#!/usr/bin/env ruby
# Run with: bundle exec examples/server/https_hello_world.rb

require 'bundler/setup'
require 'h2/server'

# hello world TLS example
#
# NOTE: this is a TLS-enabled "h2" type of HTTP/2 server. we will need some
#       cryptography to get going. this will check for the existence of a git-
#       ignored set of testing CA, server, and client certs/keys, creating
#       them as needed.
#
#       see: test/support/create_certs.rb
#
certs_dir    = File.expand_path '../../../tmp/certs', __FILE__
ca_file      = certs_dir + '/ca.crt'
create_certs = File.expand_path '../../../test/support/create_certs', __FILE__
require create_certs unless File.exist? ca_file

# crank up the logger level for testing/example purposes
#
H2::Logger.level = ::Logger::DEBUG

port = 1234
addr = Socket.getaddrinfo('localhost', port).first[3]
puts "*** Starting server on https://localhost:#{port}"

# if not using SNI, we may pass the underlying opts directly, and the same TLS
# cert/key will be used for all incoming connections.
#
tls = {
  cert: certs_dir + '/server.crt',
  key:  certs_dir + '/server.key',
  # :extra_chain_cert => certs_dir + '/chain.pem'
}

# create h2 server on the given address and port using the given certificate
# and private key for all TLS negotiation. the constructor requires a block
# that will be called on each connection.
#
s = H2::Server::HTTPS.new host: addr, port: port, **tls do |connection|

  # each connection will have 0 or more streams, so we must give the
  # connection a stream handler block via the +#each_stream+ method.
  #
  connection.each_stream do |stream|

    # check the request path (HTTP/2 psuedo-header ':path')
    #
    # see +H2::Server::Stream#request+ - access the +H2::Server::Stream::Request+ instance
    #
    if stream.request.path == '/favicon.ico'

      # since this is a TLS-enabled server, we could actually test it with a
      # real browser, which will undoubtedly request /favicon.ico.
      #
      # see +H2::Server::Stream#respond+
      #
      stream.respond status: 404

    else

      # since HTTP/2 connections are sort of intrinsically "keep-alive", we
      # tell the client to close when this stream is complete with a GOAWAY frame
      #
      stream.goaway_on_complete

      # we respond with 200 and a "hello, world\n" body
      #
      # see +H2::Server::Stream#respond+
      #
      stream.respond status: 200, body: "hello, world!\n"
    end
  end
end

# now that our server reactor (Celluloid::IO instance) is configured and listening,
# we can put the "main" thread to sleep.
#
sleep
