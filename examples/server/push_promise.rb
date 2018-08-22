#!/usr/bin/env ruby
# Run with: bundle exec examples/server/push_promise.rb

require 'bundler/setup'
require 'h2/server'

# push promise example
#
# NOTE: this is a TLS-enabled "h2" type of HTTP/2 server. we will need some
#       cryptography to get going. this will check for the existence of a git-
#       ignored set of testing CA, server, and client certs/keys, creating
#       them as needed.
#
#       see: test/support/create_certs.rb
#
require File.expand_path '../../../test/support/create_certs', __FILE__

# crank up the logger level for testing/example purposes
#
H2::Logger.level = ::Logger::DEBUG

port = 1234
addr = Socket.getaddrinfo('localhost', port).first[3]
puts "*** Starting server on https://localhost:#{port}"

# NOTE: since we're going to try a real-world push promise, let's load up some
#       "useful" example bits to play with: full valid HTML, a PNG of a dog, and
#       some javscript. we will respond directly with the HTML, but push promise
#       the dog and js.
#
html = <<~EOHTML
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <meta charset="UTF-8">
    <title>HTTP/2 Push Promise Example</title>
  </head>
  <body>
    wait for it...
    <img src="/dog.png"/>
    <script src="/pushed.js"></script>
  </body>
  </html>
EOHTML

dog_png_file = File.expand_path '../dog.png', __FILE__
dog_png = File.read dog_png_file
dog_png_fs = File::Stat.new dog_png_file
dog_png_etag = OpenSSL::Digest::SHA.hexdigest dog_png_fs.ino.to_s +
                                              dog_png_fs.size.to_s +
                                              dog_png_fs.mtime.to_s

pushed_js = '(()=>{ alert("hello h2 push promise!"); })();'

# using SNI, we can negotiate TLS for multiple certificates based on the
# requested servername.
#
# see: https://en.wikipedia.org/wiki/Server_Name_Indication
# see: https://ruby-doc.org/stdlib-2.5.1/libdoc/openssl/rdoc/OpenSSL/SSL/SSLContext.html#servername_cb
#
certs_dir = File.expand_path '../../../tmp/certs', __FILE__
sni = {
  'localhost' => {
    :cert => certs_dir + '/server.crt',
    :key  => certs_dir + '/server.key',
    # :extra_chain_cert => certs_dir + '/chain.pem'
  },
  'example.com' => {
    :cert => certs_dir + '/example.com.crt',
    :key  => certs_dir + '/example.com.key',
    :extra_chain_cert => certs_dir + '/example.com-chain.pem'
  }
}

# create h2 server on the given address and port using the given SNI +Hash+
# for configuring TLS negotiation. the constructor requires a block that will
# be called on each connection.
#
s = H2::Server::HTTPS.new host: addr, port: port, sni: sni do |connection|

  # each connection will have 0 or more streams, so we must give the
  # connection a stream handler block via the +#each_stream+ method.
  #
  connection.each_stream do |stream|

    # check the request path (HTTP/2 psuedo-header ':path')
    #
    # see +H2::Server::Stream#request+
    #
    if stream.request.path != '/'

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

      # initiate a push promise sub-stream, and queue the "keep" handler.
      # since a push promise may be canceled, we queue the handler on the server reactor,
      # after initiating the stream with headers, so that the client has a chance to
      # cancel with a RST_STREAM frame.
      #
      # see +H2::Server::Stream#push_promise+
      #
      stream.push_promise path: '/dog.png',
                          headers: {
                            'content-type' => 'image/png',

                            # NOTE: "etag" headers are not supplied by the server.
                            #
                            'etag' => dog_png_etag

                          },
                          body: dog_png

      # instantiate a push promise sub-stream, but do not send initial headers
      # nor "keep" the promise by sending the body.
      #
      # see +H2::Server::Stream#push_promise_for+
      #
      js_promise = stream.push_promise_for path: '/pushed.js',
                                           headers: { 'content-type' => 'application/javascript' },
                                           body: pushed_js

      # have this +H2::Server::PushPromise+ initiate the sub-stream on this
      # stream by sending initial headers.
      #
      # see +H2::Server::Stream::#make_promise+
      #
      stream.make_promise js_promise

      # respond with 200 and HTML body
      #
      # see +H2::Server::Stream#respond+
      #
      stream.respond status: 200, body: html

      # we have now waited until we've sent the entire body of the original
      # response, so the client probably has received that and the push promise
      # headers for both the dog and the script. our convenient +H2::Server::Stream#push_promise+
      # method above queued the actual sending of the body on the server reactor,
      # but for `js_promise`, we must keep it ourselves. in this case, we keep
      # it "synchronously", but we may also call `#keep_async` to queue it.
      #
      # see +H2::Server::Stream::PushPromise#keep+
      # see +H2::Server::Stream::PushPromise#keep_async+
      #
      js_promise.keep

    end
  end
end

# now that our server reactor (Celluloid::IO instance) is configured and listening,
# we can put the "main" thread to sleep.
#
sleep
