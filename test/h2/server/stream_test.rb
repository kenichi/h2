require File.expand_path '../../../test_helper', __FILE__

class ServerStreamTest < Minitest::Test
  include H2::MockStream

  def test_construction_event_binding
    c = Object.new
    s = stream
    str = H2::Server::Stream.new connection: c, stream: s
    assert_equal c, str.connection
    assert_instance_of Set, str.push_promises
    assert str.push_promises.empty?
    s.expect :==, true, [s]
    assert_equal s, str.stream
    s.verify
  end

  def test_create_new_request_on_active
    s = stream
    str = H2::Server::Stream.new connection: nil, stream: s
    assert_nil str.request
    str.__send__ :on_active
    assert_instance_of H2::Server::Stream::Request, str.request
  end

  def test_merges_incoming_headers_into_request
    s = stream
    str = H2::Server::Stream.new connection: nil, stream: s
    str.__send__ :on_active
    assert_instance_of H2::Server::Stream::Request, str.request
    str.__send__ :on_headers, {foo: 'bar'}
    assert_equal 'bar', str.request.headers[:foo]
  end

  def test_append_data_to_request
    s = stream
    str = H2::Server::Stream.new connection: nil, stream: s
    str.__send__ :on_active
    assert_instance_of H2::Server::Stream::Request, str.request
    str.__send__ :on_data, 'ohai'
    assert_equal 'ohai', str.request.body
  end

  def test_calls_handle_stream_async_on_server_on_half_close
    c = Minitest::Mock.new
    c.expect :server, c
    c.expect :async, c
    c.expect :handle_stream, nil, [H2::Server::Stream]

    s = stream
    str = H2::Server::Stream.new connection: c, stream: s
    str.__send__ :on_active
    str.__send__ :on_half_close
  end

end
