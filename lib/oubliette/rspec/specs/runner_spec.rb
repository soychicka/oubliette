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
    expect(box).to be_exist("test/rspec/support")
    expect(box).to be_exist("test/rspec/system")
    expect(box).to be_exist("test/cucumber/features/step_definitions")
    expect(box).to be_exist("test/javascript/jest")
    expect(box).to be_exist("test/minitest/models")
    expect(box).to be_exist("test/unit")
    expect(box).to be_exist("test/results/reports")
    # coverage/ is generated output: configured, never moved.
    expect(box).to be_exist("coverage")
  end

  it "keeps rspec system specs inside the tree rspec collects from" do
    box = new_sandbox(gems: %w[rspec-rails capybara], dirs: %w[spec/models spec/system])
    box.run

    expect(box).to be_exist("test/rspec/system")
    expect(box.read(".rspec")).to include("--default-path test/rspec")
  end

  it "leaves no original location behind" do
    box = full_app
    box.run

    %w[spec features test/models test/fixtures test_results].each do |path|
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
    before = box.read(Oubliette::Manifest::PATH)
    box.run

    expect(box.read(Oubliette::Manifest::PATH)).to eq(before)
    expect(box.manifest.pairs.map(&:status).uniq).to contain_exactly(:settled, :canonical, :configured)
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
    box.write(Oubliette::Manifest::PATH, box.read(Oubliette::Manifest::PATH).sub("oubliette: test/rspec", "oubliette: test/examples"))
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
    expect(box).not_to be_exist(Oubliette::Manifest::PATH)
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

    expect { box.run }.to raise_error(Oubliette::Error, %r{spec/models/user_spec\.rb})
    expect(box).to be_exist("spec/models")
  end

  it "reports a directory that is missing from both locations" do
    box = new_sandbox(gems: %w[rspec-rails cucumber-rails], dirs: %w[spec/models features/support])
    box.run
    FileUtils.remove_entry(box.root.join("test/cucumber"))
    box.commit("someone deleted the features")
    box.run

    expect(box.log).to include("MISSING")
    expect(box.manifest.missing.map(&:origin)).to eq(%w[features])
  end

  it "skips a directory migrate.yml and rollback.yml already agree about" do
    box = new_sandbox(gems: %w[rspec-rails cucumber-rails], dirs: %w[spec/models features/support])
    box.run
    box.commit("migrated")
    box.write(Oubliette::Manifest::PATH, box.read(Oubliette::Manifest::PATH).sub("oubliette: test/rspec", "oubliette: test/examples"))
    box.run

    relocations = box.log.lines.map(&:chomp).count("  features -> test/cucumber/features")
    expect(relocations).to eq(1)
    expect(box).to be_exist("test/cucumber/features/support")
    expect(box).to be_exist("test/examples/models")
  end

  it "restores the original location even after migrate.yml has been retargeted twice" do
    box = new_sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run
    box.write(Oubliette::Manifest::PATH, box.read(Oubliette::Manifest::PATH).sub("oubliette: test/rspec", "oubliette: test/examples"))
    box.run
    box.write(Oubliette::Manifest::PATH, box.read(Oubliette::Manifest::PATH).sub("oubliette: test/examples", "oubliette: test/somewhere"))
    box.run
    box.runner.rollback

    expect(box).to be_exist("spec/models")
    expect(box).not_to be_exist("test/somewhere")
  end

  it "rolls back to the origin even when migrate.yml is gibberish" do
    box = new_sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run
    box.write(Oubliette::Manifest::PATH, "version: 1\ngems: {}\nstrays: {}\n")
    box.commit("mangled the manifest")
    box.runner.rollback

    expect(box).to be_exist("spec/models")
    expect(box).not_to be_exist("test/rspec")
  end

  it "answers to put_back as well as rollback" do
    box = new_sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run
    box.runner.put_back("rspec-rails")

    expect(box).to be_exist("spec/models")
  end

  it "puts oubliette's own targets back on reset, and moves to match" do
    box = new_sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run
    box.write(Oubliette::Manifest::PATH, box.read(Oubliette::Manifest::PATH).sub("oubliette: test/rspec", "oubliette: test/examples"))
    box.run
    box.commit("retargeted")
    box.runner.reset

    expect(box).to be_exist("test/rspec/models")
    expect(box).not_to be_exist("test/examples")
    expect(box.read(Oubliette::Manifest::PATH)).to include("oubliette: test/rspec")
    expect(box.read(".rspec")).to include("--default-path test/rspec")
  end

  it "resets one framework and leaves another framework's edit in place" do
    box = new_sandbox(gems: %w[rspec-rails cucumber-rails], dirs: %w[spec/models features/support])
    box.run
    edited = box.read(Oubliette::Manifest::PATH)
      .sub("oubliette: test/rspec", "oubliette: test/examples")
      .sub("oubliette: test/cucumber/features", "oubliette: test/gherkin")
    box.write(Oubliette::Manifest::PATH, edited)
    box.run
    box.commit("retargeted both")
    box.runner.reset("rspec-rails")

    expect(box).to be_exist("test/rspec/models")
    expect(box).to be_exist("test/gherkin/support")
  end
