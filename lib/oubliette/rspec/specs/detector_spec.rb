# frozen_string_literal: true

RSpec.describe Oubliette::Detector do
  def detect(sandbox)
    described_class.new(sandbox.root).detections.to_h { |detection| [ detection.key, detection ] }
  end

  it "finds a framework named in the Gemfile" do
    found = detect(sandbox(gems: %w[rspec-rails], dirs: %w[spec/models]))

    expect(found.keys).to include("rspec-rails")
    expect(found["rspec-rails"].evidence).to include(a_string_matching(/Gemfile/))
  end

  it "finds a framework named only in the Gemfile.lock" do
    box = sandbox(dirs: %w[spec])
    box.write("Gemfile.lock", "GEM\n  specs:\n    rspec-rails (7.1.0)\n    rake (13.0.0)\n")

    expect(detect(box).keys).to include("rspec-rails")
  end

  it "finds a framework from package.json" do
    found = detect(sandbox(packages: %w[jest], dirs: %w[spec/javascript]))

    expect(found.keys).to include("jest")
    expect(found["jest"].evidence).to include(a_string_matching(/package\.json/))
  end

  it "finds a framework from its directory alone" do
    expect(detect(sandbox(dirs: %w[features/step_definitions])).keys).to include("cucumber-rails")
  end

  it "ignores frameworks with neither a dependency nor a directory" do
    expect(detect(sandbox(gems: %w[rspec-rails], dirs: %w[spec])).keys).not_to include("cypress")
  end

  it "reports test-shaped directories that belong to no framework" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec despec unspec app/models])
    claimed = %w[spec features test coverage]

    expect(described_class.new(box.root).strays(claimed)).to eq(%w[despec unspec])
  end
end

RSpec.describe "#{Oubliette::Detector} evidence tiers" do
  def detect(box, key)
    Oubliette::Detector.new(box.root).detections.find { |d| d.key == key }
  end

  it "calls a gem you put in your Gemfile declared" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])

    expect(detect(box, "rspec-rails").tier).to eq(:declared)
    expect(detect(box, "rspec-rails").evidence).to include("Gemfile: rspec-rails")
  end

  it "calls a gem that only reached the lockfile locked" do
    box = sandbox(dirs: %w[test/models])
    box.write("Gemfile", "source 'https://rubygems.org'\ngem 'rails'\n")
    box.write("Gemfile.lock", "GEM\n  specs:\n    rails (8.0.0)\n    minitest (5.25.0)\n")

    expect(detect(box, "minitest").tier).to eq(:locked)
    expect(detect(box, "minitest").evidence).to include("Gemfile.lock: minitest")
  end

  it "does not describe a transitive gem as one you chose" do
    box = sandbox(dirs: %w[test/models])
    box.write("Gemfile.lock", "GEM\n  specs:\n    minitest (5.25.0)\n")

    expect(detect(box, "minitest").evidence).not_to include(a_string_starting_with("Gemfile:"))
  end

  it "calls a framework known only from a directory disk" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec test/unit])

    expect(detect(box, "test-unit").tier).to eq(:disk)
  end

  it "treats a package.json dependency as declared" do
    box = sandbox(packages: %w[jest], dirs: %w[spec/javascript])

    expect(detect(box, "jest").tier).to eq(:declared)
  end
end
