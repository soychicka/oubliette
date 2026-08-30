# frozen_string_literal: true

RSpec.describe Oubliette::Repair do
  def box_with_reference
    box = new_sandbox(gems: %w[rspec-rails], dirs: %w[spec/models spec/support])
    box.write("spec/rails_helper.rb", %(Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }\n))
    box.write("app/notes.rb", "# see spec/support/ for the old layout\n")
    box.commit("a real reference and a comment")
    box
  end

  # The first answer is for the migration prompt, the second for this one.
  describe "what it offers" do
    it "shows the line and what it would become" do
      box = box_with_reference
      box.run

      expect(box.log).to include("Dir[Rails.root.join('spec/support/**/*.rb')]")
      expect(box.log).to include("->  Dir[Rails.root.join('test/rspec/support/**/*.rb')]")
    end

    it "leaves comment matches alone and says why" do
      box = box_with_reference
      box.run

      expect(box.log).to include("1 more mention an old path inside a comment")
      expect(box.log).to include("not a statement about your layout")
    end

    it "offers the two ways to proceed" do
      box = box_with_reference
      box.run(input: box.answering("y\n1\n"))

      expect(box.log).to include("--OR--")
      expect(box.log).to include("[ 1: manual | 2: easy - <default> ]")
    end

    it "does not ask when nothing is attached to a terminal" do
      box = box_with_reference
      box.run

      expect(box.log).not_to include("how do you want to roll")
    end
  end

  describe "choosing manual" do
    it "changes nothing" do
      box = box_with_reference
      before = box.read("spec/rails_helper.rb")
      box.run(input: box.answering("y\n1\n"))

      expect(box.read("test/rspec/rails_helper.rb")).to eq(before)
      expect(box).not_to be_exist("test/rspec/rails_helper.rb.bak")
    end
  end

  describe "choosing easy" do
    def repaired
      @repaired ||= begin
        box = box_with_reference
        box.run(input: box.answering("y\n\n"))
        box
      end
    end

    it "updates the line" do
      expect(repaired.read("test/rspec/rails_helper.rb"))
        .to include("Dir[Rails.root.join('test/rspec/support/**/*.rb')]")
    end

    it "keeps the original as a comment" do
      expect(repaired.read("test/rspec/rails_helper.rb"))
        .to include("# was: Dir[Rails.root.join('spec/support/**/*.rb')]")
    end

    it "leaves a backup beside the file" do
      expect(repaired).to be_exist("test/rspec/rails_helper.rb.bak")
      expect(repaired.read("test/rspec/rails_helper.rb.bak"))
        .to eq("Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }\n")
    end

    it "does not touch the comment it declined to change" do
      expect(repaired.read("app/notes.rb")).to eq("# see spec/support/ for the old layout\n")
    end

    it "says how many files it changed" do
      expect(repaired.log).to include("updated 1 file, originals kept as comments")
    end

    it "runs the suites afterwards" do
      expect(repaired.log).to include("no test suites found here").or include("-----")
    end
  end
end
