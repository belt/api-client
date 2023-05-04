begin
  require "bundler/setup"
rescue LoadError
  puts "You must `gem install bundler` and `bundle install` to run rake tasks"
end

require "rdoc/task"

RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = "rdoc"
  rdoc.title = "ApiClient"
  rdoc.options << "--line-numbers"
  rdoc.rdoc_files.include("README.md")
  rdoc.rdoc_files.include("lib/**/*.rb")
end

require "bundler/gem_tasks"

# RSpec
begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  # rspec not available
end

# Standard Ruby (zero-config linting)
begin
  require "standard/rake"
rescue LoadError
  # standard not available
end

# Load all task files from lib/tasks/
Dir[File.expand_path("lib/tasks/**/*.rake", __dir__)].each { |f| load f }

# Default task
task default: :spec

# CI task
desc "Run all checks for CI"
task ci: %i[spec standard quality:audit_full]

desc "Run CI with coverage"
task ci_coverage: %i[coverage:run standard quality:audit_full]
