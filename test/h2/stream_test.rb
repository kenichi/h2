require File.expand_path '../../test_helper', __FILE__

class H2::StreamTest < H2::WithServerTest

  def test_basic_stream
    @stream = @client.get path: '/'
    @stream.block!
    assert !!@stream
    assert String === @stream.body
    assert_equal @client, @stream.client
    assert Hash === @stream.headers
    assert @stream.parent.nil?
    assert Set === @stream.pushes
    assert @stream.pushes.empty?
    assert HTTP2::Stream === @stream.stream
  end

  def test_bindings
    mock = Minitest::Mock.new
    H2::Stream::STREAM_EVENTS.each {|e| mock.expect e, nil }
    s = @client.get path: '/' do |_s|
      H2::Stream::STREAM_EVENTS.each do |e|
        _s.on(e){ mock.__send__ e }
      end
    end
    s.block!
    @client.block!
    mock.verify
  end

  def test_ok?
    @stream = @client.get path: '/'
    @stream.block!
    assert @stream.ok?
    self.handler = ->(s){ s.respond status: 404; s.connection.goaway }
    s = @client.get path: '/'
    s.block!
    refute s.ok?
  end

  def test_closed?
    mutex = Mutex.new
    condition = ConditionVariable.new
    self.handler = proc do |s|
      s.respond status: 200
      s.connection.goaway
      sleep 0.25
      mutex.synchronize { condition.signal }
    end
    s = @client.get path: '/'
    mutex.synchronize { condition.wait(mutex) }
    assert s.closed?
  end

  def test_pushes
    self.handler = proc do |s|
      s.push_promise path: '/ohai', headers: {'content-type' => 'text/plain'}, body: 'thar'
      s.respond status: 200
    end
    s = @client.get path: '/'
    s.block!
    @client.goaway!
    @client.block!
    refute s.pushes.empty?
    p = s.pushes.first
    assert_equal s, p.parent
    assert p.push?
    assert p.headers.has_key? 'content-type'
    assert_equal 'text/plain', p.headers['content-type']
    assert_equal 'thar', p.body
    assert_equal '', s.body
  end

  def test_rst_stream_on_push_header
    self.handler = proc do |s|
      pp = s.push_promise_for path: '/ohai', headers: {'etag' => '12345'}, body: 'thar'
      pp.make_on s
      s.respond status: 200
      Celluloid.sleep 1
      pp.keep
    end
    s = @client.get path: '/' do |_s|
      _s.on :promise_headers do |h|
        _s.cancel! if h['etag'] == '12345'
      end
    end
    s.block!
    @client.goaway!
    @client.block!
    assert s.pushes.empty?
  end

  def test_gzip_content_encoding
    self.handler = ->(s){ s.respond status: 200, body: 'ohai' }
    gzipped = Zlib.gzip 'ohai'
    @stream = @client.get path: '/',
                          headers: { H2::ACCEPT_ENCODING_KEY => H2::GZIP_ENCODING }
    @stream.block!
    assert @stream.ok?
    assert_equal gzipped.length, @stream.headers[H2::CONTENT_LENGTH_KEY].to_i
    assert_equal 'ohai', @stream.body
  end

  def test_deflate_content_encoding
    self.handler = ->(s){ s.respond status: 200, body: 'ohai' }
    deflated = Zlib.deflate 'ohai'
    @stream = @client.get path: '/',
                          headers: { H2::ACCEPT_ENCODING_KEY => H2::DEFLATE_ENCODING }
    @stream.block!
    assert @stream.ok?
    assert_equal deflated.length, @stream.headers[H2::CONTENT_LENGTH_KEY].to_i
    assert_equal 'ohai', @stream.body
  end

end
