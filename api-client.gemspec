# frozen_string_literal: true

require_relative 'lib/api-client/version'

Gem::Specification.new do |spec|
  spec.name = 'api-client'
  spec.version = ::ApiClient::VERSION
  spec.homepage = 'https://github.com/belt/api-client'
  # spec.installed_by_version = "3.0.9" if spec.respond_to? :installed_by_version

  spec.rubygems_version = '3.0.9'
  spec.required_ruby_version = Gem::Requirement.new('>= 2.6.8')
  spec.required_rubygems_version = Gem::Requirement.new('>= 3') if spec.respond_to? :required_rubygems_version=

  if spec.respond_to? :metadata=
    base_uri = "https://github.com/belt/api-client/blob/v#{spec.version}"
    meta = {
      'homepage_uri' => spec.homepage,
      'changelog_uri' => "#{base_uri}/api-client/CHANGELOG.md",
      'source_code_uri' => "#{base_uri}/api-client"
    }

    # Prevent pushing this gem to RubyGems.org. To allow pushes either set
    # the 'allowed_push_host' to allow pushing to a single host or delete
    # this section to allow pushing to any host.
    meta.merge!('allowed_push_host' => '')

    spec.metadata = meta
  end

  spec.require_paths = ['lib']
  spec.authors = ['Paul Belt']
  spec.description = 'An abstraction of abstractions for various API clients e.g. faraday'
  spec.email = ['paul.belt+github@gmail.com']
  spec.licenses = ['Apache-2.0']

  spec.summary = [
    'Where possible, standardize common configuration options e.g. timeouts,',
    'and machina e.g. connection pooling for various API clients. Acts as a',
    'standardized abstraction layer for said API clients.',
    'Currently supports: Faraday, AWS::Cognito'
  ].join(' ')

  spec.files = [
    'lib/api_client/base.rb',
    'LICENSE',
    'SECURITY.md',
    'README.md'
  ]

  dependency_versions_for = {
    runtime: {
      'activesupport': ['>= 6.0.4.4'],
      'aws-sdk-appsync': ['>= 1.50.0'],
      'aws-sdk-cognitoidentity': ['>= 1.38.0'],
      'aws-sdk-cognitoidentityprovider': ['>= 1.62.0'],
      'faraday': ['>= 2.5.2'],
      'faraday_middleware': ['>= 1.2.0'],
      'faraday-encoding': ['>= 0.0.5']
      rake: ['>= 13.0.6']
    }.transform_keys do |key|
      key.to_sym
    rescue StandardError
      key
    end
  }.freeze

  add_dependency = ->(gem_name, versions) { spec.add_dependency(gem_name, *versions) }
  add_runtime_dep = ->(gem_name, versions) { spec.add_runtime_dependency(gem_name, *versions) }

  if spec.respond_to? :specification_version
    spec.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0')
      dependency_versions_for[:runtime].each do |gem_name, versions|
        add_runtime_dep.call(gem_name, versions)
      end
    else
      dependency_versions_for[:runtime].each do |gem_name, versions|
        add_dependency.call(gem_name, versions)
      end
    end
  else
    dependency_versions_for[:runtime].each do |gem_name, versions|
      add_dependency.call(gem_name, versions)
    end
  end
end

# vim:ft=ruby
