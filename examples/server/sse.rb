#!/usr/bin/env ruby
# Run with: bundle exec examples/server/sse.rb

require 'bundler/setup'
require 'h2/server'

# SSE / event source example
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

# using SNI, we can negotiate TLS for multiple certificates based on the
# requested servername.
#
# see: https://en.wikipedia.org/wiki/Server_Name_Indication
# see: https://ruby-doc.org/stdlib-2.5.1/libdoc/openssl/rdoc/OpenSSL/SSL/SSLContext.html#servername_cb
#
certs_dir    = File.expand_path '../../../tmp/certs', __FILE__
sni = {
  'localhost' => {
    :cert => certs_dir + '/server.crt',
    :key  => certs_dir + '/server.key',
    # :extra_chain_cert => certs_dir + '/chain.pem'
  }
}

# this example is a bit more involved and requires more complicated
# html and javascript. these two vars are the base for a "poor-man's"
# implemenation of sinatra-style inline templates.
#
data, key = Hash.new {|h,k| h[k] = ''}, nil

# for example purposes, we're just going to use a top-level array for
# keeping track of connected +H2::Server::Stream::EventSource+ objects.
#
# NOTE: these are not "hijacked" sockets, like a websocket might be. since
#       streams are multiplexed over one HTTP/2 TCP connection, each object
#       only represents that stream, and should not hold up other streams
#       on the connection.
#
event_sources = []

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
    case stream.request.path
    when '/favicon.ico'

      # since this is a TLS-enabled server, we could actually test it with a
      # real browser, which will undoubtedly request /favicon.ico.
      #
      # see +H2::Server::Stream#respond+
      #
      stream.respond status: 404

    when '/events'

      # check request method
      #
      case stream.request.method
      when :get

        # respond with headers turning this stream into an event source, and
        # stash it in our top-level array.
        #
        # see +H2::Server::Stream#to_eventsource+
        # see +H2::Server::Stream::EventSource+
        #
        begin
          event_sources << stream.to_eventsource
        rescue H2::Server::StreamError
          stream.respond status: 400
        end

      when :delete

        # handle a DELETE /events request by sending a final "die" event, then
        # closing all connected event sources.
        #
        event_sources.each {|es| es.event name: 'die', data: 'later!' rescue nil }
        event_sources.each &:close
        event_sources.clear

        # respond with the 200 "ok" status
        #
        stream.respond status: 200

      else
        stream.respond status: 404
      end

    when '/msg'

      # check to make sure this is a POST request
      #
      if stream.request.method == :post

        # handle a POST /msg request and send the received body to all
        # connected event sources as the data of an event named "msg".
        #
        msg = stream.request.body
        event_sources.each {|es| es.event name: 'msg', data: msg rescue nil }

        # respond with the 201 "created" status
        #
        stream.respond status: 201

      else

        # 404 if not post
        #
        stream.respond status: 404
      end

    when '/sse.js'

      # to further the push promise example a bit, here we respond with a 404
      # if the client requests the script we've linked in the HTML. this means
      # the *only* way for a client to get that script is to receive the push.
      #
      stream.respond status: 404,
                     body: "should have been pushed..."

    else

      # initiate a push promise sub-stream, and queue the "keep" handler.
      # since a push promise may be canceled, we queue the handler on the server reactor,
      # after initiating the stream with headers, so that the client has a chance to
      # cancel with a RST_STREAM frame.
      #
      # see +H2::Server::Stream#push_promise+
      #
      stream.push_promise path: '/sse.js',
                          headers: { 'content-type' => 'application/javascript' },
                          body: data[:javascript]

      # respond with 200 and HTML body
      #
      # see +H2::Server::Stream#respond+
      #
      stream.respond status: 200, body: data[:html]

    end
  end
end

# "poor-man's" sinatra-style inline "templates"
#
DATA.each_line do |l|
  if l.start_with?('@@')
    key = l.strip[2..-1].to_sym
  else
    data[key] << l unless l.empty?
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
  <hr/>
  <input id="delete" type="button" value="close all"/>
</body>
</html>

@@javascript
//
// client code for SSE/eventsource example
//
var sse;
document.addEventListener('DOMContentLoaded', () => {

  // fire up a new EventSource instance. this will initiate the GET /events
  // request with 'text/event-stream' accept header. it will also continue to
  // try reconnecting if the connection closes enexpectedly.
  //
  sse = new EventSource('/events');

  // add event listeners as normal client JS event handler functions, where the
  // event "name" is the value given with the `name:` keyword to
  // H2::Server::Stream::EventSource#event.
  //
  sse.addEventListener('msg', (msg) => {

    // in this case, we're listening for the "msg" event and simply adding a
    // new item to the list already in the DOM with the given data.
    //
    let item = document.createElement('li');
    item.innerHTML = msg.data;
    document.getElementById('list').appendChild(item);
  });

  // since SSE will keep trying to reconnect, we want a way to signal a stop
  // to that. listen for the "die" event and close the EventSource.
  //
  sse.addEventListener('die', (e) => {
    console.log('got die event:', e.data);
    sse.close();
    console.log('closed:', sse);
    document.getElementById('words').setAttribute('disabled', 'disabled');
  });
  document.getElementById('delete').onclick = (e) => {
    fetch('/events', {method: 'delete'});
  };

  // for the sake of the example, we supply a input field/form and hijack
  // the "submit" event to post it to our server.
  //
  let w = document.getElementById('words');
  document.getElementById('say').onsubmit = (e) => {
    e.preventDefault();
    fetch('/msg', {method: 'post', body: w.value})
      .then(() => { w.value = ''; });
  };
  w.focus();
});
