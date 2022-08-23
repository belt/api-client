# frozen_string_literal: true

source 'https://rubygems.org'
ruby '2.7.4'

# rails console
gem 'awesome_print'
gem 'bond'
gem 'interactive_editor'
gem 'pry'
gem 'pry-nav'
# gem 'pry-remote'

# uncategorized
gem 'overcommit', require: false
gem 'pronto', require: false

group :development do
  gem 'binding_of_caller'
end

group :test do
  gem 'database_cleaner', '~> 1.7.0'
end

group :development, :test do
  # developer support
  gem 'byebug'
  gem 'fasterer', require: false
  gem 'flay', require: false
  gem 'rspec'

  # ops support
  gem 'bundler-audit'

  # rspec, factory, faker patterns and support
  gem 'faker'
  gem 'faker-bot'

  # rubocop
  # https://github.com/codeclimate/codeclimate-rubocop/branches/all?utf8=%E2%9C%93&query=channel%2Frubocop
  gem 'rubocop', '~> 1.23.0'
  gem 'rubocop-faker', '~> 1.0.0'
  gem 'rubocop-performance'
  gem 'rubocop-rspec'
end
