require 'socket'

module H2
  class Client
    class TCPSocket < ::Socket

      DEFAULT_TIMEOUT = 10
      # ON_LINUX = !!(RUBY_PLATFORM =~ /linux/)

      def initialize addr, port, timeout = DEFAULT_TIMEOUT

        # resolve name & pack addr
        family, addr = Socket.getaddrinfo(addr, port, nil, :STREAM, nil, AI_ALL).first.values_at(0,3)
        @_sockaddr = Socket.sockaddr_in port, addr

        super family, SOCK_STREAM

        # allow send before ack
        setsockopt IPPROTO_TCP, TCP_NODELAY, 1

        # cork on linux
        # setsockopt IPPROTO_TCP, TCP_CORK, 1 if ON_LINUX

        handle_wait_writable(timeout){ _connect } if _connect == :wait_writable
      end

      def selector
        @selector ||= [self]
      end

      private

      def _connect
        connect_nonblock @_sockaddr
      rescue IO::WaitWritable
        :wait_writable
      end

      def handle_wait_writable timeout, &block
        if IO.select nil, selector, nil, timeout
          begin
            handle_wait_writable(timeout, &block) if yield == :wait_writable
          rescue Errno::EISCONN
          rescue
            close
            raise
          end
        else
          close
          raise Errno::ETIMEDOUT
        end
      end

      module ExceptionlessIO

        def self.prepended base
          puts "prepending ExceptionlessIO to #{base}"
        end

        def _connect
          connect_nonblock(@_sockaddr, exception: false)
        end

      end

      prepend ExceptionlessIO if H2.exceptionless_io?

    end
  end
end
