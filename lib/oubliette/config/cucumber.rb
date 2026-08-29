# frozen_string_literal: true

require_relative "writer"

module Oubliette
  module Config
    # Rewrites the feature paths inside cucumber.yml.
    #
    # The file is usually hand-tuned ERB with profiles the project cares about,
    # so only the lines that name the features directory are touched, and each
    # of those keeps its original above it, commented out.
    class Cucumber < Writer
      register :cucumber

      CANDIDATES = %w[cucumber.yml config/cucumber.yml .config/cucumber.yml].freeze

      # cucumber-rails puts its config in config/cucumber.yml while a plain
      # cucumber project keeps it at the root, and cucumber reads whichever it
      # finds first. Rewriting the wrong one would leave the real config
      # pointing at directories that are no longer there.
      def filename
        CANDIDATES.find { |candidate| @root.join(candidate).file? } || CANDIDATES.first
      end

      def render(current)
        path = destination("cucumber-rails")
        return nil if path.nil?

        base = ManagedBlock.unwrap(current).to_s
        return generated(path) if base.strip.empty?

        base.lines.map { |line| rewrite(line, path) }.join
      end
      private
        def rewrite(line, path)
          updated = require_paths(substitute(line, path), path)
          return line if updated == line

          ManagedBlock.wrap(
            reason: [ "features/ moved to #{path}; the line below is yours, commented out." ],
            original: [ line.chomp ],
            replacement: [ updated.chomp ]
          )
        end

        def substitute(line, path)
          line.gsub(%r{(?<![\w/.-])features(?=[\s/'"]|$)}, path)
        end

        # Cucumber only auto-requires the ruby files beside a feature tree when
        # that tree sits where it expects. An explicit -r costs nothing when the
        # autoload would have worked, and is the difference between a suite and
        # a page of undefined steps when it would not.
        def require_paths(line, path)
          return line unless line.include?(path)
          return line if line.include?("-r ")

          line.sub(/^(\w[\w-]*):[ \t]*(?=\S)/) { "#{Regexp.last_match(0)}-r #{path} " }
        end

        def generated(path)
          ManagedBlock.wrap(
            reason: [ "this file did not exist; oubliette wrote it so `cucumber` finds #{path}.",
                      "`rake oubliette:rollback` deletes it again." ],
            replacement: [
              "default: --format progress --strict -r #{path}/support -r #{path}/step_definitions #{path}",
              "wip: --tags @wip:3 --wip #{path}"
            ]
          )
        end
    end
  end
end
