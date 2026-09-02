# frozen_string_literal: true

require_relative "ledger"
require_relative "manifest"
require_relative "notice"
require_relative "text"

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
        return :dormant unless displaced?(root)

        manifest = Manifest.load(root)
        verify!(manifest) if strict
        configure(manifest)
        :applied
      end

      # The hook only speaks up while something is actually displaced. After
      # `prepare`, after a rollback, and after an uninstall, it says nothing and
      # every framework keeps its own default -- which is correct, because at
      # that point every directory is at the default.
      def displaced?(root) = Ledger.displaced?(root)

      # A framework whose directories vanished from both the old and the new
      # location cannot run, and failing loudly here beats a suite that silently
      # loads no fixtures.
      def verify!(manifest)
        broken = manifest.gems.select do |key|
          pairs = manifest.pairs(only: key)
          pairs.any? && pairs.all?(&:missing?)
        end
        return if broken.empty?

        raise MissingPaths, Notice.error(
          Text.t("runtime.missing.headline", gems: broken.join(", ")),
          Text.t("runtime.missing.body")
        )
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
          FactoryBot.reload if reload_factories?
        end

        # factory_bot_rails sets the paths in an initializer and loads them from
        # its own `after_initialize`, which runs after this hook. Loading them
        # here as well registers every factory twice -- `find_definitions` does
        # not reset the registry first -- and the boot dies on
        # `DuplicateDefinitionError` before a single example runs.
        #
        # So the paths are always set, and they are only re-read when something
        # is already registered. That means the definitions were loaded before
        # this hook ran, from the directory they used to be in, and re-reading
        # is the whole point.
        def reload_factories?
          return false unless FactoryBot.respond_to?(:reload)
          return true unless FactoryBot.respond_to?(:factories)
          return true if FactoryBot.factories.count.positive?

          # Nothing is registered, which means one of two opposite things, and
          # counting cannot tell them apart.
          #
          # Either factory_bot_rails has not loaded the definitions yet, in
          # which case it is about to, from the paths just set, and loading
          # them here as well would register every factory twice. Or it has
          # already run and found nothing, because it looked in a directory
          # that had moved -- and then a reload is the only thing that will
          # save the suite.
          #
          # What separates them is whether the application has finished
          # initializing, since factory_bot_rails loads from `after_initialize`.
          booted?
        end

        def booted?
          defined?(Rails) && Rails.respond_to?(:application) &&
            Rails.application.respond_to?(:initialized?) && Rails.application.initialized?
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
