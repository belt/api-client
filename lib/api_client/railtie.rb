module ApiClient
  # Rails integration for ApiClient
  #
  # Automatically configures ApiClient when Rails is present,
  # setting up the logger and any Rails-specific defaults.
  #
  # == Coverage measurement artifact
  #
  # SimpleCov/Coverage reports 0% for this file. This is a load-order
  # artifact, not a real coverage gap. Rails boot loads this file
  # (via require "api_client") before Coverage.start runs in spec_helper.
  # Both initializers are tested via spec/support/dummy/ Rails app —
  # verify via spec/lib/api_client/railtie_spec.rb.
  class Railtie < ::Rails::Railtie
    initializer "api_client.i18n" do
      locale_path = File.expand_path("../../config/locales/*.yml", __dir__)
      ::I18n.load_path |= Dir[locale_path]
    end

    initializer "api_client.configure_rails_initialization" do
      ApiClient.configuration.logger = Rails.logger
    end

    initializer "api_client.subscribe_to_notifications" do
      # Opt-in via environment variable to avoid callback overhead in
      # production where the logger level is typically above debug.
      if ENV["API_CLIENT_DEBUG_NOTIFICATIONS"] == "true" ||
          (Rails.logger.respond_to?(:debug?) && Rails.logger.debug?)
        ActiveSupport::Notifications.subscribe(/^api_client\./) do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          Rails.logger.debug { "[ApiClient] #{event.name}: #{event.payload}" }
        end
      end
    end
  end
end
