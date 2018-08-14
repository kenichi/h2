require File.expand_path '../../../../test_helper', __FILE__

class ResponseTest < Minitest::Test

  def stream
    s = Minitest::Mock.new
    s.expect :request, request
  end

  def request
    r = Minitest::Mock.new
    r.expect :headers, {}
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

  def test_constructtion_with_string_body
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

end
