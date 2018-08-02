#!/usr/bin/env ruby
# Run with: bundle exec examples/server/sse/sse.rb

require 'bundler/setup'
require 'h2/server'

H2::Logger.level = ::Logger::DEBUG
H2.verbose!

port         = 4430
addr         = Socket.getaddrinfo('localhost', port).first[3]
certs_dir    = File.expand_path '../../../tmp/certs', __FILE__
data, key    = Hash.new {|h,k| h[k] = ''}, nil

sni = {
  'localhost' => {
    :cert => certs_dir + '/server.crt',
    :key  => certs_dir + '/server.key',
    # :extra_chain_cert => certs_dir + '/chain.pem'
  }
}

event_sources = []

puts "*** Starting server on https://#{addr}:#{port}"
s = H2::Server::HTTPS.new host: addr, port: port, sni: sni do |connection|
  connection.each_stream do |stream|
    case stream.request.path
    when '/favicon.ico'
      stream.respond status: 404

    when '/events'
      es = stream.to_eventsource
      event_sources << es

    when '/msg'
      if stream.request.method == :post
        msg = stream.request.body
        event_sources.each {|es| es.event name: 'msg', data: msg}
        stream.respond status: 201
      else
        stream.respond status: 404
      end

    when '/sse.js'
      stream.respond status: 404,
                     body: "should have been pushed..."

    else
      stream.push_promise path: '/sse.js',
                          headers: { 'content-type' => 'application/javascript' },
                          body: data[:javascript]

      stream.respond status: 200, body: data[:html]
    end
  end
end

DATA.each_line do |l|
  if l.start_with?('@@')
    key = l.strip[2..-1].to_sym
  else
    data[key] << l
  end
end

sleep

__END__
@@html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>SSE example</title>
  <script src="/sse.js"></script>
</head>
<body>
  <form id="say">
    say: <input type="text" id="words"/>
  </form>
  <br/>
  <div><ol id="list"></ol></div>
</body>
</html>

@@javascript
document.addEventListener('DOMContentLoaded', () => {
  let sse = new EventSource('/events');
  sse.addEventListener('msg', (msg) => {
    let item = document.createElement('li');
    item.innerHTML = msg.data;
    document.getElementById('list').appendChild(item);
  });

  let w = document.getElementById('words');
  document.getElementById('say').onsubmit = (e) => {
    e.preventDefault();
    fetch('/msg', {method: 'post', body: w.value})
      .then(() => { w.value = ''; });
  };
  w.focus();
});
