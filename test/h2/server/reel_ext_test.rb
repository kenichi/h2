require File.expand_path '../../../test_helper', __FILE__
require 'h2/reel/ext'

class ReelExtTest < Minitest::Test

  def setup
    @host = '127.0.0.1'
    @port = 45670
    @socket = ::Celluloid::IO::TCPServer.new @host, @port
  end

  def teardown
    @socket.close
  end

  def test_connection_reader_in_request
    conn = Object.new
    def conn.socket; nil; end
    req = ::Reel::Request.new nil, conn
    assert_equal conn, req.connection
  end

  def test_server_accessor_in_connection
    server = Object.new
    conn = ::Reel::Connection.new @socket, nil
    conn.server = server
    assert_equal server, conn.server
  end

  class TestServerConnection

    def initialize s, o, &c
      @callback = c
    end

    def callback conn
      @callback[conn]
    end

  end
  TestServerConnection.prepend H2::Reel::ServerConnection

  def test_server_assignment_in_callback
    expected = nil
    tsc = TestServerConnection.new nil, nil do |conn|
      expected = conn.server
    end
    conn = ::Reel::Connection.new @socket, nil
    tsc.callback conn
    assert_equal tsc, expected
  end

end
