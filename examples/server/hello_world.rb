#!/usr/bin/env ruby
# Run with: bundle exec examples/server/hello_world.rb

require 'bundler/setup'
require 'h2/server'

# hello world example
#
# NOTE: this is a plaintext "h2c" type of HTTP/2 server. browsers probably will
# never support this, but it may be useful for testing, or for behind
# TLS-enabled proxies.

# crank up the logger level for testing/example purposes
#
H2::Logger.level = ::Logger::DEBUG

port = 1234
addr = Socket.getaddrinfo('localhost', port).first[3]
puts "*** Starting server on http://localhost:#{port}"

# create h2c server on the given address and port.
# the constructor requires a block that will be called on each connection.
#
s = H2::Server::HTTP.new host: addr, port: port do |connection|

  # each connection will have 0 or more streams, so we must give the
  # connection a stream handler block via the +#each_stream+ method.
  #
  connection.each_stream do |stream|

    # here, without checking anything about the request, we respond with 200
    # and a "hello, world\n" body
    #
    # see +H2::Server::Stream#respond+
    #
    stream.respond status: 200, body: "hello, world!\n"

    # since HTTP/2 connections are sort of intrinsically "keep-alive", we
    # tell the client to close immediately with a GOAWAY frame
    #
    # see also +H2::Server::Connection#goaway_on_complete+
    #
    stream.connection.goaway

  end
end

# now that our server reactor (Celluloid::IO instance) is configured and listening,
# we can put the "main" thread to sleep.
#
sleep
