# frozen_string_literal: true

require "spec_helper"
require_relative "../support/server_compat/falcon_server"

# standard:disable RSpec/DescribeClass -- this group documents the full live server/client integration
RSpec.describe "ApiClient served by Falcon", :server_compat do
  let(:server) { Support::ServerCompat::FalconServer.new }

  before { server.start }
  after { server.stop }

  it "makes a live request to the Rack app through Falcon" do
    response = ApiClient::Base.new(service_uri: server.base_url).get("/health")

    expect(response).to have_attributes(status: 200, body: '{"status":"ok"}')
  end
  # standard:enable RSpec/DescribeClass
end
