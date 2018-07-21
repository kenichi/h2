require 'celluloid/current'
require 'logger'
require 'reel'
require 'h2/reel/ext'
require 'h2'

module H2

  CONTENT_LENGTH_KEY = 'content-length'

  Logger = ::Logger.new STDOUT

  class << self

    def alpn?
      !jruby? && OpenSSL::OPENSSL_VERSION_NUMBER >= ALPN_OPENSSL_MIN_VERSION && RUBY_VERSION >= '2.3'
    end

    def jruby?
      return @jruby if defined? @jruby
      @jruby = RUBY_ENGINE == 'jruby'
    end

    # turn on extra verbose debug logging
    #
    def verbose!
      @verbose = true
    end

    def verbose?
      @verbose = false unless defined?(@verbose)
      @verbose
    end

  end

  # base H2 server, a direct subclass of +Reel::Server+
  #
  class Server < ::Reel::Server

    def initialize server, **options, &on_connection
      @on_connection = on_connection
      super server, options
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

    end

  end

end

require 'h2/server/connection'
require 'h2/server/https'
