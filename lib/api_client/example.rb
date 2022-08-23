# frozen_string_literal: true

require 'api_client/base'

module ApiClient
  # example for some client-library: a generic rest api e.g. faraday
  class Example < Base
    config.base_path = '/'
  end
end
