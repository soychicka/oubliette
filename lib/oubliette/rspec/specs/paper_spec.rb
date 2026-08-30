# frozen_string_literal: true

RSpec.describe Oubliette::Paper do
  it "writes a README and a recovery note once something is displaced" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.run

    expect(box).to be_exist(Oubliette::Paper::Readme::FILENAME)
    expect(box).to be_exist(Oubliette::Paper::Recovery::FILENAME)
  end

  it "puts every move in the recovery table" do
    box = sandbox(gems: %w[rspec-rails cucumber-rails], dirs: %w[spec features])
    box.run

    recovery = box.read(Oubliette::Paper::Recovery::FILENAME)
    expect(recovery).to include("| spec").and include("test/rspec")
    expect(recovery).to include("| features").and include("test/cucumber/features")
  end

  it "says that edits to it are ignored" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.run

    expect(box.read(Oubliette::Paper::Recovery::FILENAME)).to include("ignored and will be overwritten")
    expect(box.read(Oubliette::Paper::Readme::FILENAME)).to include("rewrites it on every run")
  end

  it "names the markers a person would have to search for by hand" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.run

    expect(box.read(Oubliette::Paper::Recovery::FILENAME))
      .to include(Oubliette::Config::ManagedBlock::OPEN)
      .and include(Oubliette::Config::ManagedBlock::CLOSE)
    expect(box.read(".rspec")).to include(Oubliette::Config::ManagedBlock::OPEN)
  end

  it "explains why the javascript configs are left to the developer" do
    box = new_sandbox(gems: %w[rspec-rails], packages: %w[cypress], dirs: %w[spec cypress],
                      files: { "cypress.config.js" => "module.exports = {}\n" })
    box.run

    readme = box.read(Oubliette::Paper::Readme::FILENAME)
    expect(readme).to include("Cypress").and include("executable code, not data")
    expect(readme).to include("e2e.specPattern")
  end

  it "says so plainly when nothing needs a hand edit" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.run

    expect(box.read(Oubliette::Paper::Readme::FILENAME)).to include("Every framework oubliette moved here was configured for you")
  end

  it "overwrites whatever somebody typed into it" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.run
    box.write(Oubliette::Paper::Recovery::FILENAME, "my own notes\n")
    box.runner.call

    expect(box.read(Oubliette::Paper::Recovery::FILENAME)).not_to include("my own notes")
  end

  it "takes both papers away once everything is home again" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.run
    box.runner.rollback

    expect(box.exist?(Oubliette::Paper::Readme::FILENAME)).to be(false)
    expect(box.exist?(Oubliette::Paper::Recovery::FILENAME)).to be(false)
  end

  it "writes nothing during a dry run" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.run(dry_run: true)

    expect(box.exist?(Oubliette::Paper::Readme::FILENAME)).to be(false)
  end
end

RSpec.describe "#{Oubliette::Runner} closing message" do
  it "names files that are really there" do
    box = new_sandbox(gems: %w[rspec-rails], packages: %w[cypress], dirs: %w[spec cypress],
                      files: { "cypress.config.js" => "module.exports = {}\n" })
    box.run

    named = box.log.lines.filter_map { |line| line[%r{^  (/\S+)$}, 1] }

    expect(named).not_to be_empty
    expect(named.reject { |path| File.exist?(path) }).to be_empty
  end

  it "points at the recovery note" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.run

    expect(box.log).to include(Oubliette::Paper::Recovery::FILENAME)
  end
end
