# frozen_string_literal: true

require_relative "writer"

module Oubliette
  module Config
    # Points the `rspec` command at the relocated spec tree.
    class Rspec < Writer
      register :rspec

      DEFAULTS = "--require spec_helper\n--color\n--format progress\n"

      def filename = ".rspec"

      def render(current)
        path = destination("rspec-rails")
        return nil if path.nil?

        base = ManagedBlock.unwrap(current).to_s
        base = DEFAULTS if base.strip.empty?
        existing = base.lines.find { |line| line.strip.start_with?("--default-path") }

        block = ManagedBlock.wrap(
          reason: reason(path, existing),
          original: existing ? [ existing.strip ] : [],
          replacement: [ "--default-path #{path}" ]
        )

        existing ? base.sub(existing, block) : append(base, block)
      end
      private
        def reason(path, existing)
          [
            "the spec tree moved to #{path}, and rspec reads from a single default path.",
            existing ? "the `was:` line below is yours, commented out rather than deleted." :
                       "there was no default path here before, so nothing of yours was replaced.",
            "`rake oubliette:rollback` removes this block and leaves the rest of the file alone."
          ]
        end

        def append(base, block)
          base.empty? || base.end_with?("\n") ? base + block : "#{base}\n#{block}"
        end
    end
  end
end
