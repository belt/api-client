FactoryBot.define do
  factory :api_client_configuration, class: "ApiClient::Configuration" do
    skip_create

    transient do
      service_uri { "http://localhost:8080" }
      open_timeout { 5 }
      read_timeout { 30 }
      write_timeout { 10 }
      on_error { nil }
    end

    initialize_with { new }

    after(:build) do |config, evaluator|
      config.service_uri = evaluator.service_uri
      config.open_timeout = evaluator.open_timeout
      config.read_timeout = evaluator.read_timeout
      config.write_timeout = evaluator.write_timeout
      config.on_error = evaluator.on_error if evaluator.on_error
    end

    trait :slow_timeouts do
      read_timeout { 120 }
      write_timeout { 60 }
    end

    trait :fast_timeouts do
      open_timeout { 1 }
      read_timeout { 2 }
      write_timeout { 1 }
    end

    trait :aggressive_retry do
      after(:build) do |config|
        config.retry.max = 5
        config.retry.interval = 0.1
        config.retry.backoff_factor = 1.5
      end
    end

    trait :no_retry do
      after(:build) do |config|
        config.retry.max = 0
      end
    end

    trait :sensitive_circuit do
      after(:build) do |config|
        config.circuit.threshold = 2
        config.circuit.cool_off = 5
      end
    end
  end
end
