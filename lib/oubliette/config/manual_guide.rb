# frozen_string_literal: true

require_relative "writer"
require_relative "../text"

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

        if Oubliette.read(target) == render(nil)
          @log.call(Text.t("guide.removed", file: filename))
          remove
          :restored
        else
          @log.call(Text.t("guide.kept", file: filename))
          :unchanged
        end
      end

      def render(_current)
        Text.t("manual_guide.document",
               gem: @entry.gem, file: @entry.file, moves: moves.join("\n"),
               settings: settings_sentence, example: example)
      end
      private
        def moves
          @entry.pairs.map do |pair|
            Text.t("manual_guide.move", origin: pair.origin, oubliette: pair.oubliette)
          end
        end

        def settings_sentence
          return Text.t("manual_guide.settings_unknown") if @entry.settings.empty?

          names = @entry.settings.map { |setting| "`#{setting}`" }.join(" and ")
          return Text.t("manual_guide.settings_one", names: names) if @entry.settings.one?

          Text.t("manual_guide.settings_many", names: names)
        end

        def example
          pair = @entry.pairs.first
          setting = @entry.settings.first || "specPattern"

          Text.t("manual_guide.example",
                 before: nested(setting, "#{pair.origin}/**/*"),
                 after: nested(setting, "#{pair.oubliette}/**/*")).rstrip
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
