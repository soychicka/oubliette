# frozen_string_literal: true

# Two ways to leave a framework alone, and both have to survive a rerun --
# otherwise oubliette quietly puts back what the developer took out.
RSpec.describe "excluding a framework" do
  def two_frameworks
    box = new_sandbox(gems: %w[rspec-rails cucumber-rails], dirs: %w[spec/models features/support])
    box.run(input: box.answering("n\n"))
    box
  end

  def delete_entry(box, key)
    path = box.root.join(Oubliette::Manifest::PATH)
    path.write(path.read.sub(/  #{Regexp.escape(key)}:\n(?:    .*\n|      .*\n)*/, ""))
    box.commit("deleted #{key}")
  end

  def disable_entry(box, key)
    path = box.root.join(Oubliette::Manifest::PATH)
    yaml = path.read
    index = yaml.index("  #{key}:")
    path.write(yaml[0...index] + yaml[index..].sub("enabled: true", "enabled: false"))
    box.commit("disabled #{key}")
  end

  describe "by deleting the entry" do
    it "leaves that framework where it is" do
      box = two_frameworks
      delete_entry(box, "cucumber-rails")
      box.run

      expect(box).to be_exist("features/support")
      expect(box).not_to be_exist("test/cucumber/features")
    end

    it "still migrates everything else" do
      box = two_frameworks
      delete_entry(box, "cucumber-rails")
      box.run

      expect(box).to be_exist("test/rspec/models")
    end

    it "does not put the entry back" do
      box = two_frameworks
      delete_entry(box, "cucumber-rails")
      box.run

      expect(box.read(Oubliette::Manifest::PATH)).not_to include("cucumber-rails")
    end

    it "stays deleted across several runs" do
      box = two_frameworks
      delete_entry(box, "cucumber-rails")
      3.times do
        box.run
        box.commit("ran")
      end

      expect(box).to be_exist("features/support")
    end

    it "comes back on reset, which is the way to change your mind" do
      box = two_frameworks
      delete_entry(box, "cucumber-rails")
      box.run
      box.commit("migrated without cucumber")
      box.runner.reset

      expect(box.read(Oubliette::Manifest::PATH)).to include("cucumber-rails")
      expect(box).to be_exist("test/cucumber/features")
    end
  end

  describe "by setting enabled: false" do
    it "leaves that framework where it is" do
      box = two_frameworks
      disable_entry(box, "cucumber-rails")
      box.run

      expect(box).to be_exist("features/support")
      expect(box).not_to be_exist("test/cucumber/features")
    end

    it "keeps the entry, so it is a decision you can see and undo" do
      box = two_frameworks
      disable_entry(box, "cucumber-rails")
      box.run

      expect(box.read(Oubliette::Manifest::PATH)).to include("cucumber-rails")
      expect(box.read(Oubliette::Manifest::PATH)).to include("enabled: false")
    end
  end

  it "does not mistake a framework it has never seen for one that was deleted" do
    box = new_sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.run

    box.write("Gemfile", "#{box.read('Gemfile')}gem 'cucumber-rails'\n")
    box.write("features/support/env.rb", "")
    box.commit("cucumber arrives later")
    box.run

    expect(box).to be_exist("test/cucumber/features/support")
  end
end
