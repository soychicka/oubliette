# frozen_string_literal: true

module Oubliette
  # The catalog is the shipped knowledge of where each test framework keeps its
  # assets by default, and where oubliette would rather they lived. It is data
  # only -- nothing here touches the filesystem. Entries are consulted in order,
  # so an earlier entry wins a directory that two frameworks both claim
  # (spec/javascript, for instance, belongs to jest before jasmine).
  module Catalog
    ROOT = "test"

    # ecosystem  :ruby | :javascript
    # kind       :data for shared test material, otherwise a test runner
    # generated  origins written by a tool: configure the destination, never move
    # manual_config    config files oubliette knows about but will not rewrite
    # manual_settings  the settings in them that name a path
    # gems       names looked for in Gemfile / Gemfile.lock
    # packages   names looked for in package.json dependencies
    # paths      directories whose mere presence proves the framework is in use
    # moves      from => to, relative to the project root
    # config     symbols naming the config writers that must be rewritten
    ENTRIES = [
      {
        key: "rspec-rails", label: "RSpec", ecosystem: :ruby,
        gems: %w[rspec-rails rspec], paths: %w[spec],
        moves: { "spec" => "test/rspec" },
        config: %i[rspec]
      },
      {
        key: "support", label: "Support helpers", ecosystem: :ruby,
        gems: [], paths: %w[spec/support test/support],
        # spec/support is an rspec convention, not shared material: cucumber has
        # features/support and minitest has test/. Hoisting rspec's out to a
        # top-level test/support treated it differently from cucumber's, which
        # travels inside its own tree, and broke the conventional
        # `Dir[Rails.root.join("spec/support/**/*.rb")]` for no gain.
        moves: { "spec/support" => "test/rspec/support", "test/support" => "test/support" },
        config: %i[]
      },
      {
        key: "factory_bot_rails", label: "FactoryBot", ecosystem: :ruby, kind: :data,
        gems: %w[factory_bot_rails factory_bot factory_girl_rails factory_girl],
        paths: %w[spec/factories test/factories factories],
        moves: {
          "spec/factories" => "test/data/factories",
          "test/factories" => "test/data/factories",
          "factories" => "test/data/factories"
        },
        config: %i[factory_bot]
      },
      {
        key: "fixtures", label: "Fixtures", ecosystem: :ruby, kind: :data,
        gems: [], paths: %w[test/fixtures spec/fixtures],
        moves: {
          "test/fixtures" => "test/data/fixtures",
          "spec/fixtures" => "test/data/fixtures"
        },
        config: %i[fixtures]
      },
      {
        key: "attributes", label: "Attribute sets", ecosystem: :ruby, kind: :data,
        gems: [], paths: %w[spec/attributes test/attributes],
        moves: {
          "spec/attributes" => "test/data/attributes",
          "test/attributes" => "test/data/attributes"
        },
        config: %i[]
      },
      {
        key: "exemplars", label: "Exemplars", ecosystem: :ruby, kind: :data,
        gems: [], paths: %w[spec/exemplars test/exemplars],
        moves: {
          "spec/exemplars" => "test/data/exemplars",
          "test/exemplars" => "test/data/exemplars"
        },
        config: %i[]
      },
      {
        key: "seeds", label: "Test seeds", ecosystem: :ruby, kind: :data,
        gems: [], paths: %w[spec/seeds test/seeds db/seeds/test],
        moves: {
          "spec/seeds" => "test/data/seeds",
          "test/seeds" => "test/data/seeds",
          "db/seeds/test" => "test/data/seeds"
        },
        config: %i[]
      },
      {
        key: "vcr", label: "VCR cassettes", ecosystem: :ruby, kind: :data,
        gems: %w[vcr], paths: %w[spec/vcr_cassettes spec/cassettes test/vcr_cassettes],
        moves: {
          "spec/vcr_cassettes" => "test/data/cassettes",
          "spec/cassettes" => "test/data/cassettes",
          "test/vcr_cassettes" => "test/data/cassettes"
        },
        config: %i[vcr]
      },
      {
        key: "capybara", label: "Capybara system tests", ecosystem: :ruby,
        gems: %w[capybara], paths: %w[spec/system spec/features test/system],
        # RSpec's system specs stay inside the rspec tree. `rspec` collects from
        # a single --default-path, so a system spec parked outside it is not
        # found and not run -- and a suite that silently shrinks is worse than
        # one that breaks. Rails' own system tests keep test/system, where
        # `bin/rails test:system` looks for them.
        moves: {
          "spec/system" => "test/rspec/system",
          "spec/features" => "test/rspec/system",
          "test/system" => "test/system"
        },
        config: %i[capybara]
      },
      {
        key: "cucumber-rails", label: "Cucumber", ecosystem: :ruby,
        gems: %w[cucumber-rails cucumber], paths: %w[features],
        moves: { "features" => "test/cucumber/features" },
        config: %i[cucumber cucumber_env]
      },
      {
        key: "aruba", label: "Aruba", ecosystem: :ruby,
        gems: %w[aruba], paths: %w[features/aruba],
        moves: { "features/aruba" => "test/cucumber/aruba" },
        config: %i[]
      },
      {
        key: "minitest", label: "Minitest / Rails default tests", ecosystem: :ruby,
        gems: %w[minitest minitest-rails], paths: %w[test/models test/controllers test/integration],
        moves: %w[
          models controllers integration mailers helpers jobs channels services decorators
        ].to_h { |dir| [ "test/#{dir}", "test/minitest/#{dir}" ] },
        config: %i[]
      },
      {
        key: "test-unit", label: "Test::Unit", ecosystem: :ruby,
        gems: %w[test-unit], paths: %w[test/unit],
        moves: { "test/unit" => "test/unit" },
        config: %i[]
      },
      {
        key: "simplecov", label: "SimpleCov", ecosystem: :ruby,
        gems: %w[simplecov], paths: %w[coverage],
        moves: { "coverage" => "test/results/coverage" },
        generated: %w[coverage],
        config: %i[simplecov]
      },
      {
        key: "results", label: "Test reports and artifacts", ecosystem: :ruby, kind: :data,
        gems: [], paths: %w[test_results spec/reports test/reports tmp/screenshots],
        moves: {
          "test_results" => "test/results/reports",
          "spec/reports" => "test/results/reports",
          "test/reports" => "test/results/reports",
          "tmp/screenshots" => "test/results/screenshots"
        },
        generated: %w[tmp/screenshots],
        config: %i[]
      },
      {
        key: "jest", label: "Jest", ecosystem: :javascript,
        packages: %w[jest], paths: %w[__tests__ spec/javascript test/javascript],
        moves: {
          "__tests__" => "test/javascript/jest",
          "spec/javascript" => "test/javascript/jest",
          "test/javascript" => "test/javascript/jest"
        },
        config: %i[jest]
      },
      {
        key: "jasmine", label: "Jasmine", ecosystem: :javascript,
        packages: %w[jasmine jasmine-core], paths: %w[spec/jasmine jasmine],
        moves: {
          "spec/jasmine" => "test/javascript/jasmine",
          "jasmine" => "test/javascript/jasmine"
        },
        config: %i[jasmine]
      },
      {
        key: "vitest", label: "Vitest", ecosystem: :javascript,
        packages: %w[vitest], paths: %w[tests/unit],
        moves: { "tests/unit" => "test/javascript/vitest" },
        config: %i[manual], manual_config: %w[vitest.config.js vitest.config.ts vite.config.js vite.config.ts],
        manual_settings: %w[test.include test.dir]
      },
      {
        key: "@playwright/test", label: "Playwright", ecosystem: :javascript,
        packages: %w[@playwright/test playwright], paths: %w[e2e tests/e2e playwright],
        moves: {
          "e2e" => "test/javascript/playwright",
          "tests/e2e" => "test/javascript/playwright",
          "playwright" => "test/javascript/playwright"
        },
        config: %i[manual], manual_config: %w[playwright.config.js playwright.config.ts],
        manual_settings: %w[testDir]
      },
      {
        key: "cypress", label: "Cypress", ecosystem: :javascript,
        packages: %w[cypress], paths: %w[cypress],
        moves: { "cypress" => "test/javascript/cypress" },
        config: %i[manual], manual_config: %w[cypress.config.js cypress.config.ts],
        manual_settings: %w[e2e.specPattern component.specPattern]
      },
      {
        key: "karma", label: "Karma", ecosystem: :javascript,
        packages: %w[karma], paths: %w[karma spec/karma],
        moves: { "karma" => "test/javascript/karma", "spec/karma" => "test/javascript/karma" },
        config: %i[manual], manual_config: %w[karma.conf.js karma.conf.ts],
        manual_settings: %w[basePath files]
      }
    ].freeze

    # Root directories that look like test trees but belong to no known
    # framework. They are offered in migrate.yml under the "project" key,
    # disabled, so the user opts in by editing the file.
    STRAY_PATTERN = /\A(?:.*[-_])?(?:de|un|old|legacy|new|wip)?(?:spec|specs|test|tests)\z/

    def self.entries = ENTRIES

    def self.find(key) = ENTRIES.find { |entry| entry[:key] == key }
  end
end
