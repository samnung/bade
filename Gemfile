# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'benchmark-ips', require: false

group :dev, optional: true do
  gem 'debase', require: false
  gem 'ruby-debug-ide', require: false
end

group :benchmarks, optional: true do
  gem 'flamegraph'
  gem 'ruby-prof'
end
