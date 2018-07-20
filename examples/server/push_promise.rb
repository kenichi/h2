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
push_promise = '<html>wait for it...<img src="/dog.png"/><script src="/pushed.js"></script></html>'
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
      stream.respond :not_found

    else
      stream.goaway_on_complete

      stream.push_promise '/dog.png', { 'content-type' => 'image/png' }, dog_png

      js_promise = stream.push_promise_for '/pushed.js', { 'content-type' => 'application/javascript' }, pushed_js
      js_promise.make_on stream

      stream.respond :ok, push_promise

      js_promise.keep
    end
  end
end

sleep
