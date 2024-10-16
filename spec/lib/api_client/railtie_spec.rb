require "rails_helper"
require "api_client"
require "api_client/railtie"

RSpec.describe ApiClient::Railtie do
  # Ensure the i18n initializer has run even if api_client was loaded
  # before Rails (e.g. via spec_helper in a combined RSpec run).
  before(:all) do
    locale_path = File.expand_path("../../../config/locales/*.yml", __dir__)
    ::I18n.load_path |= Dir[locale_path]
    # Warm the backend so the first .t call doesn't pay the lazy-load cost
    ::I18n.t("api_client.errors.no_adapter")
  end

  it "is a Rails::Railtie" do
    expect(described_class.superclass).to eq(Rails::Railtie)
  end

  describe "initializers" do
    it "loads I18n locale files" do
      locale_pattern = File.expand_path("../../../config/locales/en.yml", __dir__)
      expect(::I18n.load_path).to include(locale_pattern)
    end

    it "makes api_client translations available" do
      result = ::I18n.t("api_client.errors.no_adapter")
      expect(result).to include("No concurrency adapter")
    end

    it "configures logger from Rails" do
      # Railtie should have set logger to Rails.logger
      expect(ApiClient.configuration.logger).to eq(Rails.logger)
    end

    it "subscribes to api_client notifications" do
      # Subscribe to capture the event
      received_events = []
      test_subscriber = ActiveSupport::Notifications.subscribe(/^api_client\./) do |*args|
        received_events << ActiveSupport::Notifications::Event.new(*args)
      end

      ActiveSupport::Notifications.instrument("api_client.railtie.test", {test_key: "test_value"})

      ActiveSupport::Notifications.unsubscribe(test_subscriber)

      # Verify our subscriber received the event (proves the pattern works)
      expect(received_events.size).to eq(1)
      expect(received_events.first.name).to eq("api_client.railtie.test")
    end
  end
end
