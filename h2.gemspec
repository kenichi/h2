# coding: utf-8
require File.expand_path '../lib/h2/version', __FILE__

Gem::Specification.new do |spec|
  spec.name          = "h2"
  spec.version       = H2::VERSION
  spec.authors       = ["Kenichi Nakamura"]
  spec.email         = ["kenichi.nakamura@gmail.com"]
  spec.summary       = 'an http/2 client & server based on http-2'
  spec.description   = 'a pure ruby http/2 client & server based on http-2'
  spec.homepage      = 'https://github.com/kenichi/h2'
  spec.license       = 'MIT'
  spec.bindir        = 'exe'
  spec.executables   = ['h2']
  spec.require_paths = ['lib']
  spec.files         = `git ls-files`.split.reject {|f| f.start_with? 'test', 'spec', 'features'}

  spec.required_ruby_version = '>= 2.2'

  spec.add_dependency 'http-2', '~> 0.10', '>= 0.10.0'

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 12.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
