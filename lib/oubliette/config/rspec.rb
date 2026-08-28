# frozen_string_literal: true

require_relative "writer"

module Oubliette
  module Config
    # Points the `rspec` command at the relocated spec tree.
    #
    # .rspec cannot carry comments -- RSpec splits the file on whitespace and
    # feeds every token to its option parser -- so the file is regenerated from
    # the pre-oubliette original each time rather than annotated in place.
    class Rspec < Writer
      register :rspec

      def filename = ".rspec"

      def render
        path = destination("rspec-rails")
        return nil if path.nil?

        options = source_options.reject { |option| option.start_with?("--default-path") }
        (options + [ "--default-path #{path}" ]).join("\n") + "\n"
      end
      private
        def source_options
          source = backup_path.file? ? backup_path : @root.join(filename)
          return default_options unless source.file?
          return default_options if source.read.strip == Writer::ABSENT

          source.read.lines.map(&:strip).reject(&:empty?)
        end

        def default_options
          [ "--require spec_helper", "--color", "--format progress" ]
        end
    end
  end
end
