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
    box.write(Oubliette::Manifest::PATH, box.read(Oubliette::Manifest::PATH).sub("oubliette: test/rspec", "oubliette: test/examples"))
    box.commit("retarget")
    box.run

    ledger = described_class.load(box.root)
    expect(ledger.pairs.map(&:origin)).to eq(%w[spec])
    expect(ledger.current("rspec-rails", "spec")).to eq("test/examples")
  end

  it "survives migrate.yml being deleted outright" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run
    FileUtils.rm(box.root.join(Oubliette::Manifest::PATH))
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

  # Callers pair this with their own default -- `Oubliette.path(k) || "spec"` --
  # so nil is the right answer for "nothing moved", and the target migrate.yml
  # still names is the wrong one. Answering with it would send a suite to a
  # directory the rollback has just emptied.
  it "answers with nothing after a rollback, whatever migrate.yml still names" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run
    box.runner.rollback
    Oubliette.root = box.root

    expect(Oubliette.path("rspec-rails")).to be_nil
    expect(box.read(Oubliette::Manifest::PATH)).to include("oubliette: test/rspec")
  ensure
    Oubliette.root = nil
  end

  it "answers with nothing after an uninstall, which leaves migrate.yml behind" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run
    Oubliette::Uninstall.new(box.root, out: box.output, input: StringIO.new).call
    Oubliette.root = box.root

    expect(box).to be_exist(Oubliette::Manifest::PATH)
    expect(Oubliette.path("rspec-rails")).to be_nil
  ensure
    Oubliette.root = nil
  end

  it "still answers for a framework left displaced by a partial rollback" do
    box = sandbox(gems: %w[rspec-rails cucumber-rails], dirs: %w[spec/models features/support])
    box.run
    box.runner.rollback("cucumber-rails")
    Oubliette.root = box.root

    expect(Oubliette.path("cucumber-rails").to_s).to end_with("/features")
    expect(Oubliette.path("rspec-rails").to_s).to end_with("test/rspec")
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

RSpec.describe "migrating a second time after a rollback" do
  # Rollback used to leave the emptied parent behind, and the next run found
  # test/javascript sitting there and tried to fold it into test/javascript/jest.
  it "does not leave an emptied parent directory behind" do
    box = sandbox(packages: %w[jest], dirs: %w[spec/javascript])
    box.run
    box.runner.rollback

    expect(box).to be_exist("spec/javascript")
    expect(box).not_to be_exist("test/javascript")
  end

  it "migrates cleanly all over again" do
    box = sandbox(gems: %w[rspec-rails], packages: %w[jest], dirs: %w[spec/models spec/javascript])
    box.run
    box.runner.rollback
    box.commit("rolled back")

    expect { box.run }.not_to raise_error
    expect(box).to be_exist("test/javascript/jest")
    expect(box).not_to be_exist("test/javascript/jest/jest")
  end

  it "survives three round trips" do
    box = sandbox(gems: %w[rspec-rails], packages: %w[jest], dirs: %w[spec/models spec/javascript])

    3.times do
      box.run
      box.commit("migrated")
      box.runner.rollback
      box.commit("rolled back")
    end

    expect(box).to be_exist("spec/models")
    expect(box).to be_exist("spec/javascript")
  end

  it "ignores a directory that has nothing in it" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    FileUtils.mkdir_p(box.root.join("features"))
    box.commit("an empty features directory")

    expect(Oubliette::Manifest.build(box.root).pairs.map(&:origin)).not_to include("features")
  end
end
