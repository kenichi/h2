require File.expand_path '../../../test_helper', __FILE__

class ConnectionTest < Minitest::Test

  def parser
    p = Minitest::Mock.new
    H2::Server::Connection::PARSER_EVENTS.each do |pe|
      p.expect :on, nil, [pe]
    end
    p
  end

  def with_socket_pair &block
    host = '127.0.0.1'
    port = 45670

    server = TCPServer.new(host, port)
    client = TCPSocket.new(host, port)
    peer   = server.accept

    begin
      yield client, peer
    ensure
      server.close rescue nil
      client.close rescue nil
      peer.close   rescue nil
    end
  end

  def test_construction
    with_socket_pair do |client, peer|
      server = Object.new
      c = H2::Server::Connection.new socket: peer, server: server

      assert c.attached?
      refute c.closed?
      assert_nil c.each_stream
      assert_instance_of HTTP2::Server, c.parser
      assert_equal server, c.server
      assert_equal peer, c.socket
    end
  end

  def test_proper_detachment
    with_socket_pair do |client, peer|
      c = H2::Server::Connection.new socket: peer, server: nil
      assert_equal c, c.detach
      refute c.attached?
      c.read

      refute c.closed?

      c.close
      refute c.closed? # TODO - should this be true?
    end
  end

  def test_parser_event_binding
    p = parser
    c = H2::Server::Connection.new socket: nil, server: nil do |c|
      c.instance_variable_set :@parser, p
    end
    p.verify
  end

  def test_reading_data_from_socket_into_parser
    p = parser
    10.times { p.expect :<<, nil, [String] }

    with_socket_pair do |client, peer|
      c = H2::Server::Connection.new socket: peer, server: nil do |c|
        c.instance_variable_set :@parser, p
      end
      reader = Thread.new { c.read }
      5.times { client.write 'a'*8192}
      client.close
      reader.join
    end

    p.verify
  end

  def test_stream_construction_on_event
    stream = Minitest::Mock.new

    H2::Server::Stream::STREAM_EVENTS.each do |se|
      stream.expect :on, nil, [se]
    end

    H2::Server::Stream::STREAM_DATA_EVENTS.each do |sde|
      stream.expect :on, nil, [sde]
    end

    c = H2::Server::Connection.new socket: nil, server: nil
    c.__send__ :on_stream, stream

    stream.verify
  end

end
