# frozen_string_literal: true

module Oubliette
  # Renders what oubliette is about to do, or has just done, as a plain table.
  class Reporter
    STATUS_LABEL = {
      pending: "move",
      settled: "in place",
      missing: "MISSING",
      canonical: "already there"
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
        @out.puts("#{key} (#{@manifest.enabled?(key) ? 'enabled' : 'disabled'})")
        pairs.each do |pair|
          label = STATUS_LABEL.fetch(pair.status, pair.status.to_s)
          @out.puts(format("  %-14s %s -> %s", label, pair.origin, pair.oubliette))
        end
      end

      def strays
        pending = @manifest.data["strays"].reject { |_name, stray| stray["enabled"] }
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
        missing.each { |pair| @out.puts("  #{pair.gem}: #{pair.origin} (expected at #{pair.oubliette})") }
      end
  end
end
