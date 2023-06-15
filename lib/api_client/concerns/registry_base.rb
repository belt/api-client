module ApiClient
  module Concerns
    # Shared registry behavior for adapters and processors
    #
    # Provides memoized detection, availability checking, and resolution
    # for pluggable components with graceful fallback.
    #
    # @example Including in a registry module
    #   module MyRegistry
    #     extend RegistryBase
    #
    #     self.registry_items = %i[fast medium slow].freeze
    #     self.fallback_item = :slow
    #     self.item_label = "processor"
    #   end
    #
    module RegistryBase
      def self.extended(base)
        base.instance_variable_set(:@detected, nil)
        base.instance_variable_set(:@availability, nil)
        base.instance_variable_set(:@available_items, nil)
      end

      # Configuration accessors (must be set by including module)
      attr_accessor :registry_items, :fallback_item, :item_label

      # Detect best available item (memoized)
      # @return [Symbol]
      def detect
        return @detected unless @detected.nil?

        @detected = registry_items.find { |item| available?(item) } || fallback_item
      end

      # Check if specific item is available
      # @param item [Symbol]
      # @return [Boolean]
      def available?(item)
        @availability ||= {}
        return @availability[item] if @availability.key?(item)

        @availability[item] = check_availability(item)
      end

      # List all available items
      # @return [Array<Symbol>]
      def available_items
        @available_items ||= registry_items.select { |item| available?(item) }.freeze
      end

      # Reset memoized state (for testing)
      def reset!
        @detected = nil
        @availability = nil
        @available_items = nil
      end

      # Check if gem(s) are loaded (via top-level begin/rescue require)
      # @param constants [Array<String>] Top-level constant names to check
      # @return [Boolean]
      def gem_loaded?(*constants)
        constants.all? { |const| Object.const_defined?(const) }
      end
    end
  end
end
