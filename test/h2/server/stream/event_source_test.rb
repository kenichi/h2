require File.expand_path '../../../../test_helper', __FILE__

class EventSourceTest < Minitest::Test

  def test_construction
    stream  = Minitest::Mock.new
    parser  = Minitest::Mock.new
    request = Minitest::Mock.new

    stream.expect :stream, parser
    2.times { stream.expect :request, request }
    2.times { request.expect :headers, {'accept' => 'text/event-stream'}}
    parser.expect :headers, nil, [{':status' => '200', 'content-type' => 'text/event-stream'}]

    r = H2::Server::Stream::EventSource.new stream: stream

    yield r, stream, parser, request if block_given?

    stream.verify
    request.verify
    parser.verify
  end

  def test_event
    test_construction do |r, stream, parser, request|
      parser.expect :data, nil, ["event: foo\ndata: bar\n\n", {end_stream: false}]
      r.event name: 'foo', data: 'bar'
    end
  end

  def test_data
    test_construction do |r, stream, parser, request|
      parser.expect :data, nil, ["data: bar\n\n", {end_stream: false}]
      r.data 'bar'
    end
  end

  def test_close
    test_construction do |r, stream, parser, request|
      parser.expect :data, nil, ['']
      r.close
      assert r.closed?
    end
  end

  def test_gzip_event
    conn = Minitest::Mock.new
    server = Minitest::Mock.new
    stream  = Minitest::Mock.new
    parser  = Minitest::Mock.new
    request = Minitest::Mock.new

    stream.expect :connection, conn
    conn.expect :server, server
    server.expect :options, H2::Server::DEFAULT_OPTIONS

    stream.expect :stream, parser
    2.times { stream.expect :request, request }
    2.times { request.expect :headers, {
      'accept' => 'text/event-stream',
      H2::ACCEPT_ENCODING_KEY => H2::GZIP_ENCODING
    }}
    parser.expect :headers, nil, [{
      ':status' => '200',
      'content-type' => 'text/event-stream',
      H2::CONTENT_ENCODING_KEY => H2::GZIP_ENCODING
    }]

    r = H2::Server::Stream::EventSource.new stream: stream

    expected_data = ::Zlib.gzip "event: foo\ndata: bar\n\n"
    parser.expect :data, nil, [expected_data, {end_stream: false}]
    r.event name: 'foo', data: 'bar'

    stream.verify
    request.verify
    parser.verify
  end

  def test_deflate_event
    conn = Minitest::Mock.new
    server = Minitest::Mock.new
    stream  = Minitest::Mock.new
    parser  = Minitest::Mock.new
    request = Minitest::Mock.new

    stream.expect :connection, conn
    conn.expect :server, server
    server.expect :options, H2::Server::DEFAULT_OPTIONS

    stream.expect :stream, parser
    2.times { stream.expect :request, request }
    2.times { request.expect :headers, {
      'accept' => 'text/event-stream',
      H2::ACCEPT_ENCODING_KEY => H2::DEFLATE_ENCODING
    }}
    parser.expect :headers, nil, [{
      ':status' => '200',
      'content-type' => 'text/event-stream',
      H2::CONTENT_ENCODING_KEY => H2::DEFLATE_ENCODING
    }]

    r = H2::Server::Stream::EventSource.new stream: stream

    expected_data = ::Zlib.deflate "event: foo\ndata: bar\n\n"
    parser.expect :data, nil, [expected_data, {end_stream: false}]
    r.event name: 'foo', data: 'bar'

    stream.verify
    request.verify
    parser.verify
  end

end
