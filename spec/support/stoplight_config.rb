require "stoplight"

RSpec.configure do |config|
  config.before(:suite) do
    # Configure Stoplight ONCE at suite start - never reconfigure
    # Reconfiguring triggers "Existing circuit breakers will not see new configuration" warning
    Stoplight.configure do |conf|
      conf.data_store = Stoplight::DataStore::Memory.new
      conf.error_notifier = ->(error) { ApiClient::Hooks.instrument(:circuit_error, error: error) }
    end

    # Mark as configured so Circuit doesn't reconfigure
    ApiClient::Circuit.instance_variable_set(:@error_notifier_configured, true)
  end

  # Circuit state isolation handled by Circuit#reset! in individual specs
  # Do NOT call Stoplight.configure in before hooks - causes warning spam
end
