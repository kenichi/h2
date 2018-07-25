require 'openssl'
require 'resolv'
require 'h2/client/tcp_socket'

module H2
  class Client
    include Blockable
    include On

    CONNECTION_EVENTS = [
      :close,
      :frame,
      :goaway,
      :promise
    ]

    ALPN_PROTOCOLS           = ['h2']
    DEFAULT_MAXLEN           = 4096
    RE_IP_ADDR               = Regexp.union Resolv::IPv4::Regex, Resolv::IPv6::Regex

    attr_accessor :last_stream
    attr_reader :client, :reader, :scheme, :socket, :streams

    def initialize host: nil, port: nil, url: nil, tls: {}
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

      @tls     = tls
      @streams = {}
      @socket  = TCPSocket.new(@host, @port)
      @socket  = tls_socket @socket if @tls
      @client  = HTTP2::Client.new

      init_blocking
      yield self if block_given?
      bind_events

      read
    end

    def closed?
      @socket.closed?
    end

    def close
      unblock!
      @socket.close unless closed?
    end

    def eof?
      @socket.eof?
    end

    def goaway!
      goaway block: true
    end

    def goaway block: false
      return false if closed?
      @client.goaway
      block! if block
    end

    def bind_events
      CONNECTION_EVENTS.each do |e|
        @client.on(e){|*a| __send__ "on_#{e}", *a}
      end
    end

    REQUEST_METHODS.each do |m|
      define_method m do |**args, &block|
        request method: m, **args, &block
      end
    end

    def request method:, path:, headers: {}, params: {}, body: nil, &block
      s = @client.new_stream
      stream = add_stream method: method, path: path, stream: s, &block
      add_params params, path unless params.empty?

      h = build_headers method: method, path: path, headers: headers
      s.headers h, end_stream: body.nil?
      s.data body if body
      stream
    end

    def stringify_headers hash
      hash.keys.each do |key|
        hash[key] = hash[key].to_s unless String === hash[key]
        hash[key.to_s] = hash.delete key unless String === key
      end
      hash
    end

    def build_headers method:, path:, headers:
      h = {
        AUTHORITY_KEY => [@host, @port.to_s].join(':'),
        METHOD_KEY    => method.to_s.upcase,
        PATH_KEY      => path,
        SCHEME_KEY    => @scheme
      }.merge USER_AGENT
      h.merge! stringify_headers(headers)
    end

    def add_stream method:, path:, stream:, &block
      @streams[method] ||= {}
      @streams[method][path] ||= []
      stream = Stream.new client: self, stream: stream, &block unless Stream === stream
      @streams[method][path] << stream
      @streams[stream.id] = stream
      stream
    end

    def add_params params, path
      appendage = path.index('?') ? '&' : '?'
      path << appendage
      path << URI.encode_www_form(params)
    end

    # ---

    def selector
      @selector ||= [@socket]
    end

    def read maxlen = DEFAULT_MAXLEN
      main = Thread.current
      @reader = Thread.new do
        begin
          _read maxlen
        rescue => e
          main.raise e
        end
      end
    end

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
              STDERR.puts 'mystery protocol error!'
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

    def read_from_socket maxlen
      @socket.read_nonblock maxlen
    rescue IO::WaitReadable
      :wait_readable
    end

    # ---

    def on_close
      on :close
      close
    end

    def on_frame bytes
      on :frame, bytes

      if ::H2::Client::TCPSocket === @socket
        total = bytes.bytesize
        loop do
          n = write_to_socket bytes
          if n == :wait_writable
            IO.select nil, @socket.selector
          elsif n < total
            bytes = bytes.byteslice n, total
          else
            break
          end
        end
      else
        @socket.write bytes
      end
      @socket.flush
    end

    def write_to_socket bytes
      @socket.write_nonblock bytes
    rescue IO::WaitWritable
      :wait_writable
    end

    def on_goaway *args
      on :goaway, *args
      close
    end

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

    module ExceptionlessIO

      def read_from_socket maxlen
        @socket.read_nonblock maxlen, exception: false
      end

      def write_to_socket bytes
        @socket.write_nonblock bytes, exception: false
      end

    end

    prepend ExceptionlessIO if H2.exceptionless_io?

  end
end