end

RSpec.describe "generated output" do
  # Coverage reports are written afresh by the tool that makes them. Moving
  # yesterday's copy achieves nothing and guarantees a collision the next time
  # the suite runs, which is what made the gem unusable after one cycle.
  it "leaves the coverage directory where it is" do
    box = new_sandbox(gems: %w[rspec-rails simplecov], dirs: %w[spec/models])
    box.write("coverage/index.html", "generated")
    box.commit("a coverage report")
    box.run

    expect(box).to be_exist("coverage/index.html")
    expect(box).not_to be_exist("test/results/coverage")
  end

  it "still tells the tool where to write from now on" do
    box = new_sandbox(gems: %w[rspec-rails simplecov], dirs: %w[spec/models])
    box.write("coverage/index.html", "generated")
    box.commit("a coverage report")
    box.run

    expect(box.manifest.destination("simplecov")).to eq("test/results/coverage")
  end

  it "does not collide when the report is regenerated and the task run again" do
    box = new_sandbox(gems: %w[rspec-rails simplecov], dirs: %w[spec/models])
    box.write("coverage/index.html", "generated")
    box.commit("a coverage report")
    box.run
    box.commit("migrated")
    box.write("coverage/index.html", "regenerated by the next test run")
    box.commit("ran the suite again")

    expect { box.run }.not_to raise_error
  end

  it "reports it as configured rather than pending forever" do
    box = new_sandbox(gems: %w[rspec-rails simplecov], dirs: %w[spec/models])
    box.write("coverage/index.html", "generated")
    box.commit("a coverage report")
    box.run

    expect(box.manifest.pairs(only: "simplecov").map(&:status)).to eq([ :configured ])
  end
end

RSpec.describe "a migration reverted from outside" do
  it "asks to be migrated again rather than reporting itself lost" do
    box = new_sandbox(gems: %w[rspec-rails minitest], dirs: %w[spec/models test/controllers])
    box.run
    # Exactly the reported case: the migration's staged renames are thrown away
    # while oubliette's own untracked files survive, so it still believes.
    system("git", "-C", box.root.to_s, "reset", "--hard", "HEAD", out: File::NULL, err: File::NULL)

    statuses = box.manifest.pairs.map(&:status)
    expect(statuses).to all(eq(:pending))
    expect(box.manifest.missing).to be_empty
  end
end

RSpec.describe "what counts as a tree too dirty to move" do
  # Installing the gem edits the Gemfile, so the very first thing a user does
  # guaranteed a refusal. Work oubliette cannot affect is none of its business.
  it "does not care about uncommitted work outside the directories being moved" do
    box = new_sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.write("Gemfile", "#{box.read('Gemfile')}gem 'oubliette'\n")
    box.write("app/models/user.rb", "class User; end\n")

    expect { box.run }.not_to raise_error
    expect(box).to be_exist("test/rspec/models")
  end

  it "still refuses when the work is inside a directory it is about to move" do
    box = new_sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.touch("spec/models/user_spec.rb")

    expect { box.run }.to raise_error(Oubliette::Error, %r{spec/models/user_spec\.rb})
  end

  it "names what is in the way rather than saying the tree is dirty" do
    box = new_sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.touch("spec/models/one_spec.rb")
    box.touch("spec/models/two_spec.rb")

    expect { box.run }.to raise_error(Oubliette::Error) { |error|
      expect(error.message).to include("one_spec.rb").and include("two_spec.rb")
    }
  end

  it "can still be overridden" do
    box = new_sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.touch("spec/models/user_spec.rb")

    expect { box.runner(force: true).call }.not_to raise_error
  end
end
