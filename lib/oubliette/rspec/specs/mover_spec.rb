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

RSpec.describe "#{Oubliette::Mover} merging placeholders" do
  it "drops a duplicate git placeholder rather than refusing the merge" do
    box = sandbox(gems: %w[factory_bot_rails], dirs: %w[spec/factories test/factories])
    box.run

    expect(box).to be_exist("test/data/factories/.keep")
    expect(box).not_to be_exist("spec/factories")
    expect(box).not_to be_exist("test/factories")
  end

  it "still refuses when both files have content" do
    box = sandbox(gems: %w[factory_bot_rails], dirs: [])
    box.write("spec/factories/users.rb", "one")
    box.write("test/factories/users.rb", "two")
    box.commit("two factories")

    # Caught before anything moves now, rather than partway through the merge.
    expect { box.run }.to raise_error(Oubliette::Error, %r{test/data/factories/users\.rb})
    expect(box.read("test/factories/users.rb")).to eq("two")
    expect(box.read("spec/factories/users.rb")).to eq("one")
  end
end

RSpec.describe "#{Oubliette::Runner} refusing a partial migration" do
  # spec/factories and test/factories both land in test/data/factories, so a
  # file named the same in each is a genuine collision.
  def colliding
    box = new_sandbox(gems: %w[rspec-rails factory_bot_rails], dirs: %w[spec/models])
    box.write("spec/factories/users.rb", "one")
    box.write("test/factories/users.rb", "two")
    box.commit("two factories of the same name")
    box
  end

  it "moves nothing at all when any destination file would be overwritten" do
    box = colliding

    expect { box.run }.to raise_error(Oubliette::Error, %r{test/data/factories/users\.rb})
    expect(box).to be_exist("spec/models")
    expect(box).to be_exist("spec/factories/users.rb")
    expect(box).not_to be_exist("test/rspec")
    expect(box).not_to be_exist("test/data/factories")
  end

  it "names every colliding file, not just the first" do
    box = new_sandbox(gems: %w[rspec-rails factory_bot_rails], dirs: %w[spec/models])
    box.write("spec/factories/users.rb", "one")
    box.write("spec/factories/posts.rb", "one")
    box.write("test/factories/users.rb", "two")
    box.write("test/factories/posts.rb", "two")
    box.commit("collisions")

    expect { box.run }.to raise_error(Oubliette::Error, /users\.rb.*posts\.rb|posts\.rb.*users\.rb/m)
  end
end
