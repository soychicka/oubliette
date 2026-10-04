# frozen_string_literal: true

require "rspec/core"
require "yaml"

# Asserts that a real project -- as opposed to a sandbox -- is fully and
# consistently migrated. This is the example group a host application includes
# in its own suite:
#
#   require "oubliette/rspec"
#   RSpec.describe "test layout" do
#     it_behaves_like "an oubliette-managed project", Rails.root
#   end
RSpec.shared_examples "an oubliette-managed project" do |project_root|
  let(:root) { Pathname.new(project_root) }
  let(:manifest) { Oubliette::Manifest.load(root) }

  it "has a migrate.yml describing the layout" do
    expect(Oubliette::Manifest.exists_in?(root)).to be(true),
      "expected #{root}/migrate.yml -- run `rake oubliette:prepare`"
  end

  it "has a rollback.yml recording where everything came from" do
    expect(Oubliette::Ledger.exists_in?(root)).to be(true),
      "expected #{root}/rollback.yml -- run `rake oubliette`"
  end

  it "can name an origin for every directory it has moved" do
    ledger = Oubliette::Ledger.load(root)
    # A configured pair is never moved and so never recorded: coverage reports
    # are written afresh wherever the tool is pointed, which is the whole job.
    unrecorded = manifest.pairs
                         .reject { |pair| pair.canonical? || pair.configured? }
                         .reject { |pair| ledger.current(pair.gem, pair.origin) }

    expect(unrecorded.map(&:origin)).to be_empty
  end

  it "has moved every directory it claims to manage" do
    unmoved = manifest.pending

    expect(unmoved).to be_empty,
      "still at their original paths: #{unmoved.map(&:origin).join(', ')} -- run `rake oubliette`"
  end

  it "has no directory missing from both its old and new location" do
    expect(manifest.missing.map { |pair| "#{pair.gem}:#{pair.origin}" }).to be_empty
  end

  it "points every recorded destination at a directory that exists" do
    absent = manifest.pairs.reject(&:missing?).map(&:oubliette).reject { |path| root.join(path).exist? }

    expect(absent).to be_empty
  end

  it "passes the runtime verification the test suite boots with" do
    expect { Oubliette::Runtime.verify!(manifest) }.not_to raise_error
  end

  it "points .rspec at the relocated spec tree" do
    destination = manifest.destination("rspec-rails")
    skip "project does not use rspec" if destination.nil?

    expect(Oubliette.read(root.join(".rspec"))).to include("--default-path #{destination}")
  end

  it "points cucumber.yml at the relocated features tree" do
    destination = manifest.destination("cucumber-rails")
    skip "project does not use cucumber" if destination.nil?

    # cucumber-rails writes config/cucumber.yml while a plain cucumber project
    # keeps it at the root. Looking only at the root quietly skipped this check
    # on every rails application, which is most of them.
    config = Oubliette::Config::Cucumber::CANDIDATES.map { |name| root.join(name) }.find(&:file?)
    skip "project has no cucumber.yml" if config.nil?

    # Only the lines cucumber actually reads. Oubliette keeps each original
    # above its replacement, commented out, so the old path is still in the
    # file on purpose and finding it there proves nothing.
    active = Oubliette.read(config).lines.reject { |line| line.strip.start_with?("#") }.join

    expect(active).to include(destination)
    expect(active).not_to match(Oubliette::PathToken.pattern("features"))
  end
end
