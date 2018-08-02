require File.expand_path '../../../../test_helper', __FILE__

class EventSourceTest < Minitest::Test

  def test_construction
    stream  = Minitest::Mock.new
    parser  = Minitest::Mock.new
    request = Minitest::Mock.new

    stream.expect :stream, parser
    stream.expect :request, request
    request.expect :headers, {'accept' => 'text/event-stream'}
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

end
