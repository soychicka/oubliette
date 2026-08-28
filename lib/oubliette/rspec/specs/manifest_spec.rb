# frozen_string_literal: true

RSpec.describe Oubliette::Manifest do
  it "writes one entry per detected framework, deepest source first" do
    box = sandbox(gems: %w[rspec-rails factory_bot_rails], dirs: %w[spec/models spec/factories])
    manifest = described_class.build(box.root)

    expect(manifest.moves.map(&:from)).to eq(%w[spec/factories spec])
  end

  it "only describes paths that exist" do
    manifest = described_class.build(sandbox(gems: %w[rspec-rails vcr], dirs: %w[spec]).root)

    expect(manifest.moves.map(&:from)).to eq(%w[spec])
  end

  it "keeps a hand-edited target across a sync" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    described_class.build(box.root).save!
    box.write("migrate.yml", box.read("migrate.yml").sub("to: test/rspec", "to: test/examples"))

    expect(described_class.build(box.root).destination("rspec-rails")).to eq("test/examples")
  end

  it "adds a framework installed after the first run without disturbing the others" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    described_class.build(box.root).save!

    box.write("Gemfile", "#{box.read('Gemfile')}gem 'cucumber-rails'\n")
    box.write("features/support/env.rb", "")
    manifest = described_class.build(box.root)

    expect(manifest.gems).to include("rspec-rails", "cucumber-rails")
    expect(manifest.destination("cucumber-rails")).to eq("test/cucumber/features")
  end

  it "offers stray directories disabled, so including one is a deliberate edit" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec despec])
    manifest = described_class.build(box.root)

    expect(manifest.data["strays"]["despec"]["enabled"]).to be(false)
    expect(manifest.moves.map(&:from)).not_to include("despec")
  end

  it "moves a stray once the user enables it" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec despec])
    described_class.build(box.root).save!
    box.write("migrate.yml", box.read("migrate.yml").sub(/enabled: false/, "enabled: true"))

    expect(described_class.build(box.root).moves.map(&:from)).to include("despec")
  end

  it "marks a path missing when it is absent from both locations" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    described_class.build(box.root).save!
    FileUtils.remove_entry(box.root.join("spec"))

    expect(described_class.load(box.root).refresh_statuses!.missing.map(&:from)).to eq(%w[spec])
  end
end
