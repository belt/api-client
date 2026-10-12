# Mock API fixtures

The RSpec suite must not open TCP connections. Tests that exercise API
requests use WebMock to intercept Faraday and Typhoeus calls, then dispatch
the request to these in-process Rack-compatible fixtures.

This exercises ApiClient's middleware, response handling, retries, circuit
breakers, and workflows without binding ports, starting a server thread, or
depending on network timing. Specs that need a particular failure should
prefer explicit WebMock stubs, including `to_raise` for transport errors.

The fixtures are not intended to simulate TCP behavior. Connection and read
timeouts are tested at the transport boundary with deterministic injected
errors. Two deliberately separate opt-in suites cover live transport:

- `bundle exec rspec --tag server_compat` starts minimal loopback services
  under Puma and Falcon, then makes one readable `ApiClient::Base` request to
  each. These are server/client compatibility examples, not chaos tests.
- `bundle exec rspec --tag chaos` routes requests through Toxiproxy to a tiny
  standalone TCP upstream. It exercises transport faults without depending on
  either Puma or Falcon. Start Toxiproxy first with `toxiproxy-server` (control
  API at `127.0.0.1:8474`).

Both suites are excluded from the default RSpec run. Only those tagged examples
temporarily permit HTTP to `127.0.0.1`; all other destinations remain blocked.
The examples own and clean up their loopback services and Toxiproxy proxy.
On Ruby 4, the live server compatibility specs may also show Ruby's experimental
`IO::Buffer` warning from the socket write path. ApiClient does not use
`IO::Buffer` directly, and the warning is not suppressed.

The `bundle exec rake examples:metrics` benchmark is separate from RSpec and
uses an explicitly started Puma loopback fixture because it measures complete
HTTP adapter costs, including connection reuse. It is not run by the test
suite or CI's ordinary spec command. The benchmark disables SSRF validation
only on those short-lived clients so the fixture can use its loopback address.
