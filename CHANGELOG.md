h2 changelog
============

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
