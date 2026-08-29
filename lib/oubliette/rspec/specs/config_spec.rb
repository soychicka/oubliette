# frozen_string_literal: true

RSpec.describe "config writers" do
  # What the framework actually reads: everything that is not commented out.
  def active(text)
    text.lines.reject { |line| line.strip.start_with?("#") }.map(&:chomp).reject(&:empty?)
  end
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

      expect(active(box.read(".rspec"))).to eq([ "--color", "--format doc", "--default-path test/rspec" ])
    end

    it "replaces an existing default path rather than adding a second" do
      box = sandbox(gems: %w[rspec-rails], dirs: %w[spec],
                    files: { ".rspec" => "--default-path spec\n--color\n" })
      described_class.new(box.root, manifest_for(box), logger: quiet).apply

      contents = box.read(".rspec")
      expect(active(contents).grep(/--default-path/)).to eq([ "--default-path test/rspec" ])
      expect(contents).to include("# was: --default-path spec")
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

      contents = box.read("cucumber.yml")
      expect(active(contents)).to eq([
        "default: -r test/cucumber/features/support -r test/cucumber/features/step_definitions " \
        "--strict test/cucumber/features"
      ])
      expect(contents).to include("# was: #{original.chomp}")
    end

    it "leaves a profile that already says what to require alone" do
      original = "default: -r features/support --strict features\n"
      box = sandbox(gems: %w[cucumber-rails], dirs: %w[features/support],
                    files: { "cucumber.yml" => original })
      described_class.new(box.root, manifest_for(box), logger: quiet).apply

      expect(active(box.read("cucumber.yml")).first.scan("-r ").length).to eq(1)
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

      expect(active(box.read("cucumber.yml")))
        .to eq([ "default: -r test/cucumber/features --tags @features_only test/cucumber/features" ])
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

RSpec.describe Oubliette::Config::ManualGuide do
  def cypress_box
    box = new_sandbox(packages: %w[cypress], dirs: %w[cypress],
                      files: { "cypress.config.js" => "module.exports = { e2e: { specPattern: 'cypress/**' } };\n" })
    box.run
    box
  end

  it "writes the note beside the file that needs changing" do
    expect(cypress_box).to be_exist("test/oubliette/cypress.config.js.md")
  end

  it "names the setting, the move, and a before and after" do
    guide = cypress_box.read("test/oubliette/cypress.config.js.md")

    expect(guide).to include("cypress -> test/javascript/cypress")
    expect(guide).to include("e2e.specPattern")
    expect(guide).to include("// before")
    expect(guide).to include('"test/javascript/cypress/**/*"')
  end

  it "leaves the config file itself alone" do
    original = "module.exports = { e2e: { specPattern: 'cypress/**' } };\n"

    expect(cypress_box.read("cypress.config.js")).to eq(original)
  end

  it "is removed by a rollback" do
    box = cypress_box
    box.runner.rollback

    expect(box).not_to be_exist("test/oubliette/cypress.config.js.md")
    expect(box).to be_exist("cypress")
  end

  it "writes nothing for a framework whose config oubliette rewrites" do
    box = new_sandbox(packages: %w[jest], dirs: %w[spec/javascript])
    box.run

    expect(box.root.glob("test/oubliette/*.md")).to be_empty
  end

  it "writes nothing when the project has no such config file" do
    box = new_sandbox(packages: %w[cypress], dirs: %w[cypress])
    box.run

    expect(box.root.glob("test/oubliette/*.md")).to be_empty
  end
end

RSpec.describe "#{Oubliette::Config::ManualGuide} example code" do
  it "nests a dotted setting back into the object literal it lives in" do
    box = new_sandbox(packages: %w[cypress], dirs: %w[cypress],
                      files: { "cypress.config.js" => "module.exports = {};\n" })
    box.run

    expect(box.read("test/oubliette/cypress.config.js.md"))
      .to include(%(e2e: { specPattern: "test/javascript/cypress/**/*" }))
  end

  it "leaves a flat setting flat" do
    box = new_sandbox(packages: %w[@playwright/test], dirs: %w[e2e],
                      files: { "playwright.config.js" => "module.exports = {};\n" })
    box.run

    guide = box.read("test/oubliette/playwright.config.js.md")
    expect(guide).to include(%(testDir: "test/javascript/playwright/**/*"))
    expect(guide).not_to include("{ testDir")
  end
end
