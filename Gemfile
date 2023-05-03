source "https://rubygems.org"

# Ruby version enforced locally via .tool-versions (rv/mise/asdf).
# CI matrix tests across 3.2, 3.3, 3.4.
# Gemspec declares required_ruby_version >= 3.2.0.

# Load runtime dependencies from gemspec file
gemspec

group :development do
  # Developer Experience
  gem "bond", ">= 0.5"
  gem "amazing_print", ">= 1.6"  # pretty print (maintained fork of awesome_print)
  gem "interactive_editor", ">= 0.0.12"

  # fast-ruby idioms (mostly deprecated by YJIT)
  # see RUBY_YJIT_ENABLE=1 in .envrc
  # gem "fasterer", ">= 0.11", require: false

  # Enhanced REPL (interactive exploration)
  gem "irb", ">= 1.14"

  # Caller info for debugging
  gem "binding_of_caller", ">= 1.0"

  # Git hooks manager
  gem "overcommit", ">= 0.68", require: false

  # Markdown linting (npm:markdownlint-cli2 — but pure Ruby)
  gem "mdl", ">= 0.13", require: false

  # Code review runner (integrates with CI)
  gem "pronto", ">= 0.11", require: false

  # Danger for PR automation
  gem "danger", ">= 9.5", require: false
  gem "danger-rubocop", ">= 0.13", require: false
end

group :test do
  # api-client integrates with Rails but does not require it for operations
  gem "rails", "~> 8.0"
  gem "rspec-rails", ">= 7.0"  # Rails-specific RSpec matchers

  # HTTP servers for integration tests
  gem "falcon", ">= 0.54"      # Async fiber-based server
  gem "puma", ">= 7.2"         # Thread-based server
end

group :development, :test do
  # Modern debugging (replaces pry/byebug for Ruby 3.1+)
  # https://railsatscale.com/2025-03-14-ruby-debugging-tips-and-recommendations-2025/
  gem "debug", ">= 1.11", require: "debug/prelude"

  # Linting: Standard Ruby
  gem "standard", ">= 1.53", require: false
  gem "standard-rspec", ">= 0.4"
  gem "standard-thread_safety", ">= 1.0"
  gem "rubocop-performance", ">= 1.24", require: false

  # Code quality analysis
  gem "flay", ">= 2.14", require: false      # duplicate code detection
  gem "flog", ">= 4.8", require: false       # complexity scoring (ABC metric)
  gem "reek", ">= 6.5", require: false       # code smell detection
  gem "rubycritic", ">= 4.9", require: false # code quality reports (combines reek, flay, flog)
  gem "skunk", ">= 0.5", require: false      # tech debt scoring (StinkScore)

  # Code coverage/usage:
  # prod == coverband.gem
  # spec == mutant-rspec.gem
  gem "mutant-rspec", ">= 0.12", require: false  # mutation testing

  # Testing
  gem "rspec", ">= 3.13"       # BDD-ish spec/test framework
  gem "factory_bot", ">= 6.5"  # factory pattern
  gem "faker", ">= 3.6"        # random data for sparse edge-case detection
  gem "rantly", ">= 2.0"       # property-based testing (3.0+ needs Ruby >= 3.3)
  gem "timecop", ">= 0.9"      # time manipulation
  gem "toxiproxy", ">= 2.0"    # chaos/fault injection
  gem "webmock", ">= 3.26"     # HTTP stubbing

  # Benchmarks/Observe ability/Performance
  gem "benchmark", ">= 0.5"       # performance benchmarks
  gem "benchmark-ips", ">= 2.14"  # iterations per second
  gem "cgi"                       # Ruby 4.0 compat (rack-mini-profiler dep)
  gem "rack-mini-profiler"        # web request profiling
  gem "ruby-prof"                 # trace, detailed call graphs
  gem "memory_profiler"           # allocation tracking

  # Optional concurrency adapters (runtime deps are in gemspec)
  gem "async", ">= 2.36"
  gem "async-http", ">= 0.94"
  gem "concurrent-ruby", ">= 1.3"
  gem "typhoeus", ">= 1.4"
  gem "faraday-typhoeus", ">= 1.1"

  # Optional JWT support
  # jwt 3.1.2 is incompatible with Ruby 4.0 + openssl 4.0 (jwt/ruby-jwt#706).
  # Pin to HEAD until a release ships the fix.
  if RUBY_VERSION >= "4.0"
    gem "jwt", github: "jwt/ruby-jwt", branch: "main"
  else
    gem "jwt", ">= 2.7"
  end

  # Stdlib FFI (libffi wrapper) — zero-overhead syscalls from pure Ruby.
  # Used by SystemInfo for Mach task_info (macOS) / procfs (Linux) RSS
  # sampling, replacing fork/exec `ps` shell-outs in benchmarks.
  # Risk: operates outside Ruby memory safety — type mismatches or
  # wrong struct layouts cause segfaults, not exceptions.
  # Reward: eliminates fork/exec (~2ms) per RSS sample (20+ calls/run).
  gem "fiddle", ">= 1.1"
end
