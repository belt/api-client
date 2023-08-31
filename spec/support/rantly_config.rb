# Property-based testing
# Silence Rantly property test output (must be set before requiring rantly)
ENV["RANTLY_VERBOSE"] ||= "0"
require "rantly"
require "rantly/rspec_extensions"

Rantly.default_size = 100

RSpec.configure do |config|
  config.define_derived_metadata(file_path: %r{/fuzz/}) do |metadata|
    metadata[:fuzz] = true
  end

  config.filter_run_excluding fuzz: true if ENV["SKIP_FUZZ"]
end
