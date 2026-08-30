# frozen_string_literal: true

require_relative "writer"

module Oubliette
  module Config
    # Leaves a note beside a config file oubliette will not rewrite.
    #
    # Vitest, Playwright, Cypress and Karma keep their paths inside a javascript
    # module, and there is no round trip through executable code that cannot
    # corrupt it. Rather than guess, oubliette moves the directories and writes
    # the developer a short set of instructions next to the file that needs
    # changing, naming the setting and the exact before and after.
    #
    # The note is a config file like any other as far as the writer is
    # concerned, which means rollback removes it without any special handling.
    class ManualGuide < Writer
      attr_reader :entry

      def initialize(root, manifest, entry:, **options)
        super(root, manifest, **options)
        @entry = entry
      end

      # Written under oubliette's own directory rather than beside the config
      # it describes: the point of the gem is that test paraphernalia lives in
      # one place. The run names the path in its report and again when it
      # finishes, so it is not left to be stumbled upon.
      def filename = "#{HOME}/#{@entry.file.tr('/', '-')}.md"

      # The whole file is oubliette's, so a rollback removes it outright --
      # but only while it still says exactly what oubliette wrote. A guide is
      # the natural place to jot down what you worked out while following it,
      # and those notes are the developer's, not oubliette's, so an edited
      # guide is left where it is and named in the report instead.
      def revert
        target = @root.join(filename)
        return :unchanged unless target.file?

        if target.read == render(nil)
          @log.call("  #{filename}: removed, the config it describes was never touched")
          remove
          :restored
        else
          @log.call("  #{filename}: kept, you have edited it")
          :unchanged
        end
      end

      def render(_current)
        <<~MARKDOWN
          # #{@entry.gem}: update `#{@entry.file}` by hand

          Oubliette moved these directories:

          #{moves.join("\n")}

          `#{@entry.file}` is javascript rather than JSON, so oubliette does not
          rewrite it: there is no safe round trip through executable code, and a
          bad substitution in a config file is worse than no substitution at all.

          #{settings_sentence}

          #{example}

          Once the config points at the new location, delete this file. It is also
          removed by `rake oubliette:rollback`, which puts the directories back.
        MARKDOWN
      end
      private
        def moves
          @entry.pairs.map { |pair| "    #{pair.origin} -> #{pair.oubliette}" }
        end

        def settings_sentence
          return "Point its spec paths at the new location." if @entry.settings.empty?

          names = @entry.settings.map { |setting| "`#{setting}`" }
          "Update #{names.join(' and ')} so #{@entry.settings.one? ? 'it points' : 'they point'} at the new location."
        end

        def example
          pair = @entry.pairs.first
          setting = @entry.settings.first || "specPattern"

          <<~TEXT.rstrip
            ```js
            // before
            #{nested(setting, "#{pair.origin}/**/*")}

            // after
            #{nested(setting, "#{pair.oubliette}/**/*")}
            ```
          TEXT
        end

        # e2e.specPattern is how the setting is described, not how it is
        # written. Nest it back into the object literal it really lives in, so
        # what the note shows can be pasted into the config.
        def nested(setting, value)
          setting.split(".").reverse.each_with_index.reduce(nil) do |inner, (key, index)|
            index.zero? ? %(#{key}: "#{value}") : "#{key}: { #{inner} }"
          end
        end
    end
  end
end
