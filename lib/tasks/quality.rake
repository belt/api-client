require "fileutils"
require_relative "../../config/production_scope"

COVERAGE_RESULTSET = "coverage/.resultset.json"
COVERAGE_MAX_AGE = 86_400 # 24 hours

namespace :quality do
  desc "Audit string literals"
  task :string_literals do |_ok, _|
    micro_env = "RUBYOPT='--enable=frozen-string-literal --debug=frozen-string-literal'"
    sh "#{micro_env} ore exec rake"
  end

  desc "Run reek (code smells)"
  task :reek do
    sh "ore exec reek #{ProductionScope.to_args}" do |ok, _|
      puts "Reek found code smells" unless ok
    end
  end

  desc "Run flay (duplicate code)"
  task :flay do
    sh "ore exec flay #{ProductionScope.to_args}" do |ok, _|
      puts "Flay found duplicates" unless ok
    end
  end

  desc "Run flog (complexity scoring)"
  task :flog do
    sh "ore exec flog -g #{ProductionScope.to_args}"
  end

  desc "Run flog with details (methods > 10)"
  task :flog_detail do
    sh "ore exec flog -d #{ProductionScope.to_args}"
  end

  desc "Run flog on single file"
  task :flog_file, [:path] do |_, args|
    path = args[:path] || ProductionScope.to_args
    sh "ore exec flog -d #{path}"
  end

  desc "Run ore audit (security)"
  task :audit do
    sh "ore audit"
  end

  desc "Run ore audit (alias for audit_full compatibility)"
  task audit_full: %i[audit]

  desc "Run rubycritic (combined quality report)"
  task :critic do
    sh "ore exec rubycritic #{ProductionScope.to_args} --no-browser --format console"
  end

  desc "Run rubycritic with HTML report"
  task :critic_html do
    sh "ore exec rubycritic #{ProductionScope.to_args} --no-browser"
    puts "Report: tmp/rubycritic/overview.html"
  end

  desc "Run skunk (tech debt scoring)"
  task :skunk do
    sh "ore exec skunk #{ProductionScope.to_args}"
  end

  desc "Run all quality checks"
  task :all do
    now = Time.now.utc
    if now.day == 1 && now.hour < 3
      Rake::Task["quality:audit_update"].invoke
    end

    Rake::Task["quality:ensure_coverage"].invoke
    %w[audit critic skunk].each { |t| Rake::Task["quality:#{t}"].invoke }
  end

  desc "Ensure coverage data exists and is recent"
  task :ensure_coverage do
    stale = if File.exist?(COVERAGE_RESULTSET)
      age = Time.now - File.mtime(COVERAGE_RESULTSET)
      if age > COVERAGE_MAX_AGE
        puts "Coverage data is #{(age / 3600).round(1)}h old (max #{COVERAGE_MAX_AGE / 3600}h), refreshing..."
        true
      else
        false
      end
    else
      puts "No coverage data found, running specs with coverage..."
      true
    end

    if stale
      Rake::Task["coverage:run"].invoke
      Rake::Task["quality:sync_coverage"].invoke
    end
  end

  desc "Sync coverage resultset to where skunk expects it"
  task :sync_coverage do
    source = "tmp/coverage/.resultset.json"
    return unless File.exist?(source)

    FileUtils.mkdir_p("coverage")
    FileUtils.cp(source, COVERAGE_RESULTSET)
    puts "Synced coverage data to #{COVERAGE_RESULTSET}"
  end
end
