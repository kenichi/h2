$:.unshift File.expand_path '../../lib', __FILE__
$:.unshift File.expand_path '..', __FILE__

require 'bundler/setup'
require 'celluloid/current'
Bundler.require :default, :test

require 'minitest/autorun'
require 'minitest/pride'

require 'h2/server'

Thread.abort_on_exception = true
H2::Logger.level = ::Logger::FATAL
# H2::Logger.level = ::Logger::DEBUG
# H2.verbose!

module H2

  class WithServerTest < Minitest::Test

    attr_accessor :handler

    def initialize *a
      @parent_thread = Thread.current
      @mutex = Mutex.new
      super
    end

    def setup
      @addr = '127.0.0.1'
      @port = 45670
      with_reel_test = self

      @server = H2::Server::HTTP.new host: @addr, port: @port do |connection|
        connection.each_stream do |stream|
          if with_reel_test.handler
            with_reel_test.handler[stream]
          else
            go = with_reel_test.verify headers: stream.request.headers,
                                       body: stream.request.body
            stream.respond :ok
            connection.goaway if go
          end
        end
      end
      @client = H2::Client.new addr: @addr, port: @port, tls: false
    end

    def teardown
      @client.close unless @client.closed?
      @server.terminate
      @stream_handler = nil
    end

    def verify headers:, body:
      h = b = true
      h = @verify_headers[headers] if Proc === @verify_headers
      b = @verify_body[body] if Proc === @verify_body
      h && b
    rescue => e
      @parent_thread.raise e
      true
    end

  end

  module MockStream
    def stream
      s = Minitest::Mock.new
      H2::Server::Stream::STREAM_EVENTS.each do |se|
        s.expect :on, nil, [se]
      end
      H2::Server::Stream::STREAM_DATA_EVENTS.each do |sde|
        s.expect :on, nil, [sde]
      end
      s
    end
  end

  class WithServerHandlerTest < Minitest::Test
    def setup
      @addr = '127.0.0.1'
      @port = 1234
      @url  = "http://#{@addr}:#{@port}"

      @streams = ENV['STREAMS'] ? Integer(ENV['STREAMS']) : 5
      @connections = ENV['CONNECTIONS'] ? Integer(ENV['CONNECTIONS']) : 32

      @valid = Minitest::Mock.new
    end

    def with_server handler = nil, &block
      handler ||= proc do |stream|
        stream.respond :ok
        stream.connection.goaway
      end

      block ||= ->{ H2.get url: @url, tls: false }

      begin
        server = H2::Server::HTTP.new host: @addr, port: @port, spy: false do |c|
          c.each_stream &handler
        end
        block[server]
      ensure
        server.terminate if server && server.alive?
      end
    end
  end

end

trap 'TTIN' do
  Thread.list.each do |t|
    STDERR.puts "Thread TID-#{t.object_id.to_s(36)} '#{t['label']}'"
    if t.backtrace
      STDERR.puts t.backtrace.map {|s| "\t#{s}"}
    else
      STDERR.puts "<no backtrace available>"
    end
  end
end
