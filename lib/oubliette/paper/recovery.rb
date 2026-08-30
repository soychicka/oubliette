# frozen_string_literal: true

require_relative "../config/managed_block"
require_relative "../paper"
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
        <<~MARKDOWN
          # Putting everything back

          Oubliette moved the directories in the table below and rewrote the
          configuration that pointed at them. Every change is reversible, and there
          are two ways to reverse it.

          **With the gem installed**, `rake oubliette:rollback` returns every
          directory to its origin and restores the configuration. Add a framework
          name to do one at a time: `rake "oubliette:rollback[cucumber-rails]"`.
          `rake oubliette:uninstall` does the same and then removes oubliette's own
          files.

          **Without it**, move each directory back with the table below, then look
          for the blocks oubliette left in your config files. Each one opens with
          `#{Config::ManagedBlock::OPEN}` and closes with
          `#{Config::ManagedBlock::CLOSE}`, and carries your original lines inside
          it, commented out and prefixed `#{Config::ManagedBlock::WAS}`. Uncomment
          those and delete the rest of the block, marker lines included. Anything
          outside a block was never touched.

          Oubliette rewrites this file on every run to match where things actually
          are. Anything you change here is ignored and will be overwritten.

          #{Notice::RULE}

          ## Where everything came from

          #{origins}

          #{Notice::RULE}

          Written by oubliette #{VERSION}. The paths above were correct as of the
          last run; `rake oubliette:status` reports where they are now.
        MARKDOWN
      end
      private
        def origins
          rows = displaced.map { |pair| [ pair.origin, pair.current ] }.sort
          table(rows, [ "Originally", "Now at" ])
        end
    end
  end
end
