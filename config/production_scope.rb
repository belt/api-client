# Single source of truth for production source paths.
# Used by: Rakefile, spec/support/coverage_config.rb
# Sync manually: .rubycritic.yml, config/mutant.yml
module ProductionScope
  SOURCE_DIRS = %w[lib/].freeze
  EXCLUDES = %w[lib/api_client/examples/].freeze

  # Expanded file list for tools that accept file args
  def self.files(glob = "**/*.rb")
    SOURCE_DIRS
      .flat_map { |dir| Dir["#{dir}#{glob}"] }
      .reject { |f| EXCLUDES.any? { |ex| f.start_with?(ex) } }
  end

  # Space-separated paths for CLI tools (reek, flay, flog, etc.)
  def self.to_args
    files.join(" ")
  end

  # Check if an absolute path is in production scope
  def self.include?(absolute_path)
    EXCLUDES.none? { |ex| absolute_path.include?(ex.delete_prefix("lib/")) }
  end
end
