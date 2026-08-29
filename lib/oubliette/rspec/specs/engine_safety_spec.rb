# frozen_string_literal: true

# A project's own test directories are oubliette's business. The ones inside an
# installed or vendored engine are not: moving them, or rewriting the paths that
# reach them, would break a gem the project does not own.
RSpec.describe "engine and gem safety" do
  def vendored_engine
    box = new_sandbox(gems: %w[rspec-rails cucumber-rails], dirs: %w[spec/models features/support])
    box.write("vendor/gems/widgetry/spec/widgetry_spec.rb", "RSpec.describe(Widgetry) { it { } }\n")
    box.write("vendor/gems/widgetry/features/admin.feature", "Feature: admin\n")
    box.write("vendor/gems/widgetry/app/assets/javascripts/widgetry.js", "console.log('widgetry');\n")
    box.write("vendor/gems/widgetry/test/fixtures/widgets.yml", "one:\n  name: one\n")
    box.commit("vendored engine")
    box
  end

  it "leaves a vendored engine's test directories exactly where they are" do
    box = vendored_engine
    box.run

    expect(box).to be_exist("vendor/gems/widgetry/spec/widgetry_spec.rb")
    expect(box).to be_exist("vendor/gems/widgetry/features/admin.feature")
    expect(box).to be_exist("vendor/gems/widgetry/test/fixtures/widgets.yml")
  end

  it "leaves a vendored engine's assets alone" do
    box = vendored_engine
    before = box.read("vendor/gems/widgetry/app/assets/javascripts/widgetry.js")
    box.run

    expect(box.read("vendor/gems/widgetry/app/assets/javascripts/widgetry.js")).to eq(before)
  end

  it "never names an engine directory in the plan" do
    box = vendored_engine
    box.run

    expect(box.manifest.pairs.map(&:origin)).to all(satisfy { |path| !path.start_with?("vendor/") })
  end

  it "does not report references that live inside an engine" do
    box = vendored_engine
    box.write("vendor/gems/widgetry/lib/widgetry.rb", "Dir['spec/**/*_spec.rb']\n")
    box.commit("engine reference")
    box.run

    expect(Oubliette::Scanner.new(box.root, box.manifest).findings.map(&:file))
      .to all(satisfy { |file| !file.start_with?("vendor/") })
  end

  it "does not offer an engine's directories as strays" do
    box = vendored_engine
    manifest = Oubliette::Manifest.build(box.root)

    expect(manifest.data["strays"].keys).not_to include("vendor", "widgetry")
  end

  it "leaves an app file that points at an engine asset untouched" do
    box = vendored_engine
    manifest = "//= link administrate/application.js\n//= link widgetry.js\n"
    box.write("app/assets/config/manifest.js", manifest)
    box.commit("asset manifest")
    box.run

    expect(box.read("app/assets/config/manifest.js")).to eq(manifest)
  end
end
