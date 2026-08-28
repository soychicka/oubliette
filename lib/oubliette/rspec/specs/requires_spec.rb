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
