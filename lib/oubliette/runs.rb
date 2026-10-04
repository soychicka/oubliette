# frozen_string_literal: true

require "fileutils"
require "pathname"

module Oubliette
  # The record of what the suites did, run by run.
  #
  # A flat log rather than YAML: six lines a run means a hundred runs is six
  # hundred lines, so keeping everything is affordable, and rotation and reading
  # newest-first both stay simple. Newest is written at the top, because this is
  # read in an editor rather than followed live.
  class Runs
    FILENAME = "test-runs.log"
    PATH = "#{HOME}/#{FILENAME}"
    HISTORY = "#{HOME}/history"
    LIMIT = 500

    Result = Data.define(:suite, :passed, :examples, :failures, :seconds)

    def initialize(root)
      @root = Pathname.new(root)
      @path = @root.join(PATH)
    end

    attr_reader :path

    def record(results, marker:, revision:)
      entry = render(results, marker: marker, revision: revision)
      FileUtils.mkdir_p(@path.dirname)
      @path.write(entry + existing)
      rotate
      entry
    end

    # What changed since the run before this one, per suite.
    def drift(results)
      # Called before this run is written, so the newest entry on file is the
      # one to compare against.
      previous = counts_in(runs.first.to_s)
      return [] if previous.empty?

      results.filter_map do |result|
        was = previous[result.suite]
        next if was.nil? || was == result.examples || result.examples.nil?

        "#{result.suite} #{was} -> #{result.examples}"
      end
    end

    def any?
      @path.file? && !runs.empty?
    end
    private
      def existing
        @path.file? ? Oubliette.read(@path) : ""
      end

      def render(results, marker:, revision:)
        total = results.sum { |result| result.examples.to_i }
        failed = results.sum { |result| result.failures.to_i }
        seconds = results.sum(&:seconds)

        head = format("%s  %-8s %-16s %2d suites  %4d examples  %3d failures  %6.1fs",
                      Time.now.strftime("%Y-%m-%d %H:%M"), revision, marker,
                      results.length, total, failed, seconds)

        lines = results.map do |result|
          format("    %-12s %4s  %2s fail  %6.1fs",
                 result.suite, result.examples || "?", result.failures || "?", result.seconds)
        end

        "#{([ head ] + lines).join("\n")}\n\n"
      end

      # Runs are separated by a blank line, so splitting on it gives them back.
      def runs
        existing.split(/\n{2,}/).reject(&:empty?)
      end

      def counts_in(entry)
        entry.lines.drop(1).to_h do |line|
          parts = line.split
          [ parts.first, parts[1] == "?" ? nil : parts[1].to_i ]
        end
      end

      def rotate
        return if existing.lines.length <= LIMIT

        kept, moved = split_at_limit
        return if moved.empty?

        archive(moved)
        @path.write(kept.join("\n\n") + "\n\n")
      end

      # Consolidated into one file named for the range it really covers. Writing
      # a fresh file per rotation looked tidier until two rotations landed on the
      # same day and the second silently overwrote the first.
      def archive(moved)
        directory = @root.join(HISTORY)
        FileUtils.mkdir_p(directory)

        older = directory.glob("*.log").sort
        all = moved + older.flat_map { |file| Oubliette.read(file).split(/\n{2,}/).reject(&:empty?) }
        older.each(&:delete)

        directory.join("#{dates_of(all)}.log").write(all.join("\n\n") + "\n")
      end

      def split_at_limit
        lines = 0
        runs.partition do |run|
          lines += run.lines.length + 1
          lines <= LIMIT
        end
      end

      def dates_of(moved)
        stamps = moved.map { |run| run.lines.first.to_s[0, 10] }.reject(&:empty?)

        "#{stamps.last}_#{stamps.first}"
      end
  end
end
