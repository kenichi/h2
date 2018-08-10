h2 changelog
============

### 0.8.0 10 aug 2018

* fix read/settings ack race (https://httpwg.org/specs/rfc7540.html#ConnectionHeader)
* add SSE/EventSource support

### 0.7.0 2 aug 2018

* `Server::Stream::Request#path` now removes query string
* add `H2::Server::Stream::Request#query_string`
* `H2::Server::Stream::Response` body now accepts any object that `respond_to? :each`
* remove Reel completely, base from Celluloid::IO
* add SSE support

### 0.6.1 27 jul 2018

* fix race between reading and sending first frame
* make `port:` default to 443 for `H2::Client.new`

### 0.6.0 25 jul 2018

* update server API - kwargs
* update client API - addr: -> host:
* add rubydoc, update readme

### 0.5.0 21 jul 2018

* add server

### 0.4.1 17 jul 2018

* update .travis.yml for latest supported versions
* add CLI flags for threading model
* update for http-2-0.9.x (`:promise_headers`)

### 0.4.0 17 jun 2017

* downgrade required ruby version to 2.2
* update .travis.yml for latest supported versions
* refactor exceptionless IO handling to prepended modules
* refactor On#on for lack of safe-nil operator
* refactor SSL context handling for 2.2/jruby

### 0.3.1 13 may 2017

* `servername` should not be set on client socket when IP address (#1)
* add ALPN/NPN checks for minimum version of underlying OpenSSL library

### 0.3.0 10 may 2017

* update http-2 gem version >= 0.8.4 for window update state fix

### 0.2.0 7 mar 2017

* add concurrency alternates

### 0.1.1 -

* removed extra rescue/ensure in H2::Client#read

### 0.1.0 - 30 dec 2016

* initial release
* seems to work! :)
