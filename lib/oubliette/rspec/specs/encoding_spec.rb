# frozen_string_literal: true

# A project is allowed a non-ASCII character in its Gemfile, its package.json or
# a config file: an author's name, an accented comment, a feature written in
# French. Ruby tags a file read without an explicit encoding with
# Encoding.default_external, and that is US-ASCII wherever the environment does
# not say otherwise -- a bare `docker exec`, cron, launchd, a CI image with no
# locale. The read itself succeeds and hands back a string whose bytes are a lie
# about its encoding; the regex or JSON parse that follows is what raises.
#
# Every example here fails on an ASCII-tagged read, so this file is the only
# place that needs to know why the reads are explicit.
RSpec.describe "reading project files in an environment with no declared encoding" do
  around do |example|
    was = Encoding.default_external
    silently { Encoding.default_external = Encoding::US_ASCII }
    example.run
  ensure
    silently { Encoding.default_external = was }
  end

  # Ruby warns on every assignment to default_external, and a warning per
  # example would bury anything worth reading.
  def silently
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end

  let(:accent) { "café" }

  it "detects frameworks named in a Gemfile that has an accented comment" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.write("Gemfile", "# written at a #{accent}\n#{box.read('Gemfile')}")

    keys = Oubliette::Detector.new(box.root).detections.map(&:key)

    expect(keys).to include("rspec-rails")
  end

  it "reads a package.json with an accented author" do
    box = sandbox(packages: %w[jest], dirs: %w[spec/javascript])
    package = JSON.parse(box.read("package.json")).merge("author" => "Ren#{accent}e")
    box.write("package.json", JSON.pretty_generate(package))

    expect(Oubliette::Detector.new(box.root).detections.map(&:key)).to include("jest")
    expect(Oubliette::Suites.javascript(box.root).map(&:key)).to eq([ "javascript" ])
  end

  it "rewrites a config file with an accented comment, and keeps the accent" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec],
                  files: { ".rspec" => "# run it at the #{accent}\n--color\n" })
    manifest = Oubliette::Manifest.build(box.root).tap(&:save!)

    Oubliette::Config::Rspec.new(box.root, manifest, logger: ->(_line) { }).apply

    expect(box.read(".rspec")).to include(accent, "--default-path test/rspec")
  end

  it "loads a migrate.yml carrying an accented comment" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    Oubliette::Manifest.build(box.root).save!
    path = box.root.join(Oubliette::Manifest::PATH)
    path.write("# the #{accent} note\n#{path.read(encoding: 'UTF-8')}")

    expect(Oubliette::Manifest.load(box.root).location("rspec-rails")).to eq("test/rspec")
  end
end

# The fix above is only a fix while it stays everywhere. One bare `.read` added
# later puts the crash back, in whichever code path happens to carry it, and the
# suite would not notice because the suite runs under a declared locale.
RSpec.describe "the gem's own source" do
  let(:lib) { Pathname.new(File.expand_path("../../..", __dir__)) }

  let(:sources) do
    Pathname.glob(lib.join("**/*.rb")).reject { |file| file.to_s.include?("/rspec/specs/") }
  end

  it "reads no file without saying what the bytes are" do
    bare = sources.flat_map do |file|
      Oubliette.read(file).lines.each_with_index.filter_map do |line, index|
        next unless line.match?(/(?<!Oubliette)\.read\b|\breadlines\b/)
        next if line.match?(/encoding:|def read\b/)

        "#{file.relative_path_from(lib)}:#{index + 1}"
      end
    end

    expect(bare).to be_empty
  end
end
