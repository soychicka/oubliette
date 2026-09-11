# frozen_string_literal: true

RSpec.describe Oubliette::PathToken do
  def rewrite(text, from = "features", to = "test/cucumber/features")
    described_class.substitute(text, from, to)
  end

  describe "a path written plainly" do
    it "rewrites it on its own" do
      expect(rewrite("default: features")).to eq("default: test/cucumber/features")
    end

    it "rewrites it as the head of a longer path" do
      expect(rewrite("-r features/support")).to eq("-r test/cucumber/features/support")
    end

    it "rewrites it inside quotes" do
      expect(rewrite(%(dir: "features"))).to eq(%(dir: "test/cucumber/features"))
    end
  end

  describe "a path written with a leading ./" do
    it "rewrites it and keeps the ./" do
      expect(rewrite("-r ./features")).to eq("-r ./test/cucumber/features")
    end

    it "keeps the ./ on a longer path too" do
      expect(rewrite("-r ./features/support")).to eq("-r ./test/cucumber/features/support")
    end

    it "keeps the ./ inside quotes" do
      expect(rewrite(%(testDir: "./features"))).to eq(%(testDir: "./test/cucumber/features"))
    end
  end

  # Found by migrating a real project: rails' own cucumber.rake carries
  #   ::STATS_DIRECTORIES << %w(Cucumber\ features features)
  # where the second element is the directory. It sat against a closing paren,
  # the lookahead did not allow one, and it was the only element left unmoved.
  describe "a path that ends at a closing bracket" do
    it "rewrites the last element of a word array" do
      expect(rewrite("STATS << %w(Cucumber\\ features features)"))
        .to eq("STATS << %w(Cucumber\\ features test/cucumber/features)")
    end

    it "rewrites a path before a closing square bracket" do
      expect(rewrite("dirs = [features]")).to eq("dirs = [test/cucumber/features]")
    end

    it "rewrites a path followed by a comma" do
      expect(rewrite("paths = features, other")).to eq("paths = test/cucumber/features, other")
    end
  end

  describe "what it refuses to touch" do
    # A bare word straight after an opening paren is an argument, not a path:
    # `File.exist?(features)` is a local variable. Rewriting it would turn
    # working code into a NameError.
    it "leaves a bare identifier passed as an argument alone" do
      expect(rewrite("return true if File.exist?(features)"))
        .to eq("return true if File.exist?(features)")
    end

    # The cost of that guard, stated so it is a decision and not a surprise: a
    # single-element word array opens with the same two characters as a method
    # call and is left alone too. Rewriting `File.exist?(features)` would turn
    # working code into a NameError, which is worse than missing `%w(features)`.
    it "leaves a one-element word array alone, which is the price of the guard" do
      expect(rewrite("STATS << %w(features)")).to eq("STATS << %w(features)")
    end

    it "leaves a path that climbs out of the project alone" do
      expect(rewrite("-r ../features")).to eq("-r ../features")
    end

    it "leaves a word that merely starts with the path alone" do
      expect(rewrite("--tags @features_only")).to eq("--tags @features_only")
    end

    it "leaves the path alone when it is not a whole segment" do
      expect(rewrite("spec/features/thing", "features", "moved")).to eq("spec/features/thing")
    end

    # A bare token at the end of a line is how cucumber.yml names its feature
    # directory -- `default: <%= std_opts %> features` -- so substitution has to
    # match it, and cannot tell it apart from the same word used as prose. That
    # is why the scanner, which reads application code rather than config, uses
    # the prefix and quoted patterns instead.
    it "does match a bare token at the end of a line, which config files rely on" do
      expect(rewrite("default: <%= std_opts %> features"))
        .to eq("default: <%= std_opts %> test/cucumber/features")
    end

    it "and the scanner's patterns are the ones that ignore prose" do
      prose = "# this spec was generated, with support features"

      expect(prose).not_to match(described_class.prefix_pattern("features"))
      expect(prose).not_to match(described_class.quoted_pattern("features"))
    end
  end
end

RSpec.describe "a ./ path in a real config" do
  it "is rewritten in cucumber.yml, prefix and all" do
    box = sandbox(gems: %w[cucumber-rails], dirs: %w[features/support],
                  files: { "cucumber.yml" => "default: -r ./features/support --strict ./features\n" })
    box.run

    active = box.read("cucumber.yml").lines.reject { |line| line.strip.start_with?("#") }.join
    expect(active).to include("-r ./test/cucumber/features/support")
    expect(active).to include("--strict ./test/cucumber/features")
  end

  it "is restored exactly, ./ and all, on rollback" do
    original = "default: -r ./features/support --strict ./features\n"
    box = sandbox(gems: %w[cucumber-rails], dirs: %w[features/support],
                  files: { "cucumber.yml" => original })
    box.run
    box.runner.rollback

    expect(box.read("cucumber.yml")).to eq(original)
  end

  it "is rewritten in package.json too" do
    box = sandbox(packages: %w[jest], dirs: %w[spec/javascript])
    box.write("package.json", box.read("package.json").sub("jest spec/javascript", "jest ./spec/javascript"))
    box.commit("relative path")
    box.run

    expect(JSON.parse(box.read("package.json"))["scripts"]["test"]).to eq("jest ./test/javascript/jest")
  end

  it "is reported by the scanner when it is left in application code" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.write("lib/tasks/report.rake", %(task(:r) { Dir["./spec/**/*_spec.rb"] }\n))
    box.commit("relative reference")
    box.run

    expect(Oubliette::Scanner.new(box.root, box.manifest).findings.map(&:file))
      .to include("lib/tasks/report.rake")
  end
end
