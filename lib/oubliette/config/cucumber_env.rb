# frozen_string_literal: true

require_relative "writer"

module Oubliette
  module Config
    # Frees cucumber-rails from counting directories.
    #
    # cucumber/rails.rb works out the application root by going two levels up
    # from whichever env.rb required it, which is correct only while the
    # features tree sits directly under the project root. Moving it anywhere
    # else makes cucumber-rails look for config/environment in the wrong place,
    # so env.rb is given a line that finds the root by looking for it.
    class CucumberEnv < Writer
      register :cucumber_env

      MARKER = "# oubliette: pin the application root"

      def filename
        destination = destination("cucumber-rails")
        destination && "#{destination}/support/env.rb"
      end

      def render
        source = original
        return nil if source.nil?
        return source if source.include?(MARKER)
        return source if destination("cucumber-rails") == "features"

        shim + source
      end
      private
        def shim
          <<~RUBY
            #{MARKER} -- cucumber-rails otherwise infers it from this file's depth.
            ENV["RAILS_ROOT"] ||= begin
              dir = __dir__
              dir = File.dirname(dir) until File.file?(File.join(dir, "config", "environment.rb")) || dir == "/"
              dir
            end

          RUBY
        end

        def original
          name = filename
          return nil if name.nil?

          source = backup_path.file? ? backup_path : @root.join(name)
          return nil unless source.file?

          contents = source.read
          contents == Writer::ABSENT ? nil : contents
        end
    end
  end
end
