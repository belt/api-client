# Danger configuration for PR automation
# Run locally: bundle exec danger local
# CI: bundle exec danger ci
#
# Requires DANGER_GITHUB_API_TOKEN env var for GitHub integration

# ------------------------------------------------------------------------------
# PR Hygiene
# ------------------------------------------------------------------------------

# Warn if PR is too large
warn("This PR is quite large. Consider breaking it into smaller PRs.") if git.lines_of_code > 500

# Warn if no description provided
warn("Please provide a PR description.") if github.pr_body.nil? || github.pr_body.length < 10

# Warn if PR title doesn't follow conventional commits
unless github.pr_title.match?(/^(feat|fix|docs|style|refactor|perf|test|chore|ci|build|revert)(\(.+\))?!?:/)
  warn("PR title should follow conventional commits format: `type(scope): description`")
end

# ------------------------------------------------------------------------------
# File Changes
# ------------------------------------------------------------------------------

# Warn about Gemfile changes without Gemfile.lock
if git.modified_files.include?("Gemfile") && !git.modified_files.include?("Gemfile.lock")
  warn("Gemfile was modified but Gemfile.lock was not updated.")
end

# Warn about TODO/FIXME in new code
(git.modified_files + git.added_files).each do |file|
  next unless file.end_with?(".rb")
  next unless File.exist?(file)

  diff = git.diff_for_file(file)
  next unless diff

  if diff.patch.include?("TODO") || diff.patch.include?("FIXME")
    warn("#{file} contains TODO/FIXME comments. Consider creating issues instead.")
  end
end

# ------------------------------------------------------------------------------
# RuboCop Integration
# ------------------------------------------------------------------------------

# Run RuboCop on changed files only
rubocop.lint(
  files: git.modified_files + git.added_files,
  inline_comment: true,
  fail_on_inline_comment: false,
  force_exclusion: true
)

# ------------------------------------------------------------------------------
# Test Coverage (if available)
# ------------------------------------------------------------------------------

coverage_file = "tmp/coverage/coverage.json"
if File.exist?(coverage_file)
  message("📊 Coverage report available at `#{coverage_file}`")
end

# ------------------------------------------------------------------------------
# Changelog
# ------------------------------------------------------------------------------

# Remind to update changelog for features/fixes
if github.pr_title.match?(/^(feat|fix)/) && !git.modified_files.include?("CHANGELOG.md")
  warn("Consider updating CHANGELOG.md for this feature/fix.")
end
