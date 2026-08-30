# frozen_string_literal: true

RSpec.describe Oubliette::Runs do
  def log_for(box) = described_class.new(box.root)

  def result(suite, examples, failures = 0, seconds = 1.0)
    described_class::Result.new(suite: suite, passed: failures.zero?,
                                examples: examples, failures: failures, seconds: seconds)
  end

  it "writes a header and one line per suite" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    entry = log_for(box).record([ result("rspec", 26), result("jest", 18) ],
                                marker: "after migrate", revision: "a3f9c21")

    expect(entry.lines.length).to eq(4) # header, two suites, blank
    expect(entry).to include("2 suites").and include("44 examples")
    expect(entry).to match(/^    rspec\s+26/)
  end

  it "puts the newest run at the top" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    log = log_for(box)
    log.record([ result("rspec", 1) ], marker: "before migrate", revision: "aaa")
    log.record([ result("rspec", 2) ], marker: "after migrate", revision: "bbb")

    expect(box.read(Oubliette::Runs::PATH).lines.first).to include("bbb")
  end

  it "reports a count that moved between runs" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    log = log_for(box)
    log.record([ result("rspec", 26), result("cucumber", 2) ], marker: "before migrate", revision: "aaa")

    expect(log.drift([ result("rspec", 26), result("cucumber", 0) ])).to eq([ "cucumber 2 -> 0" ])
  end

  it "says nothing when the counts held" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    log = log_for(box)
    log.record([ result("rspec", 26) ], marker: "before migrate", revision: "aaa")

    expect(log.drift([ result("rspec", 26) ])).to be_empty
  end

  it "has no drift to report before the first run" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])

    expect(log_for(box).drift([ result("rspec", 26) ])).to be_empty
    expect(log_for(box)).not_to be_any
  end

  it "moves old runs into history once the log grows past its limit" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    log = log_for(box)
    200.times { |n| log.record([ result("rspec", n) ], marker: "after migrate", revision: "r#{n}") }

    expect(box.read(Oubliette::Runs::PATH).lines.length).to be <= Oubliette::Runs::LIMIT
    expect(box.root.glob("#{Oubliette::Runs::HISTORY}/*.log")).not_to be_empty
  end

  it "keeps the newest runs and archives the oldest" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    log = log_for(box)
    200.times { |n| log.record([ result("rspec", n) ], marker: "after migrate", revision: "r#{n}") }

    expect(box.read(Oubliette::Runs::PATH)).to include("r199")
    expect(box.root.glob("#{Oubliette::Runs::HISTORY}/*.log").first.read).to include("r0")
  end
end

RSpec.describe Oubliette::Suites do
  it "finds rspec when the project declares it" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])

    expect(described_class.for(box.root, box.manifest_built).map(&:key)).to include("rspec")
  end

  it "does not offer a runner the project does not have" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])

    expect(described_class.for(box.root, box.manifest_built).map(&:key)).not_to include("cucumber")
  end

  it "uses npm test rather than guessing at a javascript runner" do
    box = sandbox(packages: %w[jest], dirs: %w[spec/javascript])
    suite = described_class.for(box.root, box.manifest_built).find { |s| s.key == "javascript" }

    expect(suite.command).to start_with("npm", "test")
  end

  it "skips javascript when package.json declares no test script" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.write("package.json", %({"name":"x"}\n))

    expect(described_class.for(box.root, box.manifest_built).map(&:key)).not_to include("javascript")
  end

  it "does not offer bin/rails test when there is no bin/rails" do
    box = sandbox(gems: %w[minitest], dirs: %w[test/models])

    expect(described_class.for(box.root, box.manifest_built).map(&:key)).not_to include("minitest")
  end
end

RSpec.describe "#{Oubliette::Suite} parsing counts" do
  def suite(counts) = Oubliette::Suite.new(key: "x", label: "x", command: [], counts: counts)

  it "reads rspec's total" do
    parsed = suite(examples: /(\d+) examples?,/, failures: /(\d+) failures?/).tally("26 examples, 0 failures\n")

    expect(parsed).to eq(examples: 26, failures: 0)
  end

  it "reads cucumber's total" do
    parsed = suite(examples: /(\d+) scenarios? \(/, failures: /(\d+) failed/).tally("2 scenarios (2 passed)\n")

    expect(parsed[:examples]).to eq(2)
  end

  it "gives up quietly when the wording is not recognised" do
    parsed = suite(examples: /(\d+) examples?,/, failures: /(\d+) failures?/).tally("all good chief\n")

    expect(parsed).to eq(examples: nil, failures: nil)
  end
end
