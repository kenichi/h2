require File.expand_path '../../../../test_helper', __FILE__

class ResponseTest < Minitest::Test

  def stream req: request
    s = Minitest::Mock.new
    s.expect :request, req
  end

  def request headers: {}
    r = Minitest::Mock.new
    r.expect :headers, headers
  end

  def test_construction_with_integer_status
    s = stream
    r = H2::Server::Stream::Response.new stream: s,
                                         status: 200
    assert_equal 200, r.status
    assert_instance_of Hash, r.headers
    assert_equal 1, r.headers.length
    assert_equal 'content-length', r.headers.keys.first
    assert_equal 0, r.headers['content-length']
    assert_instance_of String, r.body
    assert r.body.empty?
  end

  def test_construction_with_string_body
    r = H2::Server::Stream::Response.new stream: stream, status: 200, body: 'ohai'
    assert_equal 'ohai', r.body
    assert_equal 4, r.headers['content-length']
  end

  def test_construction_with_headers
    r = H2::Server::Stream::Response.new stream: stream, status: 301, headers: {location: '/redirected'}
    assert_equal '/redirected', r.headers[:location]
  end

  def test_respond_on_stream
    s = stream
    expected_headers = {
      ':status'        => '200',
      'content-type'   => 'text/plain',
      'content-length' => '4'
    }
    s.expect :headers, nil, [expected_headers]
    s.expect :data, nil, ['ohai']
    r = H2::Server::Stream::Response.new stream: s,
                                         status: 200,
                                         headers: {content_type: 'text/plain'},
                                         body: 'ohai'
    assert_equal 'ohai', r.body
    assert_equal 4, r.headers['content-length']
    assert_equal 'text/plain', r.headers[:content_type]
    r.respond_on s
    s.verify
  end

  def test_gzip_response_encoding
    r = request headers: { H2::ACCEPT_ENCODING_KEY => 'gzip' }
    s = stream req: r

    expected_data = ::Zlib.gzip 'ohai'
    expected_headers = {
      ':status'          => '200',
      'content-encoding' => 'gzip',
      'content-length'   => expected_data.length.to_s,
      'content-type'     => 'text/plain',
    }

    serv = Minitest::Mock.new
    serv.expect :options, H2::Server::DEFAULT_OPTIONS
    conn = Minitest::Mock.new
    conn.expect :server, serv

    s.expect :connection, conn
    s.expect :headers, nil, [expected_headers]
    s.expect :data, nil, [expected_data]
    r = H2::Server::Stream::Response.new stream: s,
                                         status: 200,
                                         headers: {content_type: 'text/plain'},
                                         body: 'ohai'
    assert_equal expected_data, r.body
    assert_equal expected_data.length, r.headers['content-length']
    assert_equal 'text/plain', r.headers[:content_type]
    r.respond_on s
    s.verify
  end

  def test_deflate_response_encoding
    r = request headers: { H2::ACCEPT_ENCODING_KEY => 'deflate' }
    s = stream req: r

    expected_data = ::Zlib.deflate 'ohai'
    expected_headers = {
      ':status'          => '200',
      'content-encoding' => 'deflate',
      'content-length'   => expected_data.length.to_s,
      'content-type'     => 'text/plain',
    }

    serv = Minitest::Mock.new
    serv.expect :options, H2::Server::DEFAULT_OPTIONS
    conn = Minitest::Mock.new
    conn.expect :server, serv

    s.expect :connection, conn
    s.expect :headers, nil, [expected_headers]
    s.expect :data, nil, [expected_data]
    r = H2::Server::Stream::Response.new stream: s,
                                         status: 200,
                                         headers: {content_type: 'text/plain'},
                                         body: 'ohai'
    assert_equal expected_data, r.body
    assert_equal expected_data.length, r.headers['content-length']
    assert_equal 'text/plain', r.headers[:content_type]
    r.respond_on s
    s.verify
  end

end
