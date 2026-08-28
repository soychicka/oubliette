# frozen_string_literal: true

RSpec.describe Oubliette::Mover do
  let(:box) { sandbox(gems: %w[rspec-rails], dirs: %w[spec/models]) }
  let(:mover) { described_class.new(box.root) }

  it "moves a directory and leaves nothing behind" do
    mover.relocate("spec", "test/rspec")

    expect(box).to be_exist("test/rspec/models")
    expect(box).not_to be_exist("spec")
  end

  it "merges into a destination that already holds files" do
    box.touch("spec/factories/users.rb")
    box.touch("test/factories/posts.rb")
    mover.relocate("spec/factories", "test/data/factories")
    mover.relocate("test/factories", "test/data/factories")

    expect(box).to be_exist("test/data/factories/users.rb")
    expect(box).to be_exist("test/data/factories/posts.rb")
  end

  it "refuses to overwrite a file it would collide with" do
    box.write("spec/factories/users.rb", "one")
    box.write("test/data/factories/users.rb", "two")

    expect { mover.relocate("spec/factories", "test/data/factories") }
      .to raise_error(Oubliette::Error, /refusing to overwrite/)
    expect(box.read("test/data/factories/users.rb")).to eq("two")
  end

  it "writes nothing on a dry run" do
    described_class.new(box.root, dry_run: true, logger: ->(_) { }).relocate("spec", "test/rspec")

    expect(box).to be_exist("spec/models")
    expect(box).not_to be_exist("test/rspec")
  end

  it "sees a dirty working tree" do
    expect(mover).to be_clean
    box.touch("spec/models/user_spec.rb")

    expect(mover).not_to be_clean
  end
end
