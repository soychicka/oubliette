# frozen_string_literal: true

require "oubliette"
require_relative "rspec/sandbox"
require_relative "rspec/shared_examples"

module Oubliette
  # Test support that ships with the gem, so the same expectations can run
  # inside a host application's suite and outside it.
  module RSpec
    # Absolute paths of the portable specs. `rake oubliette:selftest` runs these
    # in their own rspec process, with no application code loaded at all.
    def self.spec_paths
      Dir[File.expand_path("rspec/specs/*_spec.rb", __dir__)]
    end
  end
end
