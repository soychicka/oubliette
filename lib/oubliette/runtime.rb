# frozen_string_literal: true

require_relative "manifest"

module Oubliette
  # Applies the parts of migrate.yml that cannot live in a config file, by
  # telling the already-loaded test libraries where their assets went.
  #
  # Everything is guarded on the constant actually being defined, so a project
  # that uses three of these frameworks pays nothing for the other ten.
  module Runtime
    class MissingPaths < Error; end

    RUNTIME_KEYS = %w[fixtures factory_bot_rails capybara vcr simplecov results].freeze

    # What rspec-rails would have inferred from the directory name, had the
    # directory still been where it expects it.
    DIRECTORY_TYPES = {
      "models" => :model, "controllers" => :controller, "requests" => :request,
      "routing" => :routing, "views" => :view, "helpers" => :helper,
      "mailers" => :mailer, "jobs" => :job, "channels" => :channel,
      "features" => :feature, "system" => :system
    }.freeze

    class << self
      def apply!(root: Oubliette.root, strict: true)
        return :absent unless Manifest.exists_in?(root)

        manifest = Manifest.load(root)
        verify!(manifest) if strict
        configure(manifest)
        :applied
      end

      # A framework whose directories vanished from both the old and the new
      # location cannot run, and failing loudly here beats a suite that silently
      # loads no fixtures.
      def verify!(manifest)
        broken = manifest.gems.select do |key|
          pairs = manifest.pairs(only: key)
          pairs.any? && pairs.all?(&:missing?)
        end
        return if broken.empty?

        raise MissingPaths, <<~TEXT
          oubliette: directories are missing for #{broken.join(', ')}.

          migrate.yml points at paths that exist in neither their original nor
          their new location, so the test suite cannot run. Restore the files, or
          run `rake oubliette:rollback` and edit migrate.yml.
        TEXT
      end

      def configure(manifest)
        rspec_types(manifest.location("rspec-rails"), manifest.location("capybara"))
        fixtures(manifest.location("fixtures"))
        factories(manifest.locations("factory_bot_rails"))
        cassettes(manifest.location("vcr"))
        coverage(manifest.location("simplecov"))
        screenshots(manifest.locations("results").find { |path| path.end_with?("screenshots") })
      end
      private
        # rails/test_help appends "#{Rails.root}/test/fixtures/" from a hook of
        # its own, and it registers that hook after this railtie has run, so
        # assigning fixture_paths here would simply be appended to. Overriding
        # the reader instead makes migrate.yml the answer no matter who asks or
        # when -- which is the point of migrate.yml.
        # rspec-rails works out that a spec in spec/requests is a request spec by
        # matching the literal path, so relocating the tree silently strips the
        # type and the example loses `get`, `post` and the rest. The same
        # mapping is re-registered against wherever the directories actually
        # went. `||=` means an explicit `type:` on the example still wins.
        def rspec_types(rspec_path, system_path)
          return unless defined?(RSpec::Rails) && defined?(RSpec.configure)

          mappings = DIRECTORY_TYPES.filter_map do |dir, type|
            [ "#{rspec_path}/#{dir}", type ] if rspec_path
          end
          mappings << [ system_path, :system ] if system_path

          RSpec.configure do |config|
            mappings.each do |path, type|
              pattern = %r{/#{Regexp.escape(path)}/}
              config.define_derived_metadata(file_path: pattern) do |metadata|
                metadata[:type] ||= type
              end
            end
          end
        end

        def fixtures(path)
          return if path.nil? || !defined?(ActiveSupport::TestCase)

          absolute = Oubliette.root.join(path).to_s
          files = File.join(absolute, "files")

          ActiveSupport::TestCase.singleton_class.prepend(Module.new do
            define_method(:fixture_paths) { [ absolute ] }
            define_method(:file_fixture_path) { files } if File.directory?(files)
          end)

          RSpec.configure { |config| config.fixture_paths = [ absolute ] } if rspec_rails_fixtures?
        end

        def factories(paths)
          return if paths.empty? || !defined?(FactoryBot)

          FactoryBot.definition_file_paths = paths.map { |path| Oubliette.root.join(path).to_s }
          FactoryBot.reload if FactoryBot.respond_to?(:reload)
        end

        def cassettes(path)
          return if path.nil? || !defined?(VCR)

          VCR.configure { |config| config.cassette_library_dir = Oubliette.root.join(path).to_s }
        end

        def coverage(path)
          return if path.nil? || !defined?(SimpleCov)

          SimpleCov.coverage_dir(Oubliette.root.join(path).to_s)
        end

        def screenshots(path)
          return if path.nil? || !defined?(Capybara)

          Capybara.save_path = Oubliette.root.join(path).to_s
        end

        def rspec_rails_fixtures?
          defined?(RSpec) && RSpec.respond_to?(:configure) &&
            defined?(RSpec::Rails) && RSpec.configuration.respond_to?(:fixture_paths=)
        end
    end
  end
end
