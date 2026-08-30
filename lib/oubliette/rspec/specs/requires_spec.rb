# frozen_string_literal: true

RSpec.describe Oubliette::Requires do
  it "deepens a require that pointed out of the directory being moved" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.write("spec/rails_helper.rb", %(require_relative "../config/environment"\n))
    box.commit("helper")
    box.run

    expect(box.read("test/rspec/rails_helper.rb")).to eq(%(require_relative "../../config/environment"\n))
  end

  it "leaves a require that travelled along with the directory alone" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.write("spec/models/user_spec.rb", %(require_relative "../rails_helper"\n))
    box.write("spec/rails_helper.rb", "")
    box.commit("helper")
    box.run

    expect(box.read("test/rspec/models/user_spec.rb")).to eq(%(require_relative "../rails_helper"\n))
  end

  it "shallows a require when the directory moves closer to the root" do
    box = sandbox(gems: %w[cucumber-rails], dirs: %w[features])
    box.write("features/support/env.rb", %(require_relative "../../config/environment"\n))
    box.commit("env")
    box.run
    box.runner.rollback

    expect(box.read("features/support/env.rb")).to eq(%(require_relative "../../config/environment"\n))
  end

  it "ignores an interpolated require it cannot resolve" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.write("spec/rails_helper.rb", %(require_relative "#{'#{dir}'}/thing"\n))
    box.commit("helper")
    box.run

    expect(box.read("test/rspec/rails_helper.rb")).to include('#{dir}/thing')
  end
end

RSpec.describe "a file oubliette cannot decode" do
  it "does not take the migration down partway through" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    box.root.join("spec/models/binary_spec.rb").binwrite("# \xFF\xFE not utf-8\n")
    box.commit("invalid bytes inside a moved directory")

    expect { box.run }.not_to raise_error
    expect(box).to be_exist("test/rspec/models/binary_spec.rb")
  end

  it "still rewrites the requires in its neighbours" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec])
    box.root.join("spec/binary_spec.rb").binwrite("# \xFF\xFE\n")
    box.write("spec/rails_helper.rb", %(require_relative "../config/environment"\n))
    box.commit("one of each")
    box.run

    expect(box.read("test/rspec/rails_helper.rb")).to include(%(require_relative "../../config/environment"))
  end

  it "explains a mid-migration failure instead of letting it reach rake raw" do
    box = sandbox(gems: %w[rspec-rails], dirs: %w[spec/models])
    allow_any_instance_of(Oubliette::Mover).to receive(:relocate).and_raise(RuntimeError, "disk went away")

    expect { box.run }.to raise_error(Oubliette::Error, /rollback/)
  end
end
