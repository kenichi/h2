require File.expand_path '../../test_helper', __FILE__

class H2::ClientTest < H2::WithServerTest

  def count_hash count: 5, enum: H2::REQUEST_METHODS
    @mutex.synchronize do
      @count ||= enum.reduce(Hash.new) {|h, m| h[m] = count; h}
      yield @count if block_given?
    end
  end

  def count_done?
    @count.all? {|_,v| v == 0}
  end

  # ---

  def test_basic_client
    assert !!@client
    assert !!@client.socket
    refute @client.closed?
    assert @client.streams.empty?
  end

  def test_reading_starts_after_first_settings_frame_sent
    sleep 0.1; Thread.pass
    assert_equal 'sleep', @client.reader.status
    @client.on_frame_sent type: :settings,
                          stream: 0,
                          payload: [
                            [:settings_max_concurrent_streams, 10],
                            [:settings_initial_window_size, 0x7fffffff],
                          ]
    assert_equal 'run', @client.reader.status
  end

  H2::REQUEST_METHODS.each do |m|

    define_method "test_basic_#{m}_requests" do
      s = @client.__send__ m, path: '/'
      s.block!
      assert s.ok?
      assert_equal '0', s.headers['content-length']
      assert_equal '', s.body
    end

    define_method "test_#{m}_requests_with_headers" do
      @verify_headers = proc do |headers|
        assert_equal '1.2', headers['a']
        assert_equal 'two', headers['b']
        assert_equal 'true', headers['c']
      end
      s = @client.__send__ m, path: '/', headers: { a: 1.2, b: 'two', c: true }
      s.block!
      assert s.ok?
    end

    define_method "test_#{m}_requests_with_bodies" do
      @verify_body = ->(b) {assert_equal 'body data', b}
      s = @client.__send__ m, path: '/', body: 'body data'
      s.block!
      assert s.ok?
    end

    define_method "test_#{m}_requests_with_query_string" do
      @verify_headers = proc do |headers|
        assert_equal 'foo=bar&baz=bat', URI.parse(headers[H2::PATH_KEY]).query
      end
      s = @client.__send__ m, path: '/?foo=bar&baz=bat'
      s.block!
      assert s.ok?
    end

    define_method "test_#{m}_requests_with_params" do
      @verify_headers = proc do |headers|
        assert_equal 'foo=bar&baz=bat', URI.parse(headers[H2::PATH_KEY]).query
      end
      s = @client.__send__ m, path: '/', params: {foo: 'bar', baz: 'bat'}
      s.block!
      assert s.ok?
    end

    define_method "test_#{m}_requests_with_everything" do
      @verify_headers = proc do |headers|
        assert_equal '1.2', headers['a']
        assert_equal 'two', headers['b']
        assert_equal 'true', headers['c']
        assert_equal 'foo=bar&baz=bat&biz=buz', URI.parse(headers[H2::PATH_KEY]).query
      end
      @verify_body = ->(b) {assert_equal 'body data', b}
      s = @client.__send__ m, path: '/?foo=bar',
                              headers: {a: 1.2, b: 'two', c: true},
                              params: {baz: 'bat', biz: 'buz'},
                              body: 'body data'
      s.block!
      assert s.ok?
    end

  end

  def test_multiple_serial_requests
    @verify_headers = proc do |h|
      m = h[H2::METHOD_KEY].downcase.to_sym
      count_hash do |ch|
        ch[m] -= 1
        count_done?
      end
    end
    H2::REQUEST_METHODS.each do |m|
      5.times do
        s = @client.__send__ m, path: '/'
        s.block!
        assert s.ok?
        refute @client.closed? unless count_done?
      end
    end
    sleep 0.5
    assert @client.closed?
    assert count_done?
  end

  def test_multiple_parallel_requests
    c = 25
    count_hash count: c
    @verify_headers = proc do |h|
      m = h[H2::METHOD_KEY].downcase.to_sym
      ret = true
      count_hash do |ch|
        ch[m] -= 1
        ret = ch.values.all? {|e| e == 0}
      end
      ret
    end
    ts = H2::REQUEST_METHODS.map do |m|
      Thread.new do
        c.times do
          s = @client.__send__ m, path: '/'
          s.block!
          assert s.ok?
          refute @client.closed?
        end
      end
    end
    ts.each {|t| refute t.join(3).nil?}
    refute @client.closed?
    count_hash {|ch| assert ch.values.all? {|e| e == 0}}
  end

end

class H2::LazyClientTest < Minitest::Test

  def setup
    @host = '127.0.0.1'
    @port = 45670
    with_server_test = self

    @server = H2::Server::HTTP.new host: @host, port: @port do |connection|
      connection.each_stream do |stream|
        if with_server_test.handler
          with_server_test.handler[stream]
        else
          go = with_server_test.verify headers: stream.request.headers,
                                     body: stream.request.body
          stream.respond status: 200
          connection.goaway if go
        end
      end
    end
    @client = H2::Client.new host: @host, port: @port, tls: false
  end

  def test_lazy_client
    assert !!@client
    assert !@client.socket
    refute @client.closed?
    assert @client.streams.empty?
    @client.connect
    assert !!@client.socket
    refute @client.closed?
    @client.close
    assert @client.closed?
  end

  def teardown
    @client.close unless @client.closed?
    @server.terminate
    @stream_handler = nil
  end

end
