module ApiClient
  # HTTP verb constants shared across Base and Connection
  module HttpVerbs
    # HTTP verbs that don't accept a body
    BODYLESS_VERBS = %i[get head delete trace].freeze

    # HTTP verbs that accept a body
    BODY_VERBS = %i[post put patch].freeze

    # All HTTP verbs
    HTTP_VERBS = (BODYLESS_VERBS + BODY_VERBS).freeze

    # Frozen empty hash for default params/headers (avoids allocation)
    EMPTY_HASH = {}.freeze

    # Define bodyless verb methods that delegate to a target method
    # @param target [Symbol] Method to delegate to (e.g., :request, :with_circuit)
    # @param wrapper [Symbol, nil] Optional wrapper method for delegation
    def define_bodyless_verbs(target:, wrapper: nil)
      BODYLESS_VERBS.each do |verb|
        if wrapper
          define_method(verb) do |path, **opts|
            public_send(wrapper) { public_send(target).public_send(verb, path, **opts) }
          end
        else
          define_method(verb) do |path, params: EMPTY_HASH, headers: EMPTY_HASH|
            public_send(target, verb, path, params: params, headers: headers)
          end
        end
      end
    end

    # Define body verb methods that delegate to a target method
    # @param target [Symbol] Method to delegate to
    # @param wrapper [Symbol, nil] Optional wrapper method for delegation
    def define_body_verbs(target:, wrapper: nil)
      BODY_VERBS.each do |verb|
        if wrapper
          define_method(verb) do |path, **opts|
            public_send(wrapper) { public_send(target).public_send(verb, path, **opts) }
          end
        else
          define_method(verb) do |path, body: nil, params: EMPTY_HASH, headers: EMPTY_HASH|
            public_send(target, verb, path, params: params, headers: headers, body: body)
          end
        end
      end
    end

    # Define all HTTP verb methods
    # @param target [Symbol] Method to delegate to
    # @param wrapper [Symbol, nil] Optional wrapper method
    def define_http_verbs(target:, wrapper: nil)
      define_bodyless_verbs(target: target, wrapper: wrapper)
      define_body_verbs(target: target, wrapper: wrapper)
    end
  end
end
