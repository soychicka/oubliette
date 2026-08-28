# frozen_string_literal: true

require "rails/railtie"

module Oubliette
  # Loads the rake tasks and, in the test environment, points the already-booted
  # test libraries at their relocated directories.
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("tasks.rake", __dir__)
    end

    initializer "oubliette.runtime" do
      ActiveSupport.on_load(:active_support_test_case) do
        Oubliette::Runtime.apply!(root: Rails.root, strict: false)
      end
    end

    config.after_initialize do
      Oubliette.root = Rails.root
    end
  end
end
