# Native Ruby Coverage integration
# Run with: COVERAGE=1 rspec
# Output: tmp/coverage/coverage.json + terminal summary
#
# Supports Ruby 4.x features:
# - lines: line-by-line execution counts
# - branches: conditional path coverage
# - methods: method invocation tracking
# - oneshot_lines: low-overhead mode (just executed/not)

if ENV["COVERAGE"]
  require "coverage"
  require "json"
  require "fileutils"
  require_relative "../../config/production_scope"

  COVERAGE_DIR = File.expand_path("../../tmp/coverage", __dir__)

  Coverage.start(
    lines: true,
    branches: true,
    methods: true
  )

  at_exit do
    result = Coverage.result

    # Filter to lib/ files only, excluding non-production code
    lib_path = File.expand_path("../../lib", __dir__)
    lib_coverage = result.select { |path, _|
      path.start_with?(lib_path) && ProductionScope.include?(path)
    }

    # Ensure output directory exists
    FileUtils.mkdir_p(COVERAGE_DIR)

    # Write JSON for CI/tooling integration
    File.write(
      File.join(COVERAGE_DIR, "coverage.json"),
      JSON.pretty_generate(lib_coverage)
    )

    # Calculate and display summary
    total_lines = 0
    covered_lines = 0
    total_branches = 0
    covered_branches = 0
    total_methods = 0
    covered_methods = 0

    lib_coverage.each do |_file, data|
      # Line coverage
      data[:lines]&.each do |hits|
        next if hits.nil? # non-executable line

        total_lines += 1
        covered_lines += 1 if hits.positive?
      end

      # Branch coverage
      data[:branches]&.each_value do |branches|
        branches.each_value do |hits|
          total_branches += 1
          covered_branches += 1 if hits.positive?
        end
      end

      # Method coverage
      data[:methods]&.each_value do |hits|
        total_methods += 1
        covered_methods += 1 if hits.positive?
      end
    end

    line_pct = total_lines.positive? ? (covered_lines.to_f / total_lines * 100).round(1) : 0
    branch_pct = total_branches.positive? ? (covered_branches.to_f / total_branches * 100).round(1)
      : 0
    method_pct = total_methods.positive? ? (covered_methods.to_f / total_methods * 100).round(1) : 0

    puts "\n" + "=" * 60
    puts "Coverage Summary"
    puts "=" * 60
    puts format("  Lines:    %5.1f%% (%d/%d)", line_pct, covered_lines, total_lines)
    puts format("  Branches: %5.1f%% (%d/%d)", branch_pct, covered_branches, total_branches)
    puts format("  Methods:  %5.1f%% (%d/%d)", method_pct, covered_methods, total_methods)
    puts "=" * 60
    puts "Report: #{COVERAGE_DIR}/coverage.json"

    # Write SimpleCov-compatible .resultset.json for skunk/rubycritic
    # Format: { "RSpec" => { "coverage" => { file => { "lines" =>
    #   [hits...] } }, "timestamp" => ... } }
    simplecov_coverage = {}
    lib_coverage.each do |file, data|
      next unless data[:lines]

      simplecov_coverage[file] = {"lines" => data[:lines]}
    end

    resultset = {
      "RSpec" => {
        "coverage" => simplecov_coverage,
        "timestamp" => Time.now.to_i
      }
    }

    File.write(
      File.join(COVERAGE_DIR, ".resultset.json"),
      JSON.pretty_generate(resultset)
    )
  end
end
