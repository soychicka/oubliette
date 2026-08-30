# frozen_string_literal: true

RSpec.describe Oubliette::Uninstall do
  def uninstall_for(box, input: StringIO.new)
    described_class.new(box.root, out: box.output, input: input)
  end

  it "puts every directory back and removes its own record" do
    box = sandbox(gems: %w[rspec-rails cucumber-rails], dirs: %w[spec features])
    box.run

    expect(uninstall_for(box).call).to eq(:done)
    expect(box).to be_exist("spec")
    expect(box).to be_exist("features")
    expect(box.exist?(Oubliette::Ledger::PATH)).to be(false)
  end

  it "leaves migrate.yml for the developer, since they wrote it" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.run
    uninstall_for(box).call

    expect(box).to be_exist(Oubliette::Manifest::PATH)
    expect(box.log).to include(Oubliette::Manifest::PATH)
  end

  it "does nothing at all when oubliette was never run" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])

    expect(uninstall_for(box).call).to eq(:absent)
  end

  it "stops without touching anything when the answer is no" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.run

    expect(uninstall_for(box, input: box.answering("n\n")).call).to eq(:declined)
    expect(box).to be_exist("test/rspec")
    expect(box).to be_exist(Oubliette::Ledger::PATH)
  end

  it "keeps a guide somebody has written in, and removes one nobody touched" do
    box = new_sandbox(gems: %w[rspec-rails], packages: %w[vitest cypress],
                      dirs: %w[spec tests/unit cypress],
                      files: { "vitest.config.js" => "export default {}\n",
                               "cypress.config.js" => "module.exports = {}\n" })
    box.run
    guides = box.root.glob("#{Oubliette::HOME}/*.md")
    expect(guides.length).to eq(2)
    guides.first.write("#{guides.first.read}\nDone on Tuesday. Also had to fix the CI cache.\n")

    uninstall_for(box).call

    expect(guides.first).to be_file
    expect(guides.last).not_to be_file
    expect(box.log).to include("a guide you have edited")
  end

  it "lists the test history rather than deleting it" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.run
    box.write(Oubliette::Runs::PATH, "2026-08-30  after migrate  a3f9c21\n")

    uninstall_for(box).call

    expect(box).to be_exist(Oubliette::Runs::PATH)
    expect(box.log).to include("test history")
  end

  it "lists coverage output stranded by restoring the configuration" do
    box = sandbox(gems: %w[rspec-rails simplecov], dirs: %w[spec coverage])
    box.run
    box.touch("test/results/coverage/index.html")

    uninstall_for(box).call

    expect(box.log).to include("test/results/coverage").and include("now stale")
  end

  it "names what it removed on its own" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.run
    uninstall_for(box).call

    expect(box.log).to include("removed automatically: #{Oubliette::Ledger::PATH}")
    expect(box.log).to include("oubliette has put everything back")
  end
end
