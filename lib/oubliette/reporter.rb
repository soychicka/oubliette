# frozen_string_literal: true

module Oubliette
  # Renders what oubliette is about to do, or has just done, as a plain table.
  class Reporter
    STATUS_LABEL = {
      "pending" => "move",
      "moved" => "in place",
      "missing" => "MISSING",
      "canonical" => "already there"
    }.freeze

    def initialize(manifest, out: $stdout)
      @manifest = manifest
      @out = out
    end

    def plan(dry_run: false)
      heading(dry_run ? "oubliette dry run -- nothing will be written" : "oubliette")
      @manifest.gems.each { |key| gem_section(key) }
      strays
      warnings
      self
    end

    def line(text) = @out.puts(text)
    private
      def heading(text)
        @out.puts
        @out.puts(text)
        @out.puts("-" * text.length)
      end

      def gem_section(key)
        moves = @manifest.moves(only: key)
        return if moves.empty?

        @out.puts
        @out.puts("#{key} (#{@manifest.enabled?(key) ? 'enabled' : 'disabled'})")
        moves.each do |move|
          label = STATUS_LABEL.fetch(move.status, move.status)
          @out.puts(format("  %-14s %s -> %s", label, move.from, move.to))
        end
      end

      def strays
        pending = @manifest.data["strays"].reject { |_, stray| stray["enabled"] }
        return if pending.empty?

        @out.puts
        @out.puts("unclaimed test-shaped directories (disabled -- edit migrate.yml to include)")
        pending.each_key { |name| @out.puts("  #{name}") }
      end

      def warnings
        missing = @manifest.missing
        return if missing.empty?

        @out.puts
        @out.puts("WARNING: missing from both locations -- config will be disabled")
        missing.each { |move| @out.puts("  #{move.gem}: #{move.from} (expected at #{move.to})") }
      end
  end
end
