# frozen_string_literal: true

RSpec.describe Oubliette::Manifest do
  it "writes one entry per detected framework, deepest origin first" do
    box = sandbox(gems: %w[rspec-rails factory_bot_rails], dirs: %w[spec/models spec/factories])
    manifest = described_class.build(box.root)

    expect(manifest.pairs.map(&:origin)).to eq(%w[spec/factories spec])
  end

  it "pairs every origin with the target oubliette would give it" do
    manifest = described_class.build(sandbox(gems: %w[rspec-rails], dirs: %w[spec]).root)

    expect(manifest.pairs.map { |pair| [ pair.origin, pair.oubliette ] })
      .to eq([ %w[spec test/rspec] ])
  end

  it "only describes paths that exist" do
    manifest = described_class.build(sandbox(gems: %w[rspec-rails vcr], dirs: %w[spec]).root)

    expect(manifest.pairs.map(&:origin)).to eq(%w[spec])
  end

  it "keeps a hand-edited target across a sync" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    described_class.build(box.root).save!
    box.write(Oubliette::Manifest::PATH, box.read(Oubliette::Manifest::PATH).sub("oubliette: test/rspec", "oubliette: test/examples"))

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
    box.write(Oubliette::Manifest::PATH, box.read(Oubliette::Manifest::PATH).sub(/enabled: false/, "enabled: true"))

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
    box.write(Oubliette::Manifest::PATH, box.read(Oubliette::Manifest::PATH).sub("oubliette: test/rspec", "oubliette: test/examples"))

    expect(box.manifest.pairs.map(&:status)).to eq([ :pending ])
  end

  it "puts its own defaults back on reset, discarding the edit" do
    box = sandbox(gems: %w[rspec-rails factory_bot_rails], dirs: %w[spec spec/factories])
    manifest = described_class.build(box.root)
    manifest.data["gems"]["rspec-rails"]["paths"][0]["oubliette"] = "somewhere/else"
    manifest.reset_targets!

    expect(manifest.destination("rspec-rails")).to eq("test/rspec")
    expect(manifest.destination("factory_bot_rails")).to eq("test/data/factories")
  end

  it "resets one framework and leaves another edit alone" do
    box = sandbox(gems: %w[rspec-rails factory_bot_rails], dirs: %w[spec spec/factories])
    manifest = described_class.build(box.root)
    manifest.data["gems"]["rspec-rails"]["paths"][0]["oubliette"] = "somewhere/else"
    manifest.data["gems"]["factory_bot_rails"]["paths"][0]["oubliette"] = "elsewhere"
    manifest.reset_targets!(only: "factory_bot_rails")

    expect(manifest.destination("rspec-rails")).to eq("somewhere/else")
    expect(manifest.destination("factory_bot_rails")).to eq("test/data/factories")
  end
end

RSpec.describe "#{Oubliette::Manifest} self-nesting" do
  # test/javascript is jest's default home and test/javascript/jest is where it
  # lands, so a second look at an already-migrated project must not propose
  # folding the parent into its own child.
  it "does not propose a move into its own subdirectory once the move has happened" do
    box = sandbox(packages: %w[jest], dirs: %w[spec/javascript])
    box.run

    expect(box.manifest.pairs.map(&:origin)).not_to include("test/javascript")
  end

  it "still refuses when rollback.yml has been lost" do
    box = sandbox(packages: %w[jest], dirs: %w[spec/javascript])
    box.run
    FileUtils.rm(box.root.join(Oubliette::Ledger::PATH))
    box.commit("lost the ledger")

    expect(Oubliette::Manifest.build(box.root).pairs.map(&:origin)).not_to include("test/javascript")
    expect { box.run }.not_to raise_error
    expect(box).not_to be_exist("test/javascript/jest/jest")
  end

  it "refuses outright at the mover, whatever the manifest says" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    mover = Oubliette::Mover.new(box.root, logger: ->(_line) { })

    expect { mover.relocate("spec", "spec/inner") }
      .to raise_error(Oubliette::Error, /into its own subdirectory/)
  end
end

RSpec.describe "#{Oubliette::Manifest} layout" do
  def rendered(box) = Oubliette::Manifest.build(box.root).render

  def full_box
    new_sandbox(gems: %w[rspec-rails factory_bot_rails], packages: %w[jest],
                dirs: %w[spec/models spec/factories spec/javascript test/unit])
  end

  it "puts what you declared before what it merely found" do
    text = rendered(full_box)

    expect(text.index("frameworks you declared")).to be < text.index("shared test material")
    expect(text.index("shared test material")).to be < text.index("found on disk")
  end

  it "files shared material apart from the runners" do
    text = rendered(full_box)
    data_section = text.split("shared test material").last.split("found on disk").first

    expect(data_section).to include("factory_bot_rails")
    expect(data_section).not_to include("rspec-rails")
  end

  it "files a directory with no gem behind it under what it found" do
    text = rendered(full_box)

    expect(text.split("found on disk").last).to include("test-unit")
  end

  it "records why each framework is listed" do
    expect(rendered(full_box)).to include("tier: declared").and include("tier: disk")
  end

  it "lists what it knows but did not find, one line each" do
    text = rendered(full_box)
    tail = text.split("did not find here").last

    expect(tail).to match(/#\s+cypress\s+cypress\s+->\s+test\/javascript\/cypress/)
    expect(tail).to include("nothing here to uncomment")
  end

  it "offers a shape to copy for a framework detection missed" do
    expect(rendered(full_box)).to include("my-framework:").and include("copy this shape")
  end

  it "does not list a framework you deleted as one it could not find" do
    box = new_sandbox(gems: %w[rspec-rails cucumber-rails], dirs: %w[spec/models features/support])
    box.run(input: box.answering("n\n"))
    path = box.root.join(Oubliette::Manifest::PATH)
    path.write(path.read.sub(/  cucumber-rails:\n(?:    .*\n|      .*\n)*/, ""))
    box.commit("deleted cucumber")

    expect(Oubliette::Manifest.build(box.root).render).not_to include("cucumber-rails")
  end

  it "is still valid yaml that round trips" do
    box = full_box
    box.run

    expect { YAML.safe_load(box.read(Oubliette::Manifest::PATH), aliases: false) }.not_to raise_error
    expect(Oubliette::Manifest.load(box.root).gems).to include("rspec-rails")
  end
end

RSpec.describe "where support helpers belong" do
  # spec/support is rspec's own convention, the way features/support is
  # cucumber's. Hoisting one out to a shared top level while the other travelled
  # inside its tree treated the same thing two different ways.
  it "keeps rspec's support inside the rspec tree" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models spec/support])
    box.run

    expect(box).to be_exist("test/rspec/support")
    expect(box).not_to be_exist("test/support")
  end

  it "keeps cucumber's support inside the cucumber tree, as it already did" do
    box = sandbox(gems: %w[cucumber-rails], dirs: %w[features/support])
    box.run

    expect(box).to be_exist("test/cucumber/features/support")
  end

  it "leaves minitest's own test/support where it is" do
    box = sandbox(gems: %w[minitest], dirs: %w[test/models test/support])
    box.run

    expect(box).to be_exist("test/support")
  end

  it "still treats genuinely shared material as shared" do
    box = sandbox(gems: %w[rspec-rails factory_bot_rails vcr],
                  dirs: %w[spec/models spec/factories spec/vcr_cassettes spec/attributes])
    box.run

    expect(box).to be_exist("test/data/factories")
    expect(box).to be_exist("test/data/cassettes")
    expect(box).to be_exist("test/data/attributes")
  end
end
