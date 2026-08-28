# frozen_string_literal: true

RSpec.describe Oubliette::Runner do
  # A project with one of everything, standing in for the freshly generated app
  # the gem is meant to be dropped into.
  def full_app
    new_sandbox(
      gems: %w[rspec-rails cucumber-rails factory_bot_rails capybara vcr simplecov minitest],
      packages: %w[jest],
      dirs: %w[
        spec/models spec/controllers spec/factories spec/support spec/attributes
        spec/system spec/vcr_cassettes spec/javascript
        features/step_definitions features/support
        test/models test/unit test/fixtures
        test_results coverage
      ],
      files: {
        ".rspec" => "--require spec_helper\n--color\n",
        "cucumber.yml" => "default: -r features/support -r features/step_definitions features\n"
      }
    )
  end

  it "gathers every framework's assets under one test tree" do
    box = full_app
    box.run

    expect(box).to be_exist("test/rspec/models")
    expect(box).to be_exist("test/rspec/controllers")
    expect(box).to be_exist("test/data/factories")
    expect(box).to be_exist("test/data/attributes")
    expect(box).to be_exist("test/data/fixtures")
    expect(box).to be_exist("test/data/cassettes")
    expect(box).to be_exist("test/support")
    expect(box).to be_exist("test/system")
    expect(box).to be_exist("test/cucumber/features/step_definitions")
    expect(box).to be_exist("test/javascript/jest")
    expect(box).to be_exist("test/minitest/models")
    expect(box).to be_exist("test/unit")
    expect(box).to be_exist("test/results/reports")
    expect(box).to be_exist("test/results/coverage")
  end

  it "leaves no original location behind" do
    box = full_app
    box.run

    %w[spec features test/models test/fixtures test_results coverage].each do |path|
      expect(box).not_to be_exist(path), "expected #{path} to be gone"
    end
  end

  it "rewrites each framework's config to match" do
    box = full_app
    box.run

    expect(box.read(".rspec")).to include("--default-path test/rspec")
    expect(box.read("cucumber.yml")).to include("test/cucumber/features")
    expect(JSON.parse(box.read("package.json"))["scripts"]["test"]).to eq("jest test/javascript/jest")
  end

  it "changes nothing the second time it runs" do
    box = full_app
    box.run
    before = box.read("migrate.yml")
    box.run

    expect(box.read("migrate.yml")).to eq(before)
    expect(box.manifest.moves.map(&:status).uniq).to contain_exactly("moved", "canonical")
    expect(box).to be_exist("test/rspec/models")
    expect(box).not_to be_exist("test/rspec/rspec")
    expect(box).not_to be_exist("test/javascript/jest/jest")
  end

  it "picks up a framework installed after the first run" do
    box = new_sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run

    box.write("Gemfile", "#{box.read('Gemfile')}gem 'cucumber-rails'\n")
    box.touch("features/support/env.rb")
    box.commit("add cucumber")
    box.run

    expect(box).to be_exist("test/cucumber/features/support/env.rb")
    expect(box).to be_exist("test/rspec/models")
  end

  it "sends a directory home before sending it somewhere new" do
    box = new_sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run
    box.write("migrate.yml", box.read("migrate.yml").sub("to: test/rspec", "to: test/examples"))
    box.run

    expect(box).to be_exist("test/examples/models")
    expect(box).not_to be_exist("test/rspec")
    expect(box.read(".rspec")).to include("--default-path test/examples")
  end

  it "writes nothing at all on a dry run" do
    box = full_app
    box.run(dry_run: true)

    expect(box).to be_exist("spec/models")
    expect(box).not_to be_exist("test/rspec")
    expect(box).not_to be_exist("migrate.yml")
    expect(box.log).to include("spec -> test/rspec")
  end

  it "puts everything back on rollback" do
    box = full_app
    original = box.read("cucumber.yml")
    box.run
    box.runner.rollback

    expect(box).to be_exist("spec/models")
    expect(box).to be_exist("features/step_definitions")
    expect(box).to be_exist("test/models")
    expect(box).not_to be_exist("test/rspec")
    expect(box.read("cucumber.yml")).to eq(original)
    expect(box.read(".rspec")).to eq("--require spec_helper\n--color\n")
  end

  it "rolls back one framework and leaves the rest migrated" do
    box = full_app
    box.run
    box.runner.rollback("cucumber-rails")

    expect(box).to be_exist("features/step_definitions")
    expect(box).to be_exist("test/rspec/models")
    expect(box.read(".rspec")).to include("--default-path test/rspec")
  end

  it "refuses to move anything while the tree has unstaged work" do
    box = new_sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.touch("spec/models/user_spec.rb")

    expect { box.run }.to raise_error(Oubliette::Error, /unstaged or untracked/)
    expect(box).to be_exist("spec/models")
  end

  it "reports a directory that is missing from both locations" do
    box = new_sandbox(gems: %w[rspec-rails cucumber-rails], dirs: %w[spec/models features/support])
    box.run
    FileUtils.remove_entry(box.root.join("test/cucumber"))
    box.commit("someone deleted the features")
    box.run

    expect(box.log).to include("MISSING")
    expect(box.manifest.missing.map(&:from)).to eq(%w[features])
  end
end
