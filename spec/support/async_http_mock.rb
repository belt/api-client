module Support
  module AsyncHttpMock
    MockRequest = Struct.new(:uri, :method, :body, :headers)

    def stub_async_http(adapter)
      internet = instance_double(::Async::HTTP::Internet)
      allow(internet).to receive(:close)
      allow(internet).to receive(:call) do |method, uri, headers, body|
        request = MockRequest.new(URI(uri), method.to_s.downcase.to_sym, body, headers.to_h)
        response = MockApiHolder.instance.call(request)
        Protocol::HTTP::Response[response[:status], response[:headers], [response[:body]]]
      end
      allow(adapter).to receive(:build_internet).and_return(internet)
    end
  end
end

RSpec.configure do |config|
  config.include Support::AsyncHttpMock
end
