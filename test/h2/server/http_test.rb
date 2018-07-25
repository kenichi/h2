require File.expand_path '../../../test_helper', __FILE__

class HTTPTest < H2::WithServerHandlerTest

  def test_accepts_tcp_connections
    with_server do
      s = TCPSocket.new @addr, @port
      refute s.closed?
      s.close
    end
  end

  def test_reading_requests
    ex = nil
    2.times { @valid.expect :tap, nil }

    handler = proc do |stream|
      begin
        assert_instance_of H2::Server::Stream, stream
        r = stream.request
        assert_instance_of H2::Server::Stream::Request, r
        assert_equal :post, r.method
        assert_equal 'test_value', r.headers['test-header']
        assert_equal 'test_body', r.body
        @valid.tap
      rescue => ex
      ensure
        stream.respond status: 200
        stream.connection.goaway
      end
    end

    with_server handler do
      ::H2.post(url: @url,
                headers: {'test-header' => 'test_value'},
                body: 'test_body',
                tls: false).block!
      @valid.tap
    end

    @valid.verify
    raise ex if ex
  end

  def test_sends_responses
    2.times { @valid.expect :tap, nil }

    handler = proc do |stream|
      stream.respond status: :ok, headers: {'test-header' => 'test_value'}, body: 'test_body'
      stream.connection.goaway
      @valid.tap
    end

    with_server handler do
      s = H2.get url: @url, tls: false
      s.block!
      assert s.closed?
      assert_equal '200', s.headers[':status']
      assert_equal 'test_body'.bytesize.to_s, s.headers['content-length']
      assert_equal 'test_value', s.headers['test-header']
      assert_equal 'test_body', s.body
      @valid.tap
    end

    @valid.verify
  end

  def test_handles_many_connections
    (@connections * 2).times { @valid.expect :tap, nil }

    handler = proc do |stream|
      stream.respond status: 200
      stream.connection.goaway
      @valid.tap
    end

    mutex = Mutex.new

    with_server handler do
      clients = Array.new(@connections).map do
        mutex.synchronize do
          c = H2::Client.new addr: @addr, port: @port, tls: false
          c.get path: '/'
          c
        end
      end

      clients.each do |c|
        mutex.synchronize do
          c.block!
          assert c.last_stream.ok?
          assert c.closed?
          @valid.tap
        end
      end
    end

    @valid.verify
  end

  def test_hanldes_many_streams
    count = @streams
    @streams.times { @valid.expect :tap, nil }

    handler = proc do |stream|
      count -= 1
      stream.respond status: 200
      stream.connection.goaway if count == 0
      @valid.tap
    end

    with_server handler do
      c = H2::Client.new addr: @addr, port: @port, tls: false
      @streams.times { c.get path: '/' }
      c.block!
      assert_equal 0, count
      assert c.closed?
    end

    @valid.verify
  end

  def test_handles_many_streams_on_many_connections
    count = Hash.new @streams # count = Hash.new {|h,k| h[k] = @streams}
    (@connections * @streams).times { @valid.expect :tap, nil }

    handler = proc do |stream|
      conn = stream.connection
      count[conn] -= 1
      stream.respond status: 200
      @valid.tap
      conn.goaway if count[conn] == 0
    end

    with_server handler do
      clients = Array.new(@connections).map { H2::Client.new addr: @addr, port: @port, tls: false }
      clients.each {|c| @streams.times { c.get path: '/' }}
      clients.each &:block!
      count.each {|_,v| assert_equal 0, v }
      clients.each {|c| assert c.closed? }
    end

    @valid.verify
  end

end
