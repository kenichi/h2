# coding: utf-8
require_relative './lib/h2/version'

IGNORE = %w[ test/ spec/ features/ .gitignore .travis.yml ]

Gem::Specification.new do |spec|
  spec.name          = "h2"
  spec.version       = H2::VERSION
  spec.authors       = ["Kenichi Nakamura"]
  spec.email         = ["kenichi.nakamura@gmail.com"]
  spec.summary       = 'an http/2 client based on http-2 and modern ruby'
  spec.description   = 'a pure ruby http/2 client based on http-2 for ruby 2.3 and above'
  spec.homepage      = 'https://github.com/kenichi/h2'
  spec.license       = 'MIT'
  spec.bindir        = 'exe'
  spec.executables   = ['h2']
  spec.require_paths = ['lib']
  spec.files         = `git ls-files`.split.reject {|f| f.start_with? 'test', 'spec', 'features'}

  spec.required_ruby_version = '>= 2.3'

  spec.add_dependency 'http-2', '~> 0.8', '>= 0.8.4'
  spec.add_dependency 'colored', '1.2'

  spec.add_development_dependency "bundler", "~> 1.13"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
