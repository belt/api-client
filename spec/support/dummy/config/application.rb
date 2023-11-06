require_relative "boot"

require "rails"

# Pick the frameworks you want:
require "active_model/railtie"
# require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Dummy
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Full Stack defaults:
    # config.api_only = false
    #
    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true
    config.generators.system_tests = nil

    # Minimal test app - disable unnecessary features
    config.eager_load = false
    config.cache_classes = true
    config.consider_all_requests_local = true
    config.action_controller.perform_caching = false

    # Rails 8 auto-generates secret_key_base for dev/test from tmp/local_secret.txt
    # For CI environments, set SECRET_KEY_BASE or SECRET_KEY_BASE_DUMMY env var
  end
end
