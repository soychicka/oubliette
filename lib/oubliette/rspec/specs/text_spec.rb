# frozen_string_literal: true

RSpec.describe Oubliette::Text do
  it "interpolates named placeholders" do
    expect(described_class.t("uninstall.removed", items: "a, b"))
      .to eq("removed automatically: a, b")
  end

  it "raises rather than printing a blank where a string should be" do
    expect { described_class.t("uninstall.no_such_key") }
      .to raise_error(described_class::Missing, /no_such_key/)
  end

  it "raises when a placeholder has no value, rather than printing the placeholder" do
    expect { described_class.t("uninstall.removed") }.to raise_error(KeyError)
  end

  it "does not treat a group of keys as a string" do
    expect { described_class.t("uninstall.reasons") }.to raise_error(described_class::Missing)
  end
end

# The two directions that keep the locale file and the code honest. Without
# these, a reworded key silently breaks a message, and a message deleted from
# the code leaves a string nobody will ever see sitting in the file looking
# maintained.
RSpec.describe "#{Oubliette::Text} and the code that calls it" do
  ROOT = Pathname.new(File.expand_path("../../..", __dir__))

  def sources
    ROOT.glob("oubliette/**/*.{rb,rake}").reject { |path| path.to_s.include?("/rspec/") }
  end

  # Comment lines are stripped first: the module documents itself with an
  # example call, and a doc example is not a call site.
  def used_keys
    sources.flat_map do |path|
      code = path.read.lines.reject { |line| line.strip.start_with?("#") }.join
      code.scan(/Text\.(?:t|group)\(\s*["']([\w.]+)["']/).flatten
    end.uniq
  end

  def defined_keys(node = YAML.safe_load_file(Oubliette::Text::DIRECTORY + "/en.yml"), prefix = [])
    node.flat_map do |key, value|
      here = prefix + [ key ]
      value.is_a?(Hash) ? defined_keys(value, here) : [ here.join(".") ]
    end
  end

  it "defines every key the code asks for" do
    # `defined_keys` lists leaves, so a group key is satisfied by the leaves
    # beneath it rather than by itself.
    undefined = used_keys.reject do |used|
      defined_keys.any? { |key| key == used || key.start_with?("#{used}.") }
    end

    expect(undefined).to be_empty
  end

  it "uses every key it defines" do
    # A group key covers everything beneath it: `Text.group("reporter.status")`
    # is what uses `reporter.status.pending`.
    unused = defined_keys.reject do |key|
      used_keys.any? { |used| used == key || key.start_with?("#{used}.") }
    end

    expect(unused).to be_empty
  end
end

RSpec.describe "#{Oubliette::Text} in a packaged gem" do
  # The locale file is data, and the gemspec lists files by extension. Every
  # string in the gem became unreachable the moment the text moved out of the
  # .rb files, and nothing in the suite would have noticed: the specs run from
  # the working tree, where the file is simply there.
  it "packages the locale files it loads at runtime" do
    gemspec = Pathname.new(File.expand_path("../../../..", __dir__)).join("oubliette.gemspec")
    packaged = Gem::Specification.load(gemspec.to_s).files

    locales = Dir.children(Oubliette::Text::DIRECTORY).map { |name| "lib/oubliette/locales/#{name}" }

    expect(locales).not_to be_empty
    expect(locales - packaged).to be_empty
  end
end
