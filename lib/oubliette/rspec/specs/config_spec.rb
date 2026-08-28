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
      manifest = manifest_for(box)
      FileUtils.remove_entry(box.root.join("spec"))

      expect(described_class.new(box.root, manifest.refresh_statuses!, logger: quiet).apply).to eq(:skipped)
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
