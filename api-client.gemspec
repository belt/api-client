require_relative "lib/api_client/version"

Gem::Specification.new do |spec|
  spec.name = "api-client"
  spec.version = ::ApiClient::VERSION
  spec.homepage = "https://github.com/belt/api-client"
  # spec.installed_by_version = "3.0.9" if spec.respond_to? :installed_by_version

  spec.required_ruby_version = Gem::Requirement.new(">= 3.2.0")
  spec.required_rubygems_version = Gem::Requirement.new(">= 3") if spec.respond_to? :required_rubygems_version=

  if spec.respond_to? :metadata=
    base_uri = "https://github.com/belt/api-client/blob/v#{spec.version}"
    meta = {
      "homepage_uri" => spec.homepage,
      "changelog_uri" => "#{base_uri}/api-client/CHANGELOG.md",
      "source_code_uri" => "#{base_uri}/api-client"
    }

    # Prevent pushing this gem to RubyGems.org. To allow pushes either set
    # the 'allowed_push_host' to allow pushing to a single host or delete
    # this section to allow pushing to any host.
    meta["allowed_push_host"] = ""

    spec.metadata = meta
  end

  spec.require_paths = ["lib"]
  spec.authors = ["Paul Belt"]
  spec.description = "An abstraction of abstractions for various API clients e.g. faraday"
  spec.email = ["153964+belt@users.noreply.github.com"]
  spec.licenses = ["Apache-2.0"]

  spec.summary = [
    "HTTP client with parallel execution, circuit breaker, and pipeline support.",
    "Auto-detects best concurrency adapter (Typhoeus > Async > Concurrent).",
    "Returns raw Faraday responses for transparency."
  ].join(" ")

  spec.files = Dir["lib/**/*.rb"] + %w[LICENSE SECURITY.md README.md]

  # Runtime Convenience dependencies
  spec.add_runtime_dependency "activesupport", ">= 6.0"
  spec.add_runtime_dependency "zeitwerk", ">= 2.7"

  # Runtime Ikigai dependencies
  spec.add_runtime_dependency "connection_pool", ">= 2.4"
  spec.add_runtime_dependency "faraday", ">= 2.0"
  spec.add_runtime_dependency "faraday-retry", ">= 2.0"
  spec.add_runtime_dependency "nxt_registry", ">= 0.3"
  spec.add_runtime_dependency "stoplight", ">= 3.0"

  # ID slow methods and lines (prod safe)
  # Consider https://rbspy.github.io/ for outside-in prod-safe sampling profiler
  spec.add_runtime_dependency "stackprof", ">= 0.2"
end

# vim:ft=ruby
