require 'celluloid/current'
require 'celluloid/io'
require 'h2'

module H2

  CONTENT_LENGTH_KEY = 'content-length'

  # base H2 server, a +Celluoid::IO+ production
  #
  class Server
    include Celluloid::IO

    DEFAULT_OPTIONS = {
      backlog: 100,
      deflate: true,
      gzip: true
    }

    execute_block_on_receiver :initialize
    finalizer :shutdown

    attr_reader :options

    def initialize server, **options, &on_connection
      @server        = server
      @options       = DEFAULT_OPTIONS.merge options
      @on_connection = on_connection

      @server.listen @options[:backlog]
      async.run
    end

    def shutdown
      @server.close if @server
    end

    # build a new connection object, run it through the given block, and
    # start reading from the socket if still attached
    #
    def handle_connection socket
      connection = H2::Server::Connection.new socket: socket, server: self
      @on_connection[connection]
      connection.read if connection.attached?
    end

    # async stream handling
    #
    def handle_stream stream
      stream.connection.each_stream[stream]
    end

    # async push promise
    #
    def handle_push_promise push_promise
      push_promise.keep
    end

    # async goaway
    #
    def goaway connection
      sleep 0.25
      connection.parser.goaway unless connection.closed?
    end

    # 'h2c' server - for plaintext HTTP/2 connection
    #
    # NOTE: browsers don't support this and probably never will
    #
    # @see https://tools.ietf.org/html/rfc7540#section-3.4
    # @see https://hpbn.co/http2/#upgrading-to-http2
    #
    class HTTP < H2::Server

      # create a new h2c server
      #
      def initialize host:, port:, **options, &on_connection
        @tcpserver = Celluloid::IO::TCPServer.new host, port
        options.merge! host: host, port: port
        super @tcpserver, options, &on_connection
      end

      def run
        loop { async.handle_connection @server.accept }
      end

    end

  end

end

require 'h2/server/connection'
require 'h2/server/https'
