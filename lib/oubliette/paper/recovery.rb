# frozen_string_literal: true

require_relative "../config/managed_block"
require_relative "../paper"
require_relative "../text"
require_relative "../version"

module Oubliette
  class Paper
    # How to undo the migration without oubliette.
    #
    # The rollback task is the easy path and stays the easy path, but a note
    # that only works while the gem is installed is no use in the situation
    # that most needs it: a bundle that will not resolve, a colleague who has
    # never heard of this, a checkout with no ruby to hand. So the table below
    # is written to be read by a person with nothing but `git mv`.
    class Recovery < Paper
      FILENAME = "#{HOME}/RECOVERY.md"

      def filename = FILENAME

      def render
        Text.t("paper.recovery",
               open: Config::ManagedBlock::OPEN,
               close: Config::ManagedBlock::CLOSE,
               was: Config::ManagedBlock::WAS,
               rule: Notice::RULE,
               origins: origins,
               version: VERSION)
      end
      private
        def origins
          rows = displaced.map { |pair| [ pair.origin, pair.current ] }.sort
          table(rows, [ "Originally", "Now at" ])
        end
    end
  end
end
