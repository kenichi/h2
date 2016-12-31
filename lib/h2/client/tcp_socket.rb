require 'socket'

module H2
  class Client
    class TCPSocket < ::Socket

      DEFAULT_TIMEOUT = 10
      # ON_LINUX = !!(RUBY_PLATFORM =~ /linux/)

      attr_reader :selector

      def initialize addr, port, timeout = DEFAULT_TIMEOUT

        # resolve name & pack addr
        family, addr = Socket.getaddrinfo(addr, port, nil, :STREAM, nil, AI_ALL).first.values_at(0,3)
        sockaddr = Socket.sockaddr_in port, addr

        super family, SOCK_STREAM

        # allow send before ack
        setsockopt IPPROTO_TCP, TCP_NODELAY, 1

        # cork on linux
        # setsockopt IPPROTO_TCP, TCP_CORK, 1 if ON_LINUX

        if connect_nonblock(sockaddr, exception: false) == :wait_writable
          if IO.select nil, [self], nil, timeout
            begin
              connect_nonblock sockaddr
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

      end

    end
  end
end
