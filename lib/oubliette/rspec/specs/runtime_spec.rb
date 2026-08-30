# frozen_string_literal: true

RSpec.describe Oubliette::Runtime do
  it "does nothing in a project that has never been migrated" do
    expect(described_class.apply!(root: sandbox(gems: %w[rspec-rails], dirs: %w[spec]).root))
      .to eq(:absent)
  end

  it "says nothing after a rollback, when everything is back at its origin" do
    box = sandbox(gems: %w[rspec-rails fixtures], dirs: %w[spec test/fixtures])
    box.run
    box.runner.rollback

    expect(described_class.apply!(root: box.root)).to eq(:dormant)
  end

  it "says nothing after prepare, when migrate.yml exists but nothing has moved" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.runner.prepare

    expect(described_class.apply!(root: box.root)).to eq(:dormant)
  end

  it "speaks up while something is displaced" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.run

    expect(described_class.apply!(root: box.root)).to eq(:applied)
  end

  it "accepts a project whose directories are all where the manifest says" do
    box = sandbox(gems: %w[rspec-rails factory_bot_rails], dirs: %w[spec/models spec/factories])
    box.run

    expect { described_class.verify!(box.manifest) }.not_to raise_error
  end

  it "refuses to let a suite start when a framework's directories have vanished" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run
    FileUtils.remove_entry(box.root.join("test/rspec"))

    expect { described_class.verify!(box.manifest) }
      .to raise_error(described_class::MissingPaths, /rspec-rails/)
  end
end

# factory_bot_rails loads the definitions from its own `after_initialize`, which
# runs after this hook. Re-reading them here as well registered every factory
# twice and killed the boot on DuplicateDefinitionError, before a single example
# could run. Found by migrating a real application.
RSpec.describe "#{Oubliette::Runtime} and factory_bot" do
  # Enough of the API for the decision under test, and none of the gem: the
  # portable suite has to run in a process that has loaded nothing of its own.
  def factory_bot(registered:)
    Class.new do
      attr_accessor :definition_file_paths
      attr_reader :reloads

      define_method(:initialize) { @reloads = 0 }
      define_method(:factories) { Array.new(registered) }

      def reload
        @reloads += 1
      end
    end.new
  end

  def apply(double)
    stub_const("FactoryBot", double)
    Oubliette::Runtime.send(:factories, [ "test/data/factories" ])
  end

  it "sets the paths and leaves the loading to the framework" do
    double = factory_bot(registered: 0)
    apply(double)

    expect(double.definition_file_paths).to eq([ Oubliette.root.join("test/data/factories").to_s ])
    expect(double.reloads).to eq(0)
  end

  it "re-reads them when definitions were already loaded from the old directory" do
    double = factory_bot(registered: 3)
    apply(double)

    expect(double.reloads).to eq(1)
  end
end

RSpec.describe "#{Oubliette::Runtime} rspec type mappings" do
  it "names a type for every directory rspec-rails knows about" do
    expect(Oubliette::Runtime::DIRECTORY_TYPES)
      .to include("models" => :model, "requests" => :request, "system" => :system)
  end

  it "does nothing in a project that has no rspec-rails loaded" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run

    expect { Oubliette::Runtime.configure(box.manifest) }.not_to raise_error
  end
end
