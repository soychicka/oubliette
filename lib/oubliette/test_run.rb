# frozen_string_literal: true

require "open3"
require_relative "manifest"
require_relative "notice"
require_relative "runs"
require_relative "suite"

module Oubliette
  # Runs every suite the project has, and says what changed since last time.
  #
  # The point is not the pass or fail -- each runner says that already -- but the
  # comparison. "Five suites pass" is much weaker than "the same suites pass as
  # before", and a suite that quietly stops being collected shows up as a count
  # that fell rather than as a failure.
  class TestRun
    def initialize(root, out: $stdout, only: nil)
      @root = Pathname.new(root)
      @out = out
      @only = only
    end

    def call
      suites = suites_to_run
      return report_nothing if suites.empty?

      results = suites.map { |suite| run(suite) }
      record(results)
      summarise(results)

      results.all?(&:passed)
    end
    private
      def suites_to_run
        manifest = Manifest.exists_in?(@root) ? Manifest.load(@root) : Manifest.build(@root)
        found = Suites.for(@root, manifest)

        @only ? found.select { |suite| suite.key == @only } : found
      end

      def run(suite)
        @out.puts
        @out.puts("----- #{suite.label} -----")
        @out.puts

        started = Time.now
        output, status = Open3.capture2e(*suite.command, chdir: @root.to_s)
        seconds = Time.now - started

        @out.puts(output)
        tally = suite.tally(output, passed: status.success?)

        Runs::Result.new(suite: suite.key, passed: status.success?,
                         examples: tally[:examples], failures: tally[:failures], seconds: seconds)
      end

      def record(results)
        runs = Runs.new(@root)
        had_history = runs.any?
        drift = had_history ? runs.drift(results) : []
        runs.record(results, marker: marker, revision: revision)

        @drift = drift
        @first_run = !had_history
      end

      def summarise(results)
        @out.puts
        @out.puts(Notice.rule)
        @out.puts
        results.each do |result|
          @out.puts(format("  %-12s %-5s %4s examples  %2s failures  %6.1fs",
                           result.suite, result.passed ? "pass" : "FAIL",
                           result.examples || "?", result.failures || "?", result.seconds))
        end
        @out.puts
        @out.puts(Notice.rule)
        @out.puts
        @out.puts(verdict(results))
        report_drift
      end

      def verdict(results)
        failed = results.reject(&:passed)

        failed.empty? ? "everything green" : "#{failed.map(&:suite).join(', ')} failed"
      end

      def report_drift
        if @first_run
          @out.puts("no earlier run to compare against. Run this again after migrating to see drift.")
        elsif @drift.empty?
          @out.puts("no drift since the last run.")
        else
          @out.puts
          @out.puts("DRIFT since the last run -- a count that moved without a failure is worth a look:")
          @drift.each { |line| @out.puts("  #{line}") }
        end
      end

      # Which side of a migration this run sits on, so the comparison that
      # matters -- before against after -- can be found later.
      def marker
        manifest = Manifest.exists_in?(@root) ? Manifest.load(@root) : nil
        return "no migration" if manifest.nil?

        manifest.pairs.any?(&:settled?) ? "after migrate" : "before migrate"
      end

      def revision
        stdout, status = Open3.capture2("git", "-C", @root.to_s, "rev-parse", "--short", "HEAD")

        status.success? ? stdout.strip : "-"
      rescue StandardError
        "-"
      end

      def report_nothing
        @out.puts("no test suites found here.")
        true
      end
  end
end
