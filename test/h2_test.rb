require File.expand_path '../test_helper', __FILE__

class H2Test < Minitest::Test

  def test_version
    refute_nil H2::VERSION
    assert H2::VERSION > '0.0.0'
  end

  # TODO test convenience methods

  class BlockableTest < Minitest::Test

    class Blocker
      include H2::Blockable
    end

    def setup
      @obj = Blocker.new
      @obj.init_blocking
    end

    def teardown
      @obj = nil
    end

    # ---

    def test_init_blocking
      refute_nil @obj.instance_variable_get :@mutex
      refute_nil @obj.instance_variable_get :@condition
    end

    def test_basic_blocking
      Thread.new do
        sleep 0.1
        @obj.unblock!
      end
      @obj.block!
      assert true
    end

    def test_many_threads_blocking
      mocks = Array.new(25).map do
        mock = Minitest::Mock.new
        mock.expect :after_block, nil
        Thread.new do
          @obj.block!
          mock.after_block
        end
        mock
      end
      @obj.unblock!
      sleep 0.1
      mocks.each &:verify
    end

  end

  class OnTest < Minitest::Test

    def setup
      @obj = Class.new { include H2::On }.new
    end

    def teardown
      @obj = nil
    end

    # ---

    def test_on_with_block
      @obj.on(:event){|x| nil}
      assert Proc === @obj.instance_variable_get(:@on)[:event]
    end

    def test_on_without_block
      mock = Minitest::Mock.new
      mock.expect :inside_block, nil
      @obj.on(:event){ mock.inside_block }
      @obj.on :event
      mock.verify
    end

    def test_on_without_block_args
      mock = Minitest::Mock.new
      mock.expect :inside_block, nil
      @obj.on(:event){|x| x.inside_block }
      @obj.on :event, mock
      mock.verify
    end

  end

end
