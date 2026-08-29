# frozen_string_literal: true

require_relative "writer"

module Oubliette
  module Config
    # Frees cucumber-rails from counting directories.
    #
    # cucumber/rails.rb works out the application root by going two levels up
    # from whichever env.rb required it, which is correct only while the
    # features tree sits directly under the project root.
    class CucumberEnv < Writer
      register :cucumber_env

      def filename
        destination = destination("cucumber-rails")
        destination && "#{destination}/support/env.rb"
      end

      def render(current)
        return nil if current.nil?

        base = ManagedBlock.unwrap(current).to_s
        path = destination("cucumber-rails")
        return base if path.nil? || path == "features"

        shim + base
      end
      private
        def shim
          ManagedBlock.wrap(
            reason: [ "cucumber-rails infers the application root from this file's depth,",
                      "which moving features/ changed. Nothing below this block was touched." ],
            replacement: [
              'ENV["RAILS_ROOT"] ||= begin',
              "  dir = __dir__",
              '  dir = File.dirname(dir) until File.file?(File.join(dir, "config", "environment.rb")) || dir == "/"',
              "  dir",
              "end",
              ""
            ]
          )
        end
    end
  end
end
