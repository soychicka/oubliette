# frozen_string_literal: true

RSpec.describe Oubliette::Ledger do
  it "records where a directory started and where it is now" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run
    ledger = described_class.load(box.root)

    expect(ledger.current("rspec-rails", "spec")).to eq("test/rspec")
  end

  it "still knows the origin after migrate.yml has been retargeted" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run
    box.write("migrate.yml", box.read("migrate.yml").sub("oubliette: test/rspec", "oubliette: test/examples"))
    box.commit("retarget")
    box.run

    ledger = described_class.load(box.root)
    expect(ledger.pairs.map(&:origin)).to eq(%w[spec])
    expect(ledger.current("rspec-rails", "spec")).to eq("test/examples")
  end

  it "survives migrate.yml being deleted outright" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run
    FileUtils.rm(box.root.join("migrate.yml"))
    box.commit("lost the manifest")
    box.runner.rollback

    expect(box).to be_exist("spec/models")
    expect(box).not_to be_exist("test/rspec")
  end

  it "lists what it has moved deepest origin first, so a nested directory is handled first" do
    box = sandbox(gems: %w[rspec-rails factory_bot_rails], dirs: %w[spec/models spec/factories])
    box.run

    expect(described_class.load(box.root).pairs.map(&:origin)).to eq(%w[spec/factories spec])
  end
end

RSpec.describe "#{Oubliette}.path" do
  it "answers with the relocated directory once it has moved" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run
    Oubliette.root = box.root

    expect(Oubliette.path("rspec-rails").to_s).to end_with("test/rspec")
  ensure
    Oubliette.root = nil
  end

  it "answers with the origin after a rollback, not the target migrate.yml still names" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run
    box.runner.rollback
    Oubliette.root = box.root

    expect(Oubliette.path("rspec-rails").to_s).to end_with("/spec")
    expect(box.read("migrate.yml")).to include("oubliette: test/rspec")
  ensure
    Oubliette.root = nil
  end
end

RSpec.describe "#{Oubliette::Ledger} nested pairs" do
  # spec/system's target lives inside spec's target, so restoring the parent
  # carries the child home with it. The ledger has to notice.
  it "still knows where a nested directory went after a rollback" do
    box = sandbox(gems: %w[rspec-rails capybara], dirs: %w[spec/models spec/system])
    box.run
    expect(box).to be_exist("test/rspec/system")

    box.runner.rollback

    expect(box).to be_exist("spec/system")
    expect(box.manifest.missing).to be_empty
    expect(Oubliette::Ledger.load(box.root).current("capybara", "spec/system")).to eq("spec/system")
  end

  it "re-migrates a nested directory on the next run" do
    box = sandbox(gems: %w[rspec-rails capybara], dirs: %w[spec/models spec/system])
    box.run
    box.runner.rollback
    box.commit("rolled back")
    box.run

    expect(box).to be_exist("test/rspec/system")
  end
end
