source 'https://rubygems.org'

gem 'http-2', git: 'https://github.com/kenichi/http-2', branch: 'stream_close_state'

gemspec

group :concurrent_ruby do
  gem 'concurrent-ruby'
end

group :celluloid do
  gem 'celluloid'
end

group :development, :test do
  gem 'awesome_print'
  gem 'pry-byebug'
  gem 'reel', require: 'reel/h2', git: 'https://github.com/kenichi/reel', branch: 'h2'
end
