module ApiClientHelpers
  def reset_api_client_configuration!
    ApiClient.reset_configuration!
  end

  def with_configuration(**options)
    original = ApiClient.configuration.dup
    options.each { |k, v| ApiClient.configuration.public_send(:"#{k}=", v) }
    yield
  ensure
    ApiClient.instance_variable_set(:@configuration, original)
  end
end

RSpec.configure do |config|
  config.include ApiClientHelpers

  config.before do
    reset_api_client_configuration!
  end
end
