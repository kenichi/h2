#!/usr/bin/env ruby
# Run with: bundle exec examples/server/push_promise.rb

require 'bundler/setup'
require 'h2/server'

H2::Logger.level = ::Logger::DEBUG
H2.verbose!

port         = 1234
addr         = Socket.getaddrinfo('localhost', port).first[3]
certs_dir    = File.expand_path '../../../tmp/certs', __FILE__
dog_png     = File.read File.expand_path '../dog.png', __FILE__
push_promise = '<html><body>wait for it...<img src="/dog.png"/><script src="/pushed.js"></script></body></html>'
pushed_js    = '(()=>{ alert("hello h2 push promise!"); })();'

sni = {
  'localhost' => {
    :cert => certs_dir + '/server.crt',
    :key  => certs_dir + '/server.key',
    # :extra_chain_cert => certs_dir + '/chain.pem'
  }
}

puts "*** Starting server on https://#{addr}:#{port}"
s = H2::Server::HTTPS.new host: addr, port: port, sni: sni do |connection|
  connection.each_stream do |stream|

    if stream.request.path == '/favicon.ico'
      stream.respond status: 404

    else
      stream.goaway_on_complete

      # one-line convenience with async "keep" handler
      stream.push_promise path: '/dog.png', headers: { 'content-type' => 'image/png' }, body: dog_png

      # more control over when promises are "kept"...
      js_promise = stream.push_promise_for path: '/pushed.js',
                                           headers: { 'content-type' => 'application/javascript' },
                                           body: pushed_js
      js_promise.make_on stream

      stream.respond status: 200, body: push_promise

      js_promise.keep
    end
  end
end

sleep
