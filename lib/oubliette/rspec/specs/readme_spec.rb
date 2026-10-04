# frozen_string_literal: true

# The catalog is the only record of what oubliette handles; a reader consults
# the README instead. Adding an entry without adding a row leaves the gem
# quietly claiming to support less than it does, and nothing else would notice.
RSpec.describe "the README's degrees of support" do
  let(:readme) { Pathname.new(File.expand_path("../../../../README.md", __dir__)) }
  # Explicit UTF-8: this machine's default external encoding is US-ASCII, and
  # the section is full of em-dashes.
  let(:section) { readme.read(encoding: "UTF-8")[/^## Degrees of support$.*?(?=^## )/m].to_s }

  # The tiers the section defines for itself, rather than a second list here
  # that could drift from it.
  let(:defined) { section.scan(/^- \*\*(\w+)\*\*/).flatten }

  let(:graded) do
    section.lines.grep(/\A\|/).filter_map do |line|
      cell = line.chomp.split("|").map(&:strip).last.to_s.gsub(/[\\*]/, "")
      next if cell.empty? || cell == "Support" || cell.match?(/\A-+\z/)

      cell
    end
  end

  # Shared test material is named in the paragraph under the tables instead of
  # being given a row: nobody runs it, so there is no support to grade.
  let(:exempt) { %w[support] }

  it "exists" do
    expect(section).not_to be_empty
  end

  it "has a row for every framework in the catalog" do
    frameworks = Oubliette::Catalog.entries
      .reject { |entry| entry[:kind] == :data }
      .map { |entry| entry[:key] } - exempt

    expect(frameworks.reject { |key| section.include?(key) }).to be_empty
  end

  it "grades every framework it lists" do
    expect(graded).not_to be_empty
    expect(graded.uniq - defined).to be_empty
  end

  it "defines no tier it never awards" do
    expect(defined - graded.uniq).to be_empty
  end
end
