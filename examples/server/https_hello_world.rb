#!/usr/bin/env ruby
# Run with: bundle exec examples/server/https_hello_world.rb

require 'bundler/setup'
require 'h2/server'

port       = 1234
addr       = Socket.getaddrinfo('localhost', port).first[3]
certs_dir  = File.expand_path '../../../tmp/certs', __FILE__

# if not using SNI, we may pass the underlying opts directly, and the same TLS
# cert/key will be used for all incoming connections.
#
tls = {
  cert: certs_dir + '/server.crt',
  key:  certs_dir + '/server.key',
  # :extra_chain_cert => certs_dir + '/chain.pem'
}

puts "*** Starting server on https://#{addr}:#{port}"

s = H2::Server::HTTPS.new host: addr, port: port, **tls do |connection|
  connection.each_stream do |stream|
    stream.goaway_on_complete

    if stream.request.path == '/favicon.ico'
      stream.respond status: 404
    else
      stream.respond status: 200, body: "hello, world!\n"
    end
  end
end

sleep
