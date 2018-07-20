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
    s = @client.get path: '/' do |s|
      H2::Stream::STREAM_EVENTS.each do |e|
        s.on(e){ mock.__send__ e }
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
    self.handler = ->(s){ s.respond :not_found; s.connection.goaway }
    s = @client.get path: '/'
    s.block!
    refute s.ok?
  end

  def test_closed?
    mutex = Mutex.new
    condition = ConditionVariable.new
    self.handler = proc do |s|
      s.respond :ok
      s.connection.goaway
      sleep 0.25
      mutex.synchronize { condition.signal }
    end
    s = @client.get path: '/'
    mutex.synchronize { condition.wait(mutex) }
    assert s.closed?
  end

  # TODO: not implemented in reel/h2 yet
  #
  # def test_pushes
  #   self.handler = proc do |s|
  #     s.push_promise '/ohai', :text, 'thar'
  #     s.respond :ok
  #   end
  #   s = @client.get path: '/'
  #   s.block!
  #   @client.goaway!
  #   @client.block!
  #   refute s.pushes.empty?
  #   p = s.pushes.first
  #   assert_equal s, p.parent
  #   assert p.push?
  # end

  # def test_rst_stream_on_push_header
  #   self.handler = proc do |s|
  #     s.push_promise '/ohai', {some: 'data'}, 'thar'
  #     s.respond :ok
  #   end
  #   s = @client.get path: '/' do |s|
  #     s.on :headers do |h|
  #       s.cancel! if h['some'] == 'data'
  #     end
  #   end
  #   s.block!
  #   @client.goaway!
  #   @client.block!
  # end

end
