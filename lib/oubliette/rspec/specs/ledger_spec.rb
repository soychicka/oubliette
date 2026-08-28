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
