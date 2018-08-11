require 'h2/server/stream'

module H2
  class Server

    # handles reading data from the +@socket+ into the +HTTP2::Server+ +@parser+,
    # callbacks from the +@parser+, and closing of the +@socket+
    #
    class Connection

      # each +@parser+ event method is wrapped in a block to call a local instance
      # method of the same name
      #
      PARSER_EVENTS = [
        :frame,
        :stream,
        :goaway
      ]

      # include FrameDebugger

      attr_reader :parser, :server, :socket

      def initialize socket:, server:
        @socket   = socket
        @server   = server
        @parser   = ::HTTP2::Server.new
        @attached = true

        # set a default stream handler that raises +NotImplementedError+
        #
        @each_stream = ->(s){ raise NotImplementedError }

        yield self if block_given?

        bind_events

        Logger.debug "new H2::Connection: #{self}" if H2.verbose?
      end

      # is this connection still attached to the server reactor?
      #
      def attached?
        @attached
      end

      # bind parser events to this instance
      #
      def bind_events
        PARSER_EVENTS.each do |e|
          on = "on_#{e}".to_sym
          @parser.on(e) { |x| __send__ on, x }
        end
      end

      # closes this connection's socket if attached
      #
      def close
        socket.close if socket && attached? && !closed?
      end

      # is this connection's socket closed?
      #
      def closed?
        socket.closed?
      end

      # prevent this server reactor from handling this connection
      #
      def detach
        @attached = false
        self
      end

      # accessor for stream handler
      #
      def each_stream &block
        @each_stream = block if block_given?
        @each_stream
      end

      # queue a goaway frame
      #
      def goaway
        server.async.goaway self
      end

      # begins the read loop, handling all errors with a log message,
      # backtrace, and closing the +@socket+
      #
      def read
        begin
          while attached? && !@socket.closed? && !(@socket.eof? rescue true)
            data = @socket.readpartial(4096)
            @parser << data
          end
          close

        rescue => e
          Logger.error "Exception: #{e.message} - closing socket"
          STDERR.puts e.backtrace if H2.verbose?
          close

        end
      end

      protected

      # +@parser+ event methods

      # called by +@parser+ with a binary frame to write to the +@socket+
      #
      def on_frame bytes
        @socket.write bytes
      rescue IOError, Errno::EPIPE => e
        Logger.error e.message
        close
      end

      # the +@parser+ calls this when a new stream has been initiated by the
      # client
      #
      def on_stream stream
        H2::Server::Stream.new connection: self, stream: stream
      end

      # the +@parser+ calls this when a goaway frame is received from the client
      #
      def on_goaway event
        close
      end

    end
  end
end
