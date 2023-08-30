require "timecop"

Timecop.safe_mode = true

RSpec.configure do |config|
  config.after do
    Timecop.return
  end
end
