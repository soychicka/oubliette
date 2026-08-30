# frozen_string_literal: true

module Oubliette
  # Keeps what oubliette says apart from what the machine says.
  #
  # A rule goes between our prose and anything dense the reader is not meant to
  # read as a sentence: paths, backtraces, file lists, config. Instructions
  # printed flush against a wall of paths do not get read.
  #
  # On an aborted task rake owns the layout -- it prints the class name, then
  # our message, then the backtrace -- so the rules have to travel inside the
  # message itself, the closing one being the last thing written before raising.
  module Notice
    WIDTH = 80
    RULE = ("-" * WIDTH).freeze

    module_function

    def rule = RULE

    # Prose fenced above and below, for a message rake will print between its
    # own headline and its own backtrace.
    def fenced(prose)
      "\n#{RULE}\n\n\n#{prose.to_s.rstrip}\n\n\n#{RULE}\n"
    end

    def error(headline, prose)
      "#{headline}\n#{fenced(prose)}"
    end
  end
end
