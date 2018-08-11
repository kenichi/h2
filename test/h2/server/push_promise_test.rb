require File.expand_path '../../../test_helper', __FILE__
require 'colored'

class PushPromiseTest < H2::WithServerHandlerTest

  def test_push_promise_method
    2.times { @valid.expect :tap, nil }

    handler = proc do |stream|
      stream.on_complete do
        stream.connection.goaway
        @valid.tap
      end
      stream.push_promise path: '/push', body: 'promise'
      stream.respond status: 200
    end

    with_server handler do
      s = H2.get url: @url, tls: false
      s.client.block!
      assert_equal 1, s.pushes.length
      p = s.pushes.first
      assert p.headers.has_key?(':path')
      assert_equal '/push', p.headers[':path']
      assert_equal 'promise', p.body
      @valid.tap
    end

    @valid.verify
  end

  def test_push_promise_for_method
    2.times { @valid.expect :tap, nil }

    handler = proc do |stream|
      stream.on_complete do
        stream.connection.goaway
        @valid.tap
      end
      pp = stream.push_promise_for path: '/push', body: 'promise'
      pp.make_on stream
      stream.respond status: 200
      pp.keep_async
    end

    with_server handler do
      s = H2.get url: @url, tls: false
      s.client.block!
      assert_equal 1, s.pushes.length
      p = s.pushes.first
      assert p.headers.has_key?(':path')
      assert_equal '/push', p.headers[':path']
      assert_equal 'promise', p.body
      @valid.tap
    end

    @valid.verify
  end

  def test_cancel_promises_on_stream_reset
    ex = nil
    2.times { @valid.expect :tap, nil }

    handler = proc do |stream|
      begin
        stream.on_complete do
          stream.connection.goaway
          @valid.tap
        end
        pp = stream.push_promise_for path: '/push', headers: {'etag' => '1234'}, body: 'promise'
        pp.make_on stream
        stream.respond status: 200
        Celluloid.sleep 1 # wait for client to cancel
        refute pp.keep
        assert pp.canceled?
      rescue => ex
      end
    end

    with_server handler do
      c = H2::Client.new url: @url, tls: false do |client|
        client.on :promise do |p|
          p.on :headers do |h|
            if h['etag'] == '1234'
              p.cancel!
              @valid.tap
            end
          end
        end
      end
      c.get path: '/'
      c.block!
    end

    @valid.verify
    raise ex if ex
  end

end
