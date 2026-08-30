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

  it "does not report a dry run's config as something to fix by hand" do
    box = new_sandbox(gems: %w[rspec-rails], packages: %w[jasmine], dirs: %w[spec spec/jasmine])
    box.write("jasmine.json", %({\n  "spec_dir": "spec/jasmine"\n}\n))
    manifest = Oubliette::Manifest.build(box.root)
    previews = Oubliette::Scanner.preview_of(box.root, manifest)

    findings = Oubliette::Scanner.new(box.root, manifest, previews: previews).findings

    expect(findings.map(&:file)).not_to include("jasmine.json")
  end

  it "still reports a line in that same config that oubliette will not rewrite" do
    box = new_sandbox(gems: %w[rspec-rails], packages: %w[jest], dirs: %w[spec spec/javascript])
    box.write("package.json", <<~JSON)
      {
        "name": "sandbox",
        "scripts": { "test": "jest spec/javascript" },
        "ci": { "artifacts": "spec/javascript" }
      }
    JSON
    manifest = Oubliette::Manifest.build(box.root)
    previews = Oubliette::Scanner.preview_of(box.root, manifest)

    findings = Oubliette::Scanner.new(box.root, manifest, previews: previews).findings.map(&:text)

    expect(findings).to include(a_string_matching(/artifacts/))
    expect(findings).not_to include(a_string_matching(/"test":/))
  end

  it "does not read a package name in package.json as a directory" do
    box = new_sandbox(gems: %w[rspec-rails], packages: %w[cypress jest], dirs: %w[spec cypress])

    expect(findings_for(box).map(&:text)).not_to include(a_string_matching(/"cypress":/))
  end

  it "still reports a path in the value half of a json member" do
    box = new_sandbox(gems: %w[rspec-rails], packages: %w[jasmine], dirs: %w[spec spec/jasmine])
    box.write("config/paths.json", %({\n  "spec_dir": "spec/jasmine"\n}\n))

    finding = findings_for(box).find { |found| found.file == "config/paths.json" }
    expect(finding.suggestion).to eq(%("spec_dir": "test/javascript/jasmine"))
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

RSpec.describe "#{Oubliette::Scanner} on files it cannot decode" do
  it "does not take the run down over an undecodable byte" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.root.join("app/models").mkpath
    box.root.join("app/models/binary.rb").binwrite("# spec/models \xFF\xFE not utf-8\n")
    box.commit("a file with invalid bytes")

    expect { Oubliette::Scanner.new(box.root, Oubliette::Manifest.build(box.root)).findings }.not_to raise_error
  end

  it "still finds the reference in it" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.root.join("lib").mkpath
    box.root.join("lib/mixed.rb").binwrite("Dir['spec/**/*'] \xFF\xFE\n")
    box.commit("valid reference, invalid bytes")

    expect(Oubliette::Scanner.new(box.root, Oubliette::Manifest.build(box.root)).findings.map(&:file)).to include("lib/mixed.rb")
  end

  it "survives a genuinely binary file wearing a text extension" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.root.join("lib").mkpath
    box.root.join("lib/blob.json").binwrite((0..255).to_a.pack("C*"))
    box.commit("binary")

    expect { Oubliette::Scanner.new(box.root, Oubliette::Manifest.build(box.root)).findings }.not_to raise_error
  end
end
