# frozen_string_literal: true

require_relative "ledger"
require_relative "manifest"
require_relative "mover"
require_relative "reporter"
require_relative "scanner"
require_relative "config/rspec"
require_relative "config/cucumber"
require_relative "config/cucumber_env"
require_relative "config/javascript"
require_relative "config/jasmine"

module Oubliette
  # Detect, describe, move, rewrite, record.
  #
  # `call` is the only verb that changes anything, and it moves nothing that
  # migrate.yml and rollback.yml already agree about -- which is what lets the
  # same command serve as the first migration, the sync after installing a new
  # framework, and the way you apply an edit.
  class Runner
    def initialize(root, dry_run: false, out: $stdout, force: false)
      @root = Pathname.new(root)
      @dry_run = dry_run
      @out = out
      @force = force
      @log = ->(line) { @out.puts(line) }
    end

    # Writes migrate.yml and stops, so the targets can be edited before any
    # directory moves.
    def prepare
      manifest = Manifest.build(@root)
      manifest.save! unless @dry_run
      report(manifest)
      instructions(manifest)
      manifest
    end

    def call
      ensure_movable!
      fresh = !Manifest.exists_in?(@root)
      manifest = Manifest.build(@root)
      manifest.save! unless @dry_run

      mover = Mover.new(@root, dry_run: @dry_run, logger: @log)
      move(manifest, mover)
      write_configs(manifest)
      stage_configs(mover, manifest)
      report(manifest)
      report_stale_references(manifest)
      instructions(manifest) if fresh
      manifest
    end

    # Puts migrate.yml's targets back to oubliette's own defaults, discarding
    # hand edits, and then moves the directories to match.
    def reset(key = nil)
      manifest = Manifest.build(@root)
      manifest.reset_targets!(only: key)
      manifest.save! unless @dry_run
      @out.puts("reset #{key || 'every framework'} to oubliette's default targets")
      call
    end

    # Returns directories to their `origin` -- the framework's own default
    # location, as recorded in rollback.yml when they were first moved. What
    # migrate.yml says is irrelevant here, deliberately.
    def rollback(key = nil)
      ensure_movable!
      manifest = Manifest.exists_in?(@root) ? Manifest.load(@root) : Manifest.new(@root, {})
      ledger = Ledger.load(@root)
      mover = Mover.new(@root, dry_run: @dry_run, logger: @log)

      @out.puts(@dry_run ? "would roll back" : "rolling back")
      restore_configs(manifest, key)

      ledger.pairs(only: key).each do |pair|
        next if pair.current == pair.origin

        if @root.join(pair.current).exist?
          mover.relocate(pair.current, pair.origin)
          ledger.record!(pair.gem, pair.origin, pair.origin) unless @dry_run
        elsif @root.join(pair.origin).exist?
          # Already home, carried back inside a parent that was restored first.
          ledger.record!(pair.gem, pair.origin, pair.origin) unless @dry_run
        else
          @out.puts("  #{pair.gem}: #{pair.current} is gone, cannot restore #{pair.origin}")
        end
      end

      stage_configs(mover, manifest)
      ledger.save! unless @dry_run
      ledger
    end
    alias put_back rollback

    def status
      manifest = Manifest.exists_in?(@root) ? Manifest.load(@root) : Manifest.build(@root)
      report(manifest)
      manifest
    end
    private
      def move(manifest, mover)
        ledger = manifest.ledger
        work = manifest.pairs.reject { |pair| pair.settled? || pair.canonical? }

        @out.puts
        @out.puts(@dry_run ? "would move" : "moving")
        @out.puts("  nothing -- migrate.yml and rollback.yml already agree") if work.empty?

        movable = work.reject do |pair|
          pair.missing? && @out.puts("  #{pair.gem}: #{pair.origin} is missing from both locations, skipped")
        end
        refuse_on_conflicts!(mover, movable)

        moved = 0
        movable.each do |pair|
          pair.hops.each { |from, to| mover.relocate(from, to) }
          ledger.record!(pair.gem, pair.origin, pair.oubliette) unless @dry_run
          moved += 1
        rescue Error => error
          ledger.save! unless @dry_run
          raise Error, <<~TEXT
            #{error.message}

            #{moved} of #{movable.length} directories had already moved when this failed, and
            no framework configuration has been rewritten, so the suite will not run as
            things stand. `rake oubliette:rollback` puts the moved ones back.
          TEXT
        end

        ledger.save! unless @dry_run
      end

      # Everything is checked before anything is moved. A migration that stops
      # halfway leaves directories in their new homes and the configuration
      # still pointing at the old ones, which is worse than not starting.
      def refuse_on_conflicts!(mover, pairs)
        clashes = pairs.flat_map { |pair| pair.hops.flat_map { |from, to| mover.conflicts(from, to) } }.uniq
        return if clashes.empty?

        raise Error, <<~TEXT
          these files already exist at the destination and would be overwritten:

          #{clashes.map { |path| "  #{path}" }.join("\n")}

          Nothing has been moved. Delete or rename them and run again -- generated
          output like a coverage report is usually safe to delete.
        TEXT
      end

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

      def write_configs(manifest)
        names = manifest.gems.select { |key| manifest.enabled?(key) }
                             .flat_map { |key| manifest.config_writers(key) }
                             .uniq - [ :manual ]
        return if names.empty?

        @out.puts
        @out.puts(@dry_run ? "would rewrite config" : "rewriting config")
        names.each do |name|
          Config::Writer.build(name, @root, manifest, dry_run: @dry_run, logger: @log)&.apply
        end
      end

      def restore_configs(manifest, key)
        names = key ? manifest.config_writers(key) : Config::Writer.registry.keys
        names.each do |name|
          Config::Writer.build(name, @root, manifest, dry_run: @dry_run, logger: @log)&.revert
        end
      end

      # Config files are rewritten, not moved, so they need staging of their own
      # for the tree to still look settled on the next run.
      def stage_configs(mover, manifest)
        return if @dry_run

        names = Config::Writer.registry.keys.filter_map do |name|
          Config::Writer.build(name, @root, manifest, dry_run: true, logger: ->(_line) { })&.filename
        end
        mover.stage(*names.uniq.select { |name| @root.join(name).exist? })
      end

      def report(manifest)
        Reporter.new(manifest, out: @out).plan(dry_run: @dry_run)
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

      def instructions(manifest)
        @out.puts
        @out.puts <<~TEXT
          Wrote #{manifest.path.basename}. You can edit this file and rerun `rake oubliette`
          to use your newly specified locations -- only the entries that differ from
          #{Ledger::FILENAME} are touched, and a directory whose target changed is returned
          to its origin first, then moved to the new one.

            rake oubliette                          move what changed
            rake oubliette:dry_run                  show what would change
            rake oubliette:reset                    restore oubliette's own targets, and move
            rake oubliette:rollback                 return everything to its origin
            rake oubliette:put_back[rspec-rails]    return one framework
        TEXT
      end
  end
end
