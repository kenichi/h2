require File.expand_path '../../../../test_helper', __FILE__

class RequestTest < Minitest::Test
  include H2::MockStream

  def test_construction_and_basic_api
    s = Minitest::Mock.new
    s.expect :connection, nil
    s.expect :respond, nil do |status:, headers:, body:|
      status == 200 && headers == {} && body == ''
    end
    s.expect :==, true, [s]
    r = H2::Server::Stream::Request.new s
    assert_equal s, r.stream
    assert_instance_of Hash, r.headers
    assert r.headers.empty?
    assert_instance_of String, r.body
    assert r.body.empty?
    assert_nil r.addr
    assert_nil r.method
    assert_nil r.path
    r.respond status: 200, headers: {}, body: ''
    s.verify
  end

  def test_access_header_keys
    mock_stream = stream
    s = H2::Server::Stream.new connection: nil, stream: mock_stream
    s.__send__ :on_active
    s.__send__ :on_headers, {
      'Content-Type' => 'application/vnd.example.com-v2+json',
      'Authorization' => 'Bearer token',
      'test_key' => 'test_value'
    }
    r = s.request
    assert_equal 'application/vnd.example.com-v2+json', r.headers[:content_type]
    assert_equal 'Bearer token', r.headers['AUTHORIZATION']
    assert_equal 'test_value', r.headers['test_key']
    mock_stream.verify
  end

  def test_returns_peer_socket_ip_address
    s = Minitest::Mock.new
    s.expect :connection, s
    s.expect :socket, s
    s.expect :peeraddr, s
    s.expect :[], 'ohai', [3]
    r = H2::Server::Stream::Request.new s
    assert_equal 'ohai', r.addr
    s.verify
  end

  def test_returns_request_method_symbol
    r = H2::Server::Stream::Request.new Object.new
    r.headers.merge! ':method' => 'GET'
    assert_equal :get, r.method
  end

  def test_returns_request_path
    r = H2::Server::Stream::Request.new Object.new
    r.headers.merge! ':path' => '/ohai'
    assert_equal '/ohai', r.path
  end

  def test_path_without_query_string
    r = H2::Server::Stream::Request.new Object.new
    r.headers.merge! ':path' => '/ohai'
    assert_equal '/ohai', r.path
  end

  def test_path_with_query_string
    r = H2::Server::Stream::Request.new Object.new
    r.headers.merge! ':path' => '/ohai?foo=bar'
    assert_equal '/ohai', r.path
  end

  def test_path_with_query_string_multi
    r = H2::Server::Stream::Request.new Object.new
    r.headers.merge! ':path' => '/ohai?foo=bar&baz=bat'
    assert_equal '/ohai', r.path
  end

end
