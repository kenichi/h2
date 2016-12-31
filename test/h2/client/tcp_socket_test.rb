require File.expand_path '../../../test_helper', __FILE__

class H2::Client::TCPSocketTest < Minitest::Test

  def with_socket_pair addr: '127.0.0.1', port: 45670
    server = TCPServer.new addr, port
    client = H2::Client::TCPSocket.new addr, port
    peer = server.accept
    yield peer, client
  ensure
    client.close
    peer.close
    server.close
  end

  def test_basic_write
    with_socket_pair do |peer, client|
      client.write 'hello'
      d = peer.read 5
      assert_equal 'hello', d
    end
  end

  def test_ipv6
    with_socket_pair addr: '::1' do |peer, client|
      refute client.closed?
      assert client.local_address.ipv6?
      assert_equal ::Socket::AF_INET6, client.local_address.afamily
    end
  end

end
