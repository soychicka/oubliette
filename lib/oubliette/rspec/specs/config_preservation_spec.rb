# frozen_string_literal: true

# The promise: oubliette changes only the lines it is responsible for, and a
# rollback puts those back without disturbing anything else -- including edits
# made after the migration, which an older design lost by restoring a snapshot
# taken before it.
RSpec.describe "config files survive being edited" do
  def full_box
    new_sandbox(
      gems: %w[rspec-rails cucumber-rails],
      packages: %w[jest],
      dirs: %w[spec/models features/support spec/javascript],
      files: {
        ".rspec" => "--require spec_helper\n--default-path spec\n--color\n",
        "cucumber.yml" => "default: -r features/support --strict features\nwip: --tags @wip features\n"
      }
    )
  end

  describe "a round trip with no edits at all" do
    it "leaves .rspec byte for byte as it was" do
      box = full_box
      before = box.read(".rspec")
      box.run
      box.runner.rollback

      expect(box.read(".rspec")).to eq(before)
    end

    it "leaves cucumber.yml byte for byte as it was" do
      box = full_box
      before = box.read("cucumber.yml")
      box.run
      box.runner.rollback

      expect(box.read("cucumber.yml")).to eq(before)
    end

    it "leaves package.json byte for byte as it was" do
      box = full_box
      before = box.read("package.json")
      box.run
      box.runner.rollback

      expect(box.read("package.json")).to eq(before)
    end
  end

  describe "an edit made after the migration" do
    it "keeps a line added to .rspec, and still restores the original" do
      box = full_box
      box.run
      box.write(".rspec", "#{box.read('.rspec')}--format documentation\n")
      box.commit("developer edits .rspec")
      box.runner.rollback

      contents = box.read(".rspec")
      expect(contents).to include("--format documentation")
      expect(contents).to include("--default-path spec")
      expect(contents).not_to include("test/rspec")
    end

    it "keeps a profile added to cucumber.yml" do
      box = full_box
      box.run
      box.write("cucumber.yml", "#{box.read('cucumber.yml')}smoke: --tags @smoke test/cucumber/features\n")
      box.commit("developer adds a profile")
      box.runner.rollback

      contents = box.read("cucumber.yml")
      expect(contents).to include("smoke: --tags @smoke")
      expect(contents).to include("default: -r features/support --strict features")
    end

    it "keeps a script added to package.json" do
      box = full_box
      box.run
      edited = JSON.parse(box.read("package.json"))
      edited["scripts"]["lint"] = "eslint app/javascript"
      box.write("package.json", "#{JSON.pretty_generate(edited)}\n")
      box.commit("developer adds a script")
      box.runner.rollback

      parsed = JSON.parse(box.read("package.json"))
      expect(parsed["scripts"]["lint"]).to eq("eslint app/javascript")
      expect(parsed["scripts"]["test"]).to eq("jest spec/javascript")
    end
  end

  describe "the annotation" do
    it "explains itself and keeps the original visible" do
      box = full_box
      box.run
      contents = box.read(".rspec")

      expect(contents).to include(">>> oubliette >>>")
      expect(contents).to include("the spec tree moved to test/rspec")
      expect(contents).to include("# was: --default-path spec")
      expect(contents).to include("rake oubliette:rollback")
    end

    it "says which line of cucumber.yml it replaced and why" do
      box = full_box
      box.run

      expect(box.read("cucumber.yml"))
        .to include("# was: default: -r features/support --strict features")
      expect(box.read("cucumber.yml")).to include("features/ moved to test/cucumber/features")
    end
  end

  describe "running twice" do
    it "adds no further blocks the second time" do
      box = full_box
      box.run
      first = { rspec: box.read(".rspec"), cucumber: box.read("cucumber.yml") }
      box.commit("migrated")
      box.run

      expect(box.read(".rspec")).to eq(first[:rspec])
      expect(box.read("cucumber.yml")).to eq(first[:cucumber])
    end

    it "opens and closes every block it writes" do
      box = full_box
      box.run

      [ ".rspec", "cucumber.yml" ].each do |file|
        contents = box.read(file)
        expect(contents.scan(">>> oubliette >>>").length)
          .to eq(contents.scan("<<< oubliette <<<").length), "unbalanced markers in #{file}"
      end
    end

    it "wraps each replaced line separately rather than one block inside another" do
      box = full_box
      box.run

      # cucumber.yml has two profiles naming features/, so two blocks is right.
      expect(box.read("cucumber.yml").scan(">>> oubliette >>>").length).to eq(2)
      expect(box.read(".rspec").scan(">>> oubliette >>>").length).to eq(1)
    end

    it "still restores cleanly after a retarget" do
      box = full_box
      before = box.read(".rspec")
      box.run
      box.write("migrate.yml", box.read("migrate.yml").sub("oubliette: test/rspec\n", "oubliette: test/examples\n"))
      box.run
      box.runner.rollback

      expect(box.read(".rspec")).to eq(before)
    end
  end
end
