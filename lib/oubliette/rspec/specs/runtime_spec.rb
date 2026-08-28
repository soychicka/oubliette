# frozen_string_literal: true

RSpec.describe Oubliette::Runtime do
  it "does nothing in a project that has never been migrated" do
    expect(described_class.apply!(root: sandbox(gems: %w[rspec-rails], dirs: %w[spec]).root))
      .to eq(:absent)
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
