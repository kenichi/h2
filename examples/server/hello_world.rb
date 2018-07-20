#!/usr/bin/env ruby
# Run with: bundle exec examples/server/hello_world.rb

require 'bundler/setup'
require 'h2/server'

H2::Logger.level = ::Logger::DEBUG
H2.verbose!

addr, port = '127.0.0.1', 1234

puts "*** Starting server on http://#{addr}:#{port}"
s = H2::Server::HTTP.new host: addr, port: port do |connection|
  connection.each_stream do |stream|
    stream.respond :ok, "hello, world!\n"
    stream.connection.goaway
  end
end

sleep
