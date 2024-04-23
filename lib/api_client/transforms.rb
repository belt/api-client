require "json"
require "digest"

module ApiClient
  # Shared transform registry for Ractor-based processing
  #
  # Centralizes transform logic used by RactorPool and RactorProcessor
  # to eliminate duplication and provide a single source of truth.
  #
  # @example Apply a transform
  #   Transforms.apply(:json, '{"key": "value"}')
  #   # => {"key" => "value"}
  #
  # @example Check if transform exists
  #   Transforms.valid?(:json)     # => true
  #   Transforms.valid?(:unknown)  # => false
  #
  # @example Create a recipe for extraction and transformation
  #   recipe = Transforms::Recipe.new(extract: :body, transform: :json)
  #   recipe = Transforms::Recipe.default
  #
  module Transforms
    # Specifies how to extract and transform response data
    #
    # A recipe defines the two-stage pipeline: extract data from response,
    # then apply a transformation to that data.
    #
    # @example Default recipe (extract body, parse JSON)
    #   Transforms::Recipe.default
    #
    # @example Custom recipe
    #   Transforms::Recipe.new(extract: :headers, transform: :identity)
    #
    Recipe = Data.define(:extract, :transform) do
      class << self
        # Default recipe: extract body, parse as JSON
        # @return [Recipe]
        def default
          new(extract: :body, transform: :json)
        end

        # Identity recipe: extract body, no transformation
        # @return [Recipe]
        def identity
          new(extract: :body, transform: :identity)
        end

        # Headers recipe: extract headers, no transformation
        # @return [Recipe]
        def headers
          new(extract: :headers, transform: :identity)
        end

        # Status recipe: extract status code
        # @return [Recipe]
        def status
          new(extract: :status, transform: :identity)
        end
      end
    end
    # Frozen lambdas for zero-allocation transform dispatch
    IDENTITY = ->(data) { data }.freeze
    JSON_PARSE = ->(data) { JSON.parse(data) }.freeze
    SHA256_HEX = ->(data) { Digest::SHA256.hexdigest(data) }.freeze

    REGISTRY = {
      identity: IDENTITY,
      json: JSON_PARSE,
      sha256: SHA256_HEX
    }.freeze

    class << self
      # Apply a named transform to data
      # @param transform [Symbol] Transform name
      # @param data [Object] Data to transform
      # @return [Object] Transformed data
      # @raise [ArgumentError] If transform is unknown
      def apply(transform, data)
        REGISTRY.fetch(transform) do
          raise ArgumentError, I18n.t("transforms.unknown", transform: transform)
        end.call(data)
      end

      # Check if transform is valid
      # @param transform [Symbol] Transform name
      # @return [Boolean]
      def valid?(transform)
        REGISTRY.key?(transform)
      end

      # List available transforms
      # @return [Array<Symbol>]
      def available
        REGISTRY.keys
      end
    end
  end
end
