# frozen_string_literal: true

require "pathname"
require_relative "path_token"
require_relative "config/managed_block"

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

    Finding = Data.define(:file, :line, :path, :text)

    def initialize(root, manifest)
      @root = Pathname.new(root)
      @manifest = manifest
    end

    def findings
      olds = @manifest.pairs.reject(&:canonical?).map(&:origin).uniq
      return [] if olds.empty?

      pattern = Regexp.union(olds.flat_map { |old| patterns_for(old) })

      files.flat_map { |file| scan(file, pattern) }
    end
    private
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

      # Everything between oubliette's own markers was written by oubliette,
      # including the `was:` line, whose entire purpose is to hold the old path.
      # Reporting our own annotations back as your problem is noise we generate.
      def scan(file, pattern)
        relative = file.relative_path_from(@root).to_s
        inside = false

        file.each_line.with_index(1).filter_map do |line, number|
          stripped = line.strip

          if stripped.end_with?(Config::ManagedBlock::OPEN)
            inside = true
            next
          elsif stripped.end_with?(Config::ManagedBlock::CLOSE)
            inside = false
            next
          end
          next if inside

          match = line[pattern]
          next unless match

          Finding.new(file: relative, line: number, path: match, text: stripped)
        end
      rescue ArgumentError
        [] # binary file wearing a text extension
      end
  end
end
