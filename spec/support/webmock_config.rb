# frozen_string_literal: true

# Selective WebMock adapter loading
#
# `require "webmock"` loads ALL HTTP adapters unconditionally, including
# async_http_client_adapter which pulls in the entire async gem stack (~6s).
# This project only needs net_http (Faraday) and typhoeus adapters.
# Async tests use Async::HTTP::Mock directly (see support/mock_http_helper.rb).

# WebMock core (no adapters)
require "singleton"
require "addressable/uri"
require "addressable/template"

require "webmock/deprecation"
require "webmock/version"
require "webmock/errors"
require "webmock/util/query_mapper"
require "webmock/util/uri"
require "webmock/util/headers"
require "webmock/util/hash_counter"
require "webmock/util/hash_keys_stringifier"
require "webmock/util/values_stringifier"
require "webmock/util/parsers/json"
require "webmock/util/parsers/xml"
require "webmock/util/version_checker"
require "webmock/util/hash_validator"
require "webmock/matchers/hash_argument_matcher"
require "webmock/matchers/hash_excluding_matcher"
require "webmock/matchers/hash_including_matcher"
require "webmock/matchers/any_arg_matcher"
require "webmock/request_pattern"
require "webmock/request_signature"
require "webmock/responses_sequence"
require "webmock/request_stub"
require "webmock/response"
require "webmock/rack_response"
require "webmock/stub_request_snippet"
require "webmock/request_signature_snippet"
require "webmock/request_body_diff"
require "webmock/assertion_failure"
require "webmock/request_execution_verifier"
require "webmock/config"
require "webmock/callback_registry"
require "webmock/request_registry"
require "webmock/stub_registry"
require "webmock/api"

# Adapter registry + base class
require "webmock/http_lib_adapters/http_lib_adapter_registry"
require "webmock/http_lib_adapters/http_lib_adapter"

# Only the adapters this project uses:
require "webmock/http_lib_adapters/net_http"           # Faraday default
require "webmock/http_lib_adapters/typhoeus_hydra_adapter"

# Skipped (unused, saves ~6.7s boot):
# - async_http_client_adapter (async tests use Async::HTTP::Mock)
# - httpclient_adapter
# - patron_adapter
# - curb_adapter
# - em_http_request_adapter
# - http_rb_adapter
# - excon_adapter
# - manticore_adapter

require "webmock/webmock"

# RSpec integration (replaces require "webmock/rspec")
# Load matcher files directly — webmock/rspec/matchers does `require 'webmock'`
# which pulls ALL adapters (including async) and adds ~6s boot time.
require "webmock/rspec/matchers/request_pattern_matcher"
require "webmock/rspec/matchers/webmock_matcher"

module WebMock
  module Matchers
    def have_been_made
      WebMock::RequestPatternMatcher.new
    end

    def have_been_requested
      WebMock::RequestPatternMatcher.new
    end

    def have_not_been_made
      WebMock::RequestPatternMatcher.new.times(0)
    end

    def have_requested(method, uri)
      WebMock::WebMockMatcher.new(method, uri)
    end

    def have_not_requested(method, uri)
      WebMock::WebMockMatcher.new(method, uri).times(0)
    end
  end
end

RSpec.configure do |config|
  config.include WebMock::API
  config.include WebMock::Matchers

  config.before(:suite) { WebMock.enable! }
  config.after(:suite) { WebMock.disable! }
  config.around { |example|
    example.run
    WebMock.reset!
  }
end

WebMock::AssertionFailure.error_class = RSpec::Expectations::ExpectationNotMetError

# Allow localhost for TestServer, block external requests
WebMock.disable_net_connect!(
  allow_localhost: true,
  allow: [
    /127\.0\.0\.1/,
    /localhost/
  ]
)
