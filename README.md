# H2

[![Build Status](https://travis-ci.org/kenichi/h2.svg?branch=master)](https://travis-ci.org/kenichi/h2)

H2 is a basic, _experimental_ HTTP/2 client based on the [http-2](https://github.com/igrigorik/http-2) gem.

H2 currently uses:

* one new thread per client (see [TODO](#TODO) item 3)
* keyword arguments (>=2.0)
* exception-less socket IO (>=2.3).

## Usage

```ruby
require 'h2'

#
# --- one-shot convenience
#

stream = H2.get url: 'https://example.com'

stream.ok?     #=> true
stream.headers #=> Hash
stream.body    #=> String
stream.closed? #=> true

client = stream.client #=> H2::Client

client.closed? #=> true

#
# --- normal connection
#

client = H2::Client.new addr: 'example.com', port: 443

stream = client.get path: '/'

stream.ok?     #=> true
stream.headers #=> Hash, method blocks until stream is closed
stream.body    #=> String, method blocks until stream is closed
stream.closed? #=> true

client.closed? #=> false unless server sent GOAWAY

stream = client.get path: '/push_promise' do |s| # H2::Stream === s
  s.on :headers do |h|
    if h['ETag'] == 'some_value']
      s.cancel! # already have 
    end
  end
end

stream.block! # blocks until this stream and any associated push streams are closed

stream.ok?     #=> true
stream.headers #=> Hash
stream.body    #=> String
stream.closed? #=> true

stream.pushes #=> Set
stream.pushes.each do |pp|
  pp.parent == stream #=> true
  pp.headers          #=> Hash
  pp.body             #=> String
end

client.goaway!
```

## TODO

* [x] HTTPS / TLS
* [ ] push promise cancellation
* [ ] alternate concurrency models
* [ ] fix up CLI

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/kenichi/h2. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
