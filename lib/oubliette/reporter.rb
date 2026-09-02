# frozen_string_literal: true

require_relative "notice"
require_relative "text"

module Oubliette
  # Renders what oubliette is about to do, or has just done, as a plain table.
  class Reporter
    def self.status_labels = @status_labels ||= Text.group("reporter.status")

    def initialize(manifest, out: $stdout)
      @manifest = manifest
      @out = out
    end

    def plan(dry_run: false)
      heading(dry_run ? Text.t("reporter.heading.dry_run") : Text.t("reporter.heading.plan"))
      @manifest.gems.each { |key| gem_section(key) }
      strays
      manual_configs
      warnings
      self
    end
    private
      def heading(text)
        @out.puts
        @out.puts(text)
        @out.puts("-" * text.length)
      end

      def gem_section(key)
        pairs = @manifest.pairs(only: key)
        return if pairs.empty?

        @out.puts
        if @manifest.enabled?(key)
          @out.puts(Text.t("reporter.gem.enabled", gem: key))
        else
          @out.puts(Text.t("reporter.gem.disabled", gem: key))
        end
        pairs.each do |pair|
          label = self.class.status_labels.fetch(pair.status, pair.status.to_s)
          @out.puts(format("  %-14s %s -> %s", label, pair.origin, pair.oubliette))
        end
      end

      def strays
        pending = @manifest.data["strays"].reject { |_name, stray| stray["enabled"] }
        return if pending.empty?

        @out.puts
        @out.puts(Text.t("reporter.strays.heading"))
        pending.each_key { |name| @out.puts(Text.t("reporter.strays.item", name: name)) }
      end

      # These keep their paths in a javascript module rather than in JSON, so
      # oubliette moves the directories and leaves the config alone. Saying
      # nothing would let a suite quietly stop finding its own specs.
      def manual_configs
        manual = @manifest.manual_configs
        return if manual.empty?

        @out.puts
        @out.puts(Text.t("reporter.manual.heading"))
        @out.puts
        @out.puts(Notice.rule)
        manual.each do |entry|
          moves = entry.pairs.map { |pair| "#{pair.origin} -> #{pair.oubliette}" }.join(", ")
          @out.puts(Text.t("reporter.manual.entry", file: entry.file, gem: entry.gem, moves: moves))
        end
        @out.puts
        @out.puts(Notice.rule)
      end

      def warnings
        missing = @manifest.missing
        return if missing.empty?

        @out.puts
        @out.puts(Text.t("reporter.warning.heading"))
        missing.each do |pair|
          @out.puts(Text.t("reporter.warning.entry",
                           gem: pair.gem, origin: pair.origin, oubliette: pair.oubliette))
        end
      end
  end
end
