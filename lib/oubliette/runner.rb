# frozen_string_literal: true

require_relative "manifest"
require_relative "mover"
require_relative "reporter"
require_relative "scanner"
require_relative "config/rspec"
require_relative "config/cucumber"
require_relative "config/cucumber_env"
require_relative "config/javascript"

module Oubliette
  # Orchestrates the whole job: detect, describe, move, rewrite, record.
  #
  # `call` is deliberately the only verb that changes anything, and it is
  # idempotent -- running it twice moves nothing the second time, which is what
  # makes it double as the sync for frameworks added later.
  class Runner
    def initialize(root, dry_run: false, out: $stdout, force: false)
      @root = Pathname.new(root)
      @dry_run = dry_run
      @out = out
      @force = force
      @log = ->(line) { @out.puts(line) }
    end

    # Writes migrate.yml and stops, so the user can edit targets before any
    # directory moves.
    def prepare
      manifest = Manifest.build(@root)
      manifest.save! unless @dry_run
      Reporter.new(manifest, out: @out).plan(dry_run: @dry_run)
      instructions(manifest, prepared: true)
      manifest
    end

    def call
      ensure_movable!
      fresh = !Manifest.exists_in?(@root)
      manifest = Manifest.build(@root)
      manifest.save! unless @dry_run

      mover = Mover.new(@root, dry_run: @dry_run, logger: @log)

      @out.puts
      @out.puts(@dry_run ? "would move" : "moving")
      manifest.moves.each do |move|
        result = mover.apply(move)
        next if %i[canonical unchanged missing].include?(result)

        manifest.record!(move, applied: move.to, status: "moved") unless @dry_run
      end

      manifest.refresh_statuses!
      write_configs(manifest)
      stage_configs(mover, manifest)
      manifest.save! unless @dry_run

      report_stale_references(manifest)
      Reporter.new(manifest, out: @out).plan(dry_run: @dry_run)
      instructions(manifest, prepared: fresh)
      manifest
    end

    def rollback(key = nil)
      manifest = Manifest.load(@root)
      ensure_movable!
      mover = Mover.new(@root, dry_run: @dry_run, logger: @log)

      @out.puts(@dry_run ? "would roll back" : "rolling back")
      restore_configs(manifest, key)

      manifest.moves(only: key).reverse_each do |move|
        next if mover.revert(move) == :unchanged && !@dry_run

        manifest.record!(move, applied: nil, status: "pending") unless @dry_run
      end

      stage_configs(mover, manifest)
      manifest.refresh_statuses!
      manifest.save! unless @dry_run
      manifest
    end

    def status
      manifest = Manifest.exists_in?(@root) ? Manifest.load(@root).refresh_statuses! : Manifest.build(@root)
      Reporter.new(manifest, out: @out).plan(dry_run: true)
      manifest
    end
    private
      def ensure_movable!
        return if @dry_run || @force

        mover = Mover.new(@root)
        return if !mover.git? || mover.stable?

        raise Error, <<~TEXT
          the working tree has unstaged or untracked changes.

          oubliette moves directories with `git mv`, so commit or stash first --
          or rerun with FORCE=1 if you know what you are doing.
        TEXT
      end

      # Config files are rewritten, not moved, so they need staging of their own
      # for the tree to still look settled on the next run.
      def stage_configs(mover, manifest)
        return if @dry_run

        @manifest_for_staging = manifest

        names = Config::Writer.registry.keys.filter_map do |name|
          Config::Writer.build(name, @root, @manifest_for_staging, dry_run: true, logger: ->(_) { })&.filename
        end
        mover.stage(*names.uniq.select { |name| @root.join(name).exist? })
      end

      def write_configs(manifest)
        names = manifest.gems.select { |key| manifest.enabled?(key) }
                             .flat_map { |key| manifest.config_writers(key) }
                             .uniq - [ :manual ]
        return if names.empty?

        @out.puts
        @out.puts(@dry_run ? "would rewrite config" : "rewriting config")
        names.each do |name|
          writer = Config::Writer.build(name, @root, manifest, dry_run: @dry_run, logger: @log)
          writer&.apply
        end
      end

      def restore_configs(manifest, key)
        names = if key
          manifest.config_writers(key)
        else
          Config::Writer.registry.keys
        end

        names.each do |name|
          writer = Config::Writer.build(name, @root, manifest, dry_run: @dry_run, logger: @log)
          writer&.revert
        end
      end

      # Oubliette rewrites framework config, never application code, so anything
      # that named an old path in a helper or a rake task is listed here for a
      # human to deal with.
      def report_stale_references(manifest)
        findings = Scanner.new(@root, manifest).findings
        return if findings.empty?

        @out.puts
        @out.puts("stale references to the old locations -- these are yours to update")
        findings.first(40).each do |finding|
          @out.puts(format("  %s:%d  %s", finding.file, finding.line, finding.text))
        end
        @out.puts("  ... and #{findings.length - 40} more") if findings.length > 40
      end

      def instructions(manifest, prepared:)
        return unless prepared

        @out.puts
        @out.puts <<~TEXT
          Wrote #{manifest.path.basename}. You can edit this file and rerun `rake oubliette`
          to use your newly specified locations -- a directory whose target changed is
          returned to its original path first, then moved to the new one.

            rake oubliette                 move and sync
            rake oubliette:dry_run         show what would change
            rake oubliette:rollback        undo everything
            rake oubliette:rollback[rspec-rails]   undo one framework
        TEXT
      end
  end
end
