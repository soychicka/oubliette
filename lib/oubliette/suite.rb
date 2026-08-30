# frozen_string_literal: true

require "json"

module Oubliette
  # A test suite this project actually has, and how to run it.
  #
  # The ruby invocations are predictable. The javascript ones are not -- script
  # names are whatever the project chose -- so rather than guessing at a runner
  # command, `npm test` is used where package.json declares one. That is the
  # project's own declared entry point, and it is npm convention.
  Suite = Data.define(:key, :label, :command, :counts) do
    # Every runner phrases its total differently and changes the wording between
    # major versions, so a failed parse degrades to pass or fail with a duration
    # rather than taking the run down.
    def tally(output)
      examples = counts[:examples]&.match(output)&.captures&.first
      failures = counts[:failures]&.match(output)&.captures&.first

      { examples: examples&.to_i, failures: failures&.to_i }
    end
  end

  module Suites
    RUBY_SUITES = [
      { key: "rspec", label: "rspec", gem: "rspec-rails", command: %w[bundle exec rspec],
        counts: { examples: /(\d+) examples?,/, failures: /(\d+) failures?/ } },
      { key: "cucumber", label: "cucumber", gem: "cucumber-rails", command: %w[bundle exec cucumber],
        counts: { examples: /(\d+) scenarios? \(/, failures: /(\d+) failed/ } },
      { key: "minitest", label: "minitest", gem: "minitest", command: %w[bin/rails test],
        counts: { examples: /(\d+) runs?,/, failures: /(\d+) failures?/ } }
    ].freeze

    JAVASCRIPT = {
      key: "javascript", label: "javascript", command: %w[npm test --silent],
      counts: { examples: /Tests?:\s+(\d+)/, failures: /(\d+) failed/ }
    }.freeze

    module_function

    def for(root, manifest)
      ruby(root, manifest) + javascript(root)
    end

    def ruby(root, manifest)
      RUBY_SUITES.filter_map do |suite|
        next unless manifest.gems.include?(suite[:gem])
        next if suite[:command].first.start_with?("bin/") && !root.join(suite[:command].first).exist?

        Suite.new(key: suite[:key], label: suite[:label], command: suite[:command], counts: suite[:counts])
      end
    end

    def javascript(root)
      package = root.join("package.json")
      return [] unless package.file?
      return [] unless JSON.parse(package.read).dig("scripts", "test")

      [ Suite.new(**JAVASCRIPT) ]
    rescue JSON::ParserError
      []
    end
  end
end
