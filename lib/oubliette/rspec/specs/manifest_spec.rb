# frozen_string_literal: true

RSpec.describe Oubliette::Manifest do
  it "writes one entry per detected framework, deepest origin first" do
    box = sandbox(gems: %w[rspec-rails factory_bot_rails], dirs: %w[spec/models spec/factories])
    manifest = described_class.build(box.root)

    expect(manifest.pairs.map(&:origin)).to eq(%w[spec/factories spec])
  end

  it "pairs every origin with the target oubliette would give it" do
    manifest = described_class.build(sandbox(gems: %w[rspec-rails], dirs: %w[spec]).root)

    expect(manifest.pairs.map { |pair| [ pair.origin, pair.oublietted ] })
      .to eq([ %w[spec test/rspec] ])
  end

  it "only describes paths that exist" do
    manifest = described_class.build(sandbox(gems: %w[rspec-rails vcr], dirs: %w[spec]).root)

    expect(manifest.pairs.map(&:origin)).to eq(%w[spec])
  end

  it "keeps a hand-edited target across a sync" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    described_class.build(box.root).save!
    box.write("migrate.yml", box.read("migrate.yml").sub("oublietted: test/rspec", "oublietted: test/examples"))

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
    expect(manifest.pairs.map(&:origin)).not_to include("despec")
  end

  it "moves a stray once the user enables it" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec despec])
    described_class.build(box.root).save!
    box.write("migrate.yml", box.read("migrate.yml").sub(/enabled: false/, "enabled: true"))

    expect(described_class.build(box.root).pairs.map(&:origin)).to include("despec")
  end

  it "marks a path missing when it is absent from both locations" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    described_class.build(box.root).save!
    FileUtils.remove_entry(box.root.join("spec"))

    expect(described_class.load(box.root).missing.map(&:origin)).to eq(%w[spec])
  end

  it "calls a pair settled once rollback.yml agrees with it" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.run

    expect(box.manifest.pairs.map(&:status)).to eq([ :settled ])
  end

  it "calls a pair pending as soon as the target is edited" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.run
    box.write("migrate.yml", box.read("migrate.yml").sub("oublietted: test/rspec", "oublietted: test/examples"))

    expect(box.manifest.pairs.map(&:status)).to eq([ :pending ])
  end

  it "puts its own defaults back on reset, discarding the edit" do
    box = sandbox(gems: %w[rspec-rails factory_bot_rails], dirs: %w[spec spec/factories])
    manifest = described_class.build(box.root)
    manifest.data["gems"]["rspec-rails"]["paths"][0]["oublietted"] = "somewhere/else"
    manifest.reset_targets!

    expect(manifest.destination("rspec-rails")).to eq("test/rspec")
    expect(manifest.destination("factory_bot_rails")).to eq("test/data/factories")
  end

  it "resets one framework and leaves another edit alone" do
    box = sandbox(gems: %w[rspec-rails factory_bot_rails], dirs: %w[spec spec/factories])
    manifest = described_class.build(box.root)
    manifest.data["gems"]["rspec-rails"]["paths"][0]["oublietted"] = "somewhere/else"
    manifest.data["gems"]["factory_bot_rails"]["paths"][0]["oublietted"] = "elsewhere"
    manifest.reset_targets!(only: "factory_bot_rails")

    expect(manifest.destination("rspec-rails")).to eq("somewhere/else")
    expect(manifest.destination("factory_bot_rails")).to eq("test/data/factories")
  end
end
