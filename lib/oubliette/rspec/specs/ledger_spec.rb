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

  it "lists what it has moved shallowest origin first, the order a restore wants" do
    box = sandbox(gems: %w[rspec-rails factory_bot_rails], dirs: %w[spec/models spec/factories])
    box.run

    expect(described_class.load(box.root).pairs.map(&:origin)).to eq(%w[spec spec/factories])
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
