# frozen_string_literal: true

require_relative "../catalog"
require_relative "../paper"
require_relative "../text"
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
        Text.t("paper.readme",
               rule: Notice::RULE,
               automatic: automatic,
               manual: manual_section,
               version: VERSION)
      end
      private
        def automatic
          rows = entries.reject { |entry| manual?(entry) }
                        .map { |entry| [ entry[:label], where(entry) ] }
          return Text.t("paper.readme_nothing") if rows.empty?

          table(rows, [ Text.t("paper.headers.framework"), Text.t("paper.headers.now_at") ])
        end

        def manual_section
          rows = entries.select { |entry| manual?(entry) }
                        .map { |entry| [ entry[:label], where(entry), Array(entry[:manual_settings]).join(", ") ] }
          return Text.t("paper.readme_all_automatic") if rows.empty?

          headers = [ Text.t("paper.headers.framework"), Text.t("paper.headers.now_at"),
                      Text.t("paper.headers.setting") ]

          Text.t("paper.readme_manual", table: table(rows, headers)).rstrip
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
