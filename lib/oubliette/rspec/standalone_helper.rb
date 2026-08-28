# frozen_string_literal: true

# Boots rspec for the portable specs without loading any application code, so
# `rake oubliette:selftest` still works when the migration it is meant to verify
# has broken the host suite.
require "oubliette"
require "oubliette/rspec"

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.disable_monkey_patching!
  config.order = :random
  config.include Oubliette::RSpec::SandboxHelpers
  config.after { Oubliette::RSpec::SandboxHelpers.cleanup! }
end
