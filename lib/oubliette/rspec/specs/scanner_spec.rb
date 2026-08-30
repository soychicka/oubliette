# frozen_string_literal: true

RSpec.describe Oubliette::Scanner do
  def findings_for(box)
    described_class.new(box.root, Oubliette::Manifest.build(box.root)).findings
  end

  it "reports application code still naming an old location" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.write("lib/tasks/reports.rake", "task(:report) { Dir['spec/**/*_spec.rb'] }\n")

    expect(findings_for(box).map(&:file)).to include("lib/tasks/reports.rake")
  end

  it "leaves words that merely begin with an old location alone" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.write("app/models/spectrum.rb", "class Spectrum; SPECIAL = 'specimen'; end\n")

    expect(findings_for(box).map(&:file)).not_to include("app/models/spectrum.rb")
  end

  it "ignores migrate.yml, which is supposed to name both locations" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    Oubliette::Manifest.build(box.root).save!

    expect(findings_for(box).map(&:file)).not_to include(Oubliette::Manifest::PATH)
  end

  it "finds nothing in a project with no stale references" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.write("app/models/user.rb", "class User; end\n")

    expect(findings_for(box)).to be_empty
  end
end
RSpec.describe "#{Oubliette::Scanner} noise" do
  def findings_for(box)
    Oubliette::Scanner.new(box.root, Oubliette::Manifest.build(box.root)).findings
  end

  it "ignores the old path used as an English word" do
    box = sandbox(gems: %w[rspec-rails cucumber-rails], dirs: %w[spec/models features/support])
    box.write("app/models/note.rb", "# This spec was generated, with support features.\n")

    expect(findings_for(box)).to be_empty
  end

  it "reports the old path used as a quoted directory" do
    box = sandbox(gems: %w[cucumber-rails], dirs: %w[features/support])
    box.write("lib/tasks/stats.rake", "STATS << 'features' if File.exist?('features')\n")

    expect(findings_for(box).map(&:file)).to eq(%w[lib/tasks/stats.rake])
  end
end

RSpec.describe "#{Oubliette::Scanner} and oubliette's own writing" do
  it "does not report the annotations oubliette put in a config file" do
    box = sandbox(gems: %w[cucumber-rails], dirs: %w[features/support],
                  files: { "cucumber.yml" => "default: -r features/support --strict features\n" })
    box.run

    findings = Oubliette::Scanner.new(box.root, box.manifest).findings

    expect(findings.map(&:file)).not_to include("cucumber.yml")
  end

  it "does not report the was: line, whose purpose is to hold the old path" do
    box = sandbox(gems: %w[cucumber-rails], dirs: %w[features/support],
                  files: { "cucumber.yml" => "default: -r features/support --strict features\n" })
    box.run

    expect(box.read("cucumber.yml")).to include("# was: default: -r features/support")
    expect(Oubliette::Scanner.new(box.root, box.manifest).findings).to be_empty
  end

  it "still reports a real reference in the same file, outside the block" do
    box = sandbox(gems: %w[cucumber-rails], dirs: %w[features/support],
                  files: { "cucumber.yml" => "default: -r features/support --strict features\n" })
    box.run
    box.write("cucumber.yml", "#{box.read('cucumber.yml')}smoke: --tags @smoke features/smoke\n")

    expect(Oubliette::Scanner.new(box.root, box.manifest).findings.map(&:file))
      .to include("cucumber.yml")
  end
end

RSpec.describe "how stale references are reported" do
  def report_for(box)
    box.log.split("stale references to the old locations").last.to_s
  end

  it "names each file once, with its line numbers beneath" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.write("lib/tasks/report.rake", "task(:a) { Dir['spec/**/*'] }\ntask(:b) { Dir['spec/**/*'] }\n")
    box.commit("two references in one file")
    box.run

    report = report_for(box)
    expect(report.scan("lib/tasks/report.rake").length).to eq(1)
    expect(report).to match(/^\s+1\s+task\(:a\)/)
    expect(report).to match(/^\s+2\s+task\(:b\)/)
  end

  it "puts a file of real code before one that is only comments" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.write("app/notes.rb", "# see spec/models/ for the old layout\n")
    box.write("lib/tasks/real.rake", "task(:x) { Dir['spec/**/*'] }\n")
    box.commit("one of each")
    box.run

    report = report_for(box)
    expect(report.index("lib/tasks/real.rake")).to be < report.index("app/notes.rb")
  end

  it "clips a long line rather than wrapping it" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.write("lib/tasks/long.rake", "task(:x) { Dir['spec/#{'y' * 200}'] }\n")
    box.commit("a very long line")
    box.run

    # Only the numbered finding lines; the closing message's absolute paths are
    # long on purpose and must not be clipped.
    finding_lines = report_for(box).lines.map(&:chomp).grep(/^\s+\d+\s{3}/)

    expect(finding_lines).not_to be_empty
    expect(finding_lines.map(&:length).max).to be < 90
  end
end
