# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'docker/registry/sync'

Gem::Specification.new do |spec|
  spec.name          = 'docker-registry-sync'
  spec.version       = Docker::Registry::Sync::VERSION
  spec.authors       = ['Brian Oldfield']
  spec.email         = ['brian.oldfield@socrata.com']
  spec.summary       = %q{Sync data between S3 two distinct docker registries using S3 data storage and SNS as a messaging system.}
  spec.description   = %q{Sync data between S3 two distinct docker registries using S3 data storage and SNS as a messaging system.}
  spec.homepage      = 'http://github.com/socrata-platform/docker-registry-sync'
  spec.license       = 'Apache'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/docker-registry-sync}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.7'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.3'
  spec.add_development_dependency 'simplecov', '~> 0.10'
  spec.add_development_dependency 'simplecov-console', '~> 0.2'
  spec.add_development_dependency 'webmock', '~> 1.21'
  spec.add_development_dependency 'rack', '~> 1.6'
  spec.add_dependency 'aws-sdk', '~> 2.0'
end
