require 'openssl'
require 'resolv'
require 'h2/client/tcp_socket'

module H2
  class Client
    include Blockable
    include HeaderStringifier
    include On

    PARSER_EVENTS = [
      :close,
      :frame,
      :frame_sent,
      :goaway,
      :promise
    ]

    # include FrameDebugger

    ALPN_PROTOCOLS = ['h2']
    DEFAULT_MAXLEN = 4096
    RE_IP_ADDR     = Regexp.union Resolv::IPv4::Regex, Resolv::IPv6::Regex

    attr_accessor :last_stream
    attr_reader :client, :reader, :scheme, :socket, :streams

    # create a new h2 client
    #
    # @param [String] host IP address or hostname
    # @param [Integer] port TCP port (default: 443)
    # @param [String,URI] url full URL to parse (optional: existing +URI+ instance)
    # @param [Boolean] lazy if true, awaits first stream to initiate connection (default: true)
    # @param [Hash,FalseClass] tls TLS options (optional: +false+ do not use TLS)
    # @option tls [String] :cafile path to CA file
    #
    # @return [H2::Client]
    #
    def initialize host: nil, port: 443, url: nil, lazy: true, tls: {}
      raise ArgumentError if url.nil? && (host.nil? || port.nil?)

      if url
        url     = URI.parse url unless URI === url
        @host   = url.host
        @port   = url.port
        @scheme = url.scheme
        tls     = false if 'http' == @scheme
      else
        @host = host
        @port = port
        @scheme = tls ? 'https' : 'http'
      end

      @tls       = tls
      @streams   = {}
      @client    = HTTP2::Client.new
      @read_gate = ReadGate.new

      init_blocking
      yield self if block_given?
      bind_events

      connect unless lazy
    end

    # initiate the connection
    #
    def connect
      @socket = TCPSocket.new(@host, @port)
      @socket = tls_socket socket if @tls
      read
    end

    def connected?
      !!socket
    end

    # @return true if the connection is closed
    #
    def closed?
      connected? && socket.closed?
    end

    # close the connection
    #
    def close
      unblock!
      socket.close unless closed?
    end

    def eof?
      socket.eof?
    end

    # send a goaway frame and wait until the connection is closed
    #
    def goaway!
      goaway block: true
    end

    # send a goaway frame and optionally wait for the connection to be closed
    #
    # @param [Boolean] block waits for close if +true+, returns immediately otherwise
    #
    # @return +false+ if already closed
    # @return +nil+
    #
    def goaway block: false
      return false if closed?
      @client.goaway
      block! if block
    end

    # binds all connection events to their respective on_ handlers
    #
    def bind_events
      PARSER_EVENTS.each do |e|
        @client.on(e){|*a| __send__ "on_#{e}", *a}
      end
    end

    # convenience wrappers to make requests with HTTP methods
    #
    # @see Client#request
    #
    REQUEST_METHODS.each do |m|
      define_method m do |**args, &block|
        request method: m, **args, &block
      end
    end

    # initiate a +Stream+ by making a request with the given HTTP method
    #
    # @param [Symbol] method HTTP request method
    # @param [String] path request path
    # @param [Hash] headers request headers
    # @param [Hash] params request query string parameters
    # @param [String] body request body
    #
    # @yield [H2::Stream]
    #
    # @return [H2::Stream]
    #
    def request method:, path:, headers: {}, params: {}, body: nil, &block
      connect unless connected?
      s = @client.new_stream
      add_params params, path unless params.empty?
      stream = add_stream method: method, path: path, stream: s, &block

      h = build_headers method: method, path: path, headers: headers
      s.headers h, end_stream: body.nil?
      s.data body if body
      stream
    end

    # builds headers +Hash+ with appropriate ordering
    #
    # @see https://http2.github.io/http2-spec/#rfc.section.8.1.2.1
    # @see https://github.com/igrigorik/http-2/pull/136
    #
    def build_headers method:, path:, headers:
      h = {
        AUTHORITY_KEY => [@host, @port.to_s].join(':'),
        METHOD_KEY    => method.to_s.upcase,
        PATH_KEY      => path,
        SCHEME_KEY    => @scheme
      }.merge USER_AGENT
      h.merge! stringify_headers(headers)
    end

    # creates a new stream and adds it to the +@streams+ +Hash+ keyed at both
    # the method +Symbol+ and request path as well as the ID of the stream.
    #
    def add_stream method:, path:, stream:, &block
      @streams[method] ||= {}
      @streams[method][path] ||= []
      stream = Stream.new client: self, stream: stream, &block unless Stream === stream
      @streams[method][path] << stream
      @streams[stream.id] = stream
      stream
    end

    # add query string parameters the given request path +String+
    #
    def add_params params, path
      appendage = path.index('?') ? '&' : '?'
      path << appendage
      path << URI.encode_www_form(params)
    end

    # ---

    # maintain a ivar for the +Array+ to send to +IO.select+
    #
    def selector
      @selector ||= [socket]
    end

    # creates a new +Thread+ to read the given number of bytes each loop from
    # the current +@socket+
    #
    # NOTE: initial client frames (settings, etc) should be sent first, since
    #       this is a separate thread, take care to block until this happens
    #
    # NOTE: this is the override point for celluloid actor pool or concurrent
    #       ruby threadpool support
    #
    # @param [Integer] maxlen maximum number of bytes to read
    #
    def read maxlen = DEFAULT_MAXLEN
      main = Thread.current
      @reader = Thread.new do
        @read_gate.block!
        begin
          _read maxlen
        rescue => e
          main.raise e
        end
      end
    end

    # underyling read loop implementation, handling returned +Symbol+ values
    # and shovelling data into the client parser
    #
    # @param [Integer] maxlen maximum number of bytes to read
    #
    def _read maxlen = DEFAULT_MAXLEN
      begin
        data = nil

        loop do
          data = read_from_socket maxlen
          case data
          when :wait_readable
            IO.select selector
          when NilClass
            break
          else
            begin
              @client << data
            rescue HTTP2::Error::ProtocolError => pe
              STDERR.puts "protocol error: #{pe.message}"
              STDERR.puts pe.backtrace.map {|l| "\t" + l}
            end
          end
        end

      rescue IOError, Errno::EBADF
        close
      ensure
        unblock!
      end
    end

    # fake exceptionless IO for reading on older ruby versions
    #
    # @param [Integer] maxlen maximum number of bytes to read
    #
    def read_from_socket maxlen
      socket.read_nonblock maxlen
    rescue IO::WaitReadable
      :wait_readable
    end

    # ---

    # close callback for parser: calls custom handler, then closes connection
    #
    def on_close
      on :close
      close
    end

    # frame callback for parser: writes bytes to the +@socket+, and slicing
    # appropriately for given return values
    #
    # @param [String] bytes
    #
    def on_frame bytes
      on :frame, bytes

      if ::H2::Client::TCPSocket === socket
        total = bytes.bytesize
        loop do
          n = write_to_socket bytes
          if n == :wait_writable
            IO.select nil, socket.selector
          elsif n < total
            bytes = bytes.byteslice n, total
          else
            break
          end
        end
      else
        socket.write bytes
      end
      socket.flush
    end

    # frame_sent callback for parser: used to wait for initial settings frame
    # to be sent by the client (post-connection-preface) before the read thread
    # responds to server settings frame with ack
    #
    def on_frame_sent frame
      if @read_gate.first && frame[:type] == :settings
        @read_gate.first = false
        @read_gate.unblock!
      end
    end

    # fake exceptionless IO for writing on older ruby versions
    #
    # @param [String] bytes
    #
    def write_to_socket bytes
      socket.write_nonblock bytes
    rescue IO::WaitWritable
      :wait_writable
    end

    # goaway callback for parser: calls custom handler, then closes connection
    #
    def on_goaway *args
      on :goaway, *args
      close
    end

    # push promise callback for parser: creates new +Stream+ with appropriate
    # parent, binds close event, calls custom handler
    #
    def on_promise promise
      push_promise = Stream.new client: self,
                                parent: @streams[promise.parent.id],
                                push: true,
                                stream: promise do |p|
        p.on :close do
          method = p.headers[METHOD_KEY].downcase.to_sym rescue :error
          path = p.headers[PATH_KEY]
          add_stream method: method, path: path, stream: p
        end
      end

      on :promise, push_promise
    end

    # ---

    # build, configure, and return TLS socket
    #
    # @param [TCPSocket] socket unencrypted socket
    #
    def tls_socket socket
      socket = OpenSSL::SSL::SSLSocket.new socket, create_ssl_context
      socket.sync_close = true
      socket.hostname = @host unless RE_IP_ADDR.match(@host)
      socket.connect
      socket
    end

    # builds a new SSLContext suitable for use in 'h2' connections
    #
    def create_ssl_context
      ctx                = OpenSSL::SSL::SSLContext.new
      ctx.ca_file        = @tls[:ca_file] if @tls[:ca_file]
      ctx.ca_path        = @tls[:ca_path] if @tls[:ca_path]
      ctx.ciphers        = @tls[:ciphers] || OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:ciphers]
      ctx.options        = @tls[:options] || OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:options]
      ctx.ssl_version    = :TLSv1_2
      ctx.verify_mode    = @tls[:verify_mode] || ( OpenSSL::SSL::VERIFY_PEER |
                                                   OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT )

      # https://github.com/jruby/jruby-openssl/issues/99
      set_ssl_context_protocols ctx unless H2.jruby?

      ctx
    end

    # handle protocol negotiation for older ruby/openssl versions
    #
    if H2.alpn?
      def set_ssl_context_protocols ctx
        ctx.alpn_protocols = ALPN_PROTOCOLS
      end
    else
      def set_ssl_context_protocols ctx
        ctx.npn_protocols = ALPN_PROTOCOLS
      end
    end

    # ---

    # use exceptionless IO if this ruby version supports it
    #
    module ExceptionlessIO

      def read_from_socket maxlen
        socket.read_nonblock maxlen, exception: false
      end

      def write_to_socket bytes
        socket.write_nonblock bytes, exception: false
      end

    end

    prepend ExceptionlessIO if H2.exceptionless_io?

    class ReadGate
      include Blockable

      attr_accessor :first

      def initialize
        init_blocking
        @first = true
      end
    end

  end
end
