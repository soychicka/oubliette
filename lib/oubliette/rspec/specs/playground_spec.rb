# frozen_string_literal: true

RSpec.describe Oubliette::Playground do
  # The script itself does `rails new`, `bundle install` and npm, which is not
  # something a unit spec should ever set off. What is under test here is the
  # front door: where it decides to build, and what it refuses to delete.
  def playground_for(box, target: nil, input: StringIO.new, script: true)
    described_class.new(box.root, target: target, out: box.output, input: input).tap do |playground|
      allow(playground).to receive(:system).and_return(script)
    end
  end

  it "suggests a sibling of the project, never a directory inside it" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    playground_for(box, input: box.answering("\n")).call

    expect(box.log).to include(box.root.parent.join("oubliette-playground").to_s)
    expect(box.log).not_to include(box.root.join("oubliette-playground").to_s)
  end

  it "builds where you tell it to" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    playground = playground_for(box, target: box.root.join("fresh").to_s)

    expect(playground.call).to eq(:built)
    expect(playground).to have_received(:system).with(described_class.script.to_s, box.root.join("fresh").to_s)
  end

  it "will not overwrite an existing directory without the whole word" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    target = box.root.join("elsewhere")
    target.mkpath
    playground = playground_for(box, target: target.to_s, input: box.answering("y\n"))

    expect(playground.call).to eq(:declined)
    expect(playground).not_to have_received(:system)
  end

  it "accepts YES in any case" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    target = box.root.join("elsewhere")
    target.mkpath

    expect(playground_for(box, target: target.to_s, input: box.answering("Yes\n")).call).to eq(:built)
  end

  it "refuses to delete anything when nobody is there to answer" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    target = box.root.join("elsewhere")
    target.mkpath

    expect(playground_for(box, target: target.to_s).call).to eq(:declined)
    expect(box.log).to include("Remove it yourself")
  end

  it "says where the half-built application was left when the script fails" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])

    expect(playground_for(box, target: box.root.join("fresh").to_s, script: false).call).to eq(:failed)
    expect(box.log).to include("did not finish")
  end
end
