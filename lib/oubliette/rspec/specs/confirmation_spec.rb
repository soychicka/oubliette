# frozen_string_literal: true

# The first run is the one that matters: it shows what it means to do, and waits
# to be told to do it. Every run after that already has a migrate.yml the
# developer has had the chance to read, so it just gets on with it.
RSpec.describe "the first run asks first" do
  def box
    @box ||= new_sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
  end

  describe "when the answer is yes" do
    it "moves everything and says so" do
      box.run(input: box.answering("y\n"))

      expect(box.log).to include("moving everything into place")
      expect(box).to be_exist("test/rspec/models")
    end

    it "accepts a full yes" do
      box.run(input: box.answering("yes\n"))

      expect(box).to be_exist("test/rspec/models")
    end
  end

  describe "when the answer is no" do
    before { box.run(input: box.answering("n\n")) }

    it "moves nothing" do
      expect(box).to be_exist("spec/models")
      expect(box).not_to be_exist("test/rspec")
    end

    it "leaves migrate.yml behind to be edited" do
      expect(box).to be_exist("migrate.yml")
    end

    it "says where the file is and what to do with it" do
      expect(box.log).to include("ok, we'll break here for now")
      expect(box.log).to include(box.root.join("migrate.yml").to_s)
      expect(box.log).to include("delete the entire entry for the gem")
      expect(box.log).to include("'oubliette' attribute")
      expect(box.log).to include("rake oubliette")
    end

    it "does not claim to have finished" do
      expect(box.log).not_to include("upside down")
    end

    it "proceeds without asking again on the next run" do
      box.run(input: box.answering("this is not a yes\n"))

      expect(box).to be_exist("test/rspec/models")
    end
  end

  describe "when the answer is neither" do
    it "treats an empty line as no, because nothing has moved yet" do
      box.run(input: box.answering("\n"))

      expect(box).to be_exist("spec/models")
      expect(box).not_to be_exist("test/rspec")
    end
  end

  it "shows the manifest before asking" do
    box.run(input: box.answering("n\n"))

    expect(box.log).to include("this is what oubliette proposes")
    expect(box.log).to include("origin: spec")
    expect(box.log).to include("oubliette: test/rspec")
  end

  it "does not ask when nothing is attached to a terminal" do
    box.run

    expect(box.log).to include("not a terminal")
    expect(box).to be_exist("test/rspec/models")
  end

  it "does not ask on a dry run, which was never going to move anything" do
    box.run(dry_run: true, input: box.answering("n\n"))

    expect(box.log).not_to include("do you want your test directories")
  end
end

RSpec.describe "the closing word" do
  it "is said once the directories have moved" do
    box = new_sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run

    expect(box.log).to include("I have turned the test suite upside down, and I have done it all for you.")
  end

  it "points at the two files that explain what happened" do
    box = new_sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run

    expect(box.log).to include(box.root.join("migrate.yml").to_s)
    expect(box.log).to include(box.root.join("rollback.yml").to_s)
    expect(box.log).to include("rake oubliette:rollback")
  end

  it "points at the notes left for configs oubliette will not rewrite" do
    box = new_sandbox(packages: %w[cypress], dirs: %w[cypress],
                      files: { "cypress.config.js" => "module.exports = {};\n" })
    box.run

    expect(box.log).to include("cypress.config.js.oubliette.md")
  end

  it "stays quiet on a run that had nothing to do" do
    box = new_sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run
    box.commit("migrated")
    before = box.log.length
    box.run

    expect(box.log[before..]).not_to include("upside down")
  end
end
