# frozen_string_literal: true

RSpec.describe "config writers" do
  def manifest_for(box)
    Oubliette::Manifest.build(box.root).tap(&:save!)
  end

  def quiet
    ->(_line) { }
  end

  describe Oubliette::Config::Rspec do
    it "adds a default path while keeping the options already there" do
      box = sandbox(gems: %w[rspec-rails], dirs: %w[spec], files: { ".rspec" => "--color\n--format doc\n" })
      described_class.new(box.root, manifest_for(box), logger: quiet).apply

      expect(box.read(".rspec").lines.map(&:chomp))
        .to eq([ "--color", "--format doc", "--default-path test/rspec" ])
    end

    it "replaces an existing default path rather than adding a second" do
      box = sandbox(gems: %w[rspec-rails], dirs: %w[spec],
                    files: { ".rspec" => "--default-path spec\n--color\n" })
      described_class.new(box.root, manifest_for(box), logger: quiet).apply

      expect(box.read(".rspec").scan("--default-path").length).to eq(1)
    end

    it "restores the original on revert" do
      box = sandbox(gems: %w[rspec-rails], dirs: %w[spec], files: { ".rspec" => "--color\n" })
      writer = described_class.new(box.root, manifest_for(box), logger: quiet)
      writer.apply
      writer.revert

      expect(box.read(".rspec")).to eq("--color\n")
    end

    it "writes nothing when the spec tree is missing from both locations" do
      box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
      manifest_for(box)
      FileUtils.remove_entry(box.root.join("spec"))
      manifest = Oubliette::Manifest.load(box.root)

      expect(described_class.new(box.root, manifest, logger: quiet).apply).to eq(:skipped)
    end
  end

  describe Oubliette::Config::Cucumber do
    it "rewrites the feature paths in a hand-tuned cucumber.yml" do
      original = "default: -r features/support -r features/step_definitions --strict features\n"
      box = sandbox(gems: %w[cucumber-rails], dirs: %w[features/support],
                    files: { "cucumber.yml" => original })
      described_class.new(box.root, manifest_for(box), logger: quiet).apply

      expect(box.read("cucumber.yml")).to eq(
        "default: -r test/cucumber/features/support -r test/cucumber/features/step_definitions " \
        "--strict test/cucumber/features\n"
      )
    end

    it "leaves a profile that already says what to require alone" do
      original = "default: -r features/support --strict features\n"
      box = sandbox(gems: %w[cucumber-rails], dirs: %w[features/support],
                    files: { "cucumber.yml" => original })
      described_class.new(box.root, manifest_for(box), logger: quiet).apply

      expect(box.read("cucumber.yml").scan("-r ").length).to eq(1)
    end

    it "generates a default profile when the project has no cucumber.yml" do
      box = sandbox(gems: %w[cucumber-rails], dirs: %w[features])
      described_class.new(box.root, manifest_for(box), logger: quiet).apply

      expect(box.read("cucumber.yml")).to include("test/cucumber/features")
    end

    it "leaves words that merely contain the path alone" do
      box = sandbox(gems: %w[cucumber-rails], dirs: %w[features],
                    files: { "cucumber.yml" => "default: --tags @features_only features\n" })
      described_class.new(box.root, manifest_for(box), logger: quiet).apply

      expect(box.read("cucumber.yml"))
        .to eq("default: -r test/cucumber/features --tags @features_only test/cucumber/features\n")
    end
  end

  describe Oubliette::Config::Javascript do
    it "rewrites paths inside package.json without disturbing the rest" do
      box = sandbox(packages: %w[jest], dirs: %w[spec/javascript])
      described_class.new(box.root, manifest_for(box), logger: quiet).apply
      parsed = JSON.parse(box.read("package.json"))

      expect(parsed["scripts"]["test"]).to eq("jest test/javascript/jest")
      expect(parsed["name"]).to eq("sandbox")
    end

    it "restores package.json byte for byte on revert" do
      box = sandbox(packages: %w[jest], dirs: %w[spec/javascript])
      original = box.read("package.json")
      writer = described_class.new(box.root, manifest_for(box), logger: quiet)
      writer.apply
      writer.revert

      expect(box.read("package.json")).to eq(original)
    end
  end
end

RSpec.describe Oubliette::Config::Jasmine do
  def quiet = ->(_line) { }

  def manifest_for(box) = Oubliette::Manifest.build(box.root).tap(&:save!)

  it "moves the spec directory jasmine reads from its own config" do
    box = sandbox(packages: %w[jasmine], dirs: %w[spec/jasmine],
                  files: { "jasmine.json" => %({"spec_dir":"spec/jasmine","spec_files":["**/*[sS]pec.js"]}\n) })
    described_class.new(box.root, manifest_for(box), logger: quiet).apply

    expect(JSON.parse(box.read("jasmine.json"))["spec_dir"]).to eq("test/javascript/jasmine")
  end

  it "leaves the glob patterns alone" do
    box = sandbox(packages: %w[jasmine], dirs: %w[spec/jasmine],
                  files: { "jasmine.json" => %({"spec_dir":"spec/jasmine","spec_files":["**/*[sS]pec.js"]}\n) })
    described_class.new(box.root, manifest_for(box), logger: quiet).apply

    expect(JSON.parse(box.read("jasmine.json"))["spec_files"]).to eq([ "**/*[sS]pec.js" ])
  end

  it "restores the file on revert" do
    original = %({"spec_dir":"spec/jasmine"}\n)
    box = sandbox(packages: %w[jasmine], dirs: %w[spec/jasmine], files: { "jasmine.json" => original })
    writer = described_class.new(box.root, manifest_for(box), logger: quiet)
    writer.apply
    writer.revert

    expect(box.read("jasmine.json")).to eq(original)
  end

  it "is wired up by a full run" do
    box = sandbox(packages: %w[jasmine], dirs: %w[spec/jasmine],
                  files: { "jasmine.json" => %({"spec_dir":"spec/jasmine"}\n) })
    box.run

    expect(box).to be_exist("test/javascript/jasmine")
    expect(JSON.parse(box.read("jasmine.json"))["spec_dir"]).to eq("test/javascript/jasmine")
  end
end

RSpec.describe "config oubliette will not rewrite" do
  it "names the config file and the move it invalidates" do
    box = sandbox(packages: %w[cypress], dirs: %w[cypress],
                  files: { "cypress.config.js" => "module.exports = { e2e: { specPattern: 'cypress/**' } };\n" })
    box.run

    expect(box.log).to include("CONFIG YOU MUST UPDATE BY HAND")
    expect(box.log).to include("cypress.config.js (cypress): cypress -> test/javascript/cypress")
  end

  it "leaves the file itself untouched" do
    original = "module.exports = { e2e: { specPattern: 'cypress/**' } };\n"
    box = sandbox(packages: %w[cypress], dirs: %w[cypress], files: { "cypress.config.js" => original })
    box.run

    expect(box.read("cypress.config.js")).to eq(original)
  end

  it "says nothing when the framework has no config file in the project" do
    box = sandbox(packages: %w[cypress], dirs: %w[cypress])
    box.run

    expect(box.log).not_to include("CONFIG YOU MUST UPDATE BY HAND")
  end

  it "says nothing for a framework whose config oubliette does rewrite" do
    box = sandbox(packages: %w[jest], dirs: %w[spec/javascript])
    box.run

    expect(box.log).not_to include("CONFIG YOU MUST UPDATE BY HAND")
  end
end
