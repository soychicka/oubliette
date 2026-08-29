# frozen_string_literal: true

module Oubliette
  # How a directory name is recognised inside a config file or a line of code.
  #
  # A path is only a path when it stands as a whole segment: "features" in
  # `-r features/support` is one, "features" in `--tags @features_only` is not,
  # and neither is the "e2e" inside "cypress/e2e". A leading "./" counts and is
  # kept, so a rewritten path keeps the form the developer wrote it in.
  #
  # "../features" is deliberately left alone. It points outside the project, and
  # is not the directory being moved.
  module PathToken
    module_function

    def pattern(path)
      %r{(?<![\w/.\-])(\./)?#{Regexp.escape(path)}(?=[\s/'"]|$)}
    end

    # Matches the path written as a quoted string of its own, "spec" or "./spec".
    def quoted_pattern(path)
      %r{(?<=["'`])(\./)?#{Regexp.escape(path)}(?=["'`])}
    end

    # Matches the path used as the head of a longer one, "spec/models/...".
    def prefix_pattern(path)
      %r{(?<![\w/.\-])(\./)?#{Regexp.escape(path)}/}
    end

    def substitute(text, from, to)
      text.gsub(pattern(from)) { "#{Regexp.last_match(1)}#{to}" }
    end
  end
end
