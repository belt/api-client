FactoryBot.define do
  factory :request_hash, class: Hash do
    skip_create

    transient do
      http_method { :get }
      path { "/health" }
      params { nil }
      headers { nil }
      body { nil }
    end

    initialize_with do
      hash = {method: http_method, path: path}
      hash[:params] = params if params
      hash[:headers] = headers if headers
      hash[:body] = body if body
      hash
    end

    trait :get_user do
      http_method { :get }
      path { "/users/#{rand(1..100)}" }
    end

    trait :get_post do
      http_method { :get }
      path { "/posts/#{rand(1..100)}" }
    end

    trait :create_user do
      http_method { :post }
      path { "/users" }
      body { {name: Faker::Name.name, email: Faker::Internet.email} }
    end

    trait :with_headers do
      headers { {"X-Custom" => Faker::Lorem.word}.freeze }
    end

    trait :with_params do
      params { {page: rand(1..10), limit: 20}.freeze }
    end
  end
end
