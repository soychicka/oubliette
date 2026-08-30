# frozen_string_literal: true

require "pathname"
require_relative "path_token"
require_relative "config/managed_block"
require_relative "config/writer"

module Oubliette
  # Finds hardcoded references to the old locations that survived the move.
  #
  # Oubliette rewrites the frameworks' own configuration, but it will not edit
  # application code, and a project of any age has `Rails.root.join("spec/...")`
  # written into a helper somewhere. Those are reported rather than rewritten.
  class Scanner
    SEARCHABLE = %w[.rb .rake .yml .yaml .js .ts .json .erb .feature .sh].freeze
    SKIP = %w[.git node_modules tmp log vendor .oubliette public storage coverage]
           .push(HOME).freeze

    # The key half of a json object member, up to and including the colon.
    # A key is a name -- a package, a setting, a task -- and never a path, so
    # `"cypress": "*"` in devDependencies is the package cypress rather than the
    # directory. Only the value half is searched, and only the value half is
    # rewritten.
    JSON_KEY = /\A(\s*"[^"]*"\s*:)(.*)\z/

    Finding = Data.define(:file, :line, :path, :text, :suggestion) do
      # A match inside a comment is far less likely to be something that must
      # change, and some of them must not: a comment about what a generator does
      # is not a statement about this project's layout.
      def comment? = text.start_with?("#", "//", "/*", "*")

      def fixable? = !suggestion.nil? && suggestion != text
    end

    def initialize(root, manifest, previews: nil)
      @root = Pathname.new(root)
      @manifest = manifest
      @previews = previews
    end

    def findings
      olds = @manifest.pairs.reject(&:canonical?).map(&:origin).uniq
      return [] if olds.empty?

      pattern = Regexp.union(olds.flat_map { |old| patterns_for(old) })

      files.flat_map { |file| scan(file, pattern) }
    end
    private
      # What the line would say if it named the new location instead.
      def suggest(text)
        moves.reduce(text) { |line, (origin, target)| PathToken.substitute(line, origin, target) }
      end

      def moves
        @moves ||= @manifest.pairs
                            .reject { |pair| pair.canonical? || pair.missing? }
                            .map { |pair| [ pair.origin, pair.oubliette ] }
      end

      # Only path-shaped occurrences count. "This spec was generated" and
      # "checkbox with support features" are prose, and reporting them would
      # bury the handful of references that genuinely need editing.
      def patterns_for(old)
        [ PathToken.prefix_pattern(old), PathToken.quoted_pattern(old) ]
      end

      def files
        @root.glob("**/*").select do |path|
          path.file? && SEARCHABLE.include?(path.extname) && !skipped?(path)
        end
      end

      def skipped?(path)
        relative = path.relative_path_from(@root).to_s
        return true if [ Manifest::FILENAME, Ledger::FILENAME ].include?(relative)
        SKIP.any? { |dir| relative == dir || relative.start_with?("#{dir}/") }
      end

      # A dry run has not written the config files yet, so on disk they still
      # name the old locations. Scanning them as they stand would report every
      # line oubliette is about to fix as one the developer has to, which is
      # exactly backwards. `preview` holds what each managed file will say, and
      # is read in place of the file itself.
      #
      # Only the managed files are overlaid. Everything else in them -- a
      # cucumber profile somebody added, a script that is not oubliette's --
      # is scanned normally and still reported.
      def preview
        @preview ||= @previews || {}
      end

      def self.preview_of(root, manifest)
        Config::Writer.registry.keys.each_with_object({}) do |name, previews|
          writer = Config::Writer.build(name, root, manifest, dry_run: true, logger: ->(_line) { })
          next unless writer&.filename

          current = Pathname.new(root).join(writer.filename)
          next unless current.file?

          rendered = writer.render(current.read)
          previews[writer.filename] = rendered if rendered
        end
      end

      # Read as UTF-8 and scrub: a real project contains files with bytes that
      # are not valid in whatever encoding happens to be default, and a scanner
      # that reports references is no reason to take a migration down.
      def lines(file, relative)
        if (rendered = preview[relative])
          rendered.lines.each
        else
          File.foreach(file, encoding: "UTF-8")
        end
      end

      # Everything between oubliette's own markers was written by oubliette,
      # including the `was:` line, whose entire purpose is to hold the old path.
      # Reporting our own annotations back as your problem is noise we generate.
      def scan(file, pattern)
        relative = file.relative_path_from(@root).to_s
        inside = false

        lines(file, relative).with_index(1).filter_map do |raw, number|
          line = raw.scrub
          stripped = line.strip

          if stripped.end_with?(Config::ManagedBlock::OPEN)
            inside = true
            next
          elsif stripped.end_with?(Config::ManagedBlock::CLOSE)
            inside = false
            next
          end
          next if inside

          key, value = split(file, stripped)
          match = value[pattern]
          next unless match

          Finding.new(file: relative, line: number, path: match, text: stripped,
                      suggestion: "#{key}#{suggest(value)}")
        end
      rescue ArgumentError, EncodingError, SystemCallError
        [] # binary file wearing a text extension, or one we simply cannot read
      end

      # Splits a line into the part that cannot hold a path and the part that
      # can. Everywhere but json that is the whole line.
      def split(file, stripped)
        return [ "", stripped ] unless file.extname == ".json"

        stripped.match(JSON_KEY)&.captures || [ "", stripped ]
      end
  end
end
