# frozen_string_literal: true

require_relative "../catalog"
require_relative "../paper"
require_relative "../version"

module Oubliette
  class Paper
    # Explains this directory to whoever opens it next, which is very often not
    # the person who ran the migration.
    #
    # The one thing it has to be honest about is where oubliette stops. Four
    # javascript frameworks keep their paths inside a module rather than in
    # JSON, and are moved but not configured -- if that is only discovered when
    # a suite comes up empty, the tool has cost more than it saved.
    class Readme < Paper
      FILENAME = "#{HOME}/README.md"

      def filename = FILENAME

      def render
        <<~MARKDOWN
          # This directory belongs to oubliette

          Your test suites live under `test/` now. Every framework in the list below
          was moved here, and its configuration was rewritten to match, so the usual
          commands -- `rspec`, `rails test`, `cucumber`, `npm test` -- work unchanged.

          Oubliette wrote this file and rewrites it on every run. Notes you add here
          will be lost; put them somewhere oubliette does not own.

          #{Notice::RULE}

          ## Moved and configured for you

          #{automatic}

          #{Notice::RULE}

          ## Moved, but you have to finish the configuration

          #{manual_section}

          #{Notice::RULE}

          ## Getting out

          `RECOVERY.md`, next to this file, lists where every directory came from and
          how to put it back -- by hand, with no gem installed, if it comes to that.
          With the gem installed, `rake oubliette:rollback` does it for you and
          `rake oubliette:uninstall` does it and then leaves.

          Written by oubliette #{VERSION}.
        MARKDOWN
      end
      private
        def automatic
          rows = entries.reject { |entry| manual?(entry) }
                        .map { |entry| [ entry[:label], where(entry) ] }
          return "Nothing yet." if rows.empty?

          table(rows, %w[Framework Now\ at])
        end

        def manual_section
          rows = entries.select { |entry| manual?(entry) }
                        .map { |entry| [ entry[:label], where(entry), Array(entry[:manual_settings]).join(", ") ] }
          return "None. Every framework oubliette moved here was configured for you." if rows.empty?

          <<~SECTION.rstrip
            Vitest, Playwright, Cypress and Karma keep their paths inside a javascript
            module -- `vitest.config.js` and friends are executable code, not data. There
            is no way to read one, change a value and write it back that cannot quietly
            corrupt it, so oubliette moves the directories and leaves the edit to you.

            There is a note for each one in this directory, naming the setting and the
            exact before and after. Until you make those edits, these suites will not
            find their tests.

            #{table(rows, [ "Framework", "Now at", "Setting to change" ])}
          SECTION
        end

        def entries
          @entries ||= displaced.map(&:gem).uniq.filter_map { |key| Catalog.find(key) }
                                .sort_by { |entry| entry[:label] }
        end

        def manual?(entry) = Array(entry[:config]).include?(:manual)

        def where(entry)
          displaced.select { |pair| pair.gem == entry[:key] }.map(&:current).uniq.sort.join(", ")
        end
    end
  end
end
