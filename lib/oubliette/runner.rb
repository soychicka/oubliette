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
require_relative "config/manual_guide"

module Oubliette
  # Detect, describe, move, rewrite, record.
  #
  # `call` is the only verb that changes anything, and it moves nothing that
  # migrate.yml and rollback.yml already agree about -- which is what lets the
  # same command serve as the first migration, the sync after installing a new
  # framework, and the way you apply an edit.
  class Runner
    def initialize(root, dry_run: false, out: $stdout, input: $stdin, force: false)
      @root = Pathname.new(root)
      @dry_run = dry_run
      @out = out
      @input = input
      @force = force
      @log = ->(line) { @out.puts(line) }
    end

    # Writes migrate.yml and stops, so the targets can be edited before any
    # directory moves.
    def prepare
      manifest = Manifest.build(@root)
      manifest.save! unless @dry_run
      report(manifest)
      prepared(manifest)
      manifest
    end

    def call
      ensure_movable!
      first_run = !Manifest.exists_in?(@root)
      manifest = Manifest.build(@root)
      manifest.save! unless @dry_run

      return manifest if first_run && !@dry_run && !confirmed?(manifest)

      mover = Mover.new(@root, dry_run: @dry_run, logger: @log)
      moved = move(manifest, mover)
      write_configs(manifest)
      stage_configs(mover, manifest)
      report(manifest)
      report_stale_references(manifest)
      finished(manifest) if moved.to_i.positive? && !@dry_run
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
        moved
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
        guides = manual_guides(manifest)
        return if names.empty? && guides.empty?

        @out.puts
        @out.puts(@dry_run ? "would rewrite config" : "rewriting config")
        names.each do |name|
          Config::Writer.build(name, @root, manifest, dry_run: @dry_run, logger: @log)&.apply
        end

        guides.each(&:apply)
      end

      # A config oubliette will not rewrite gets written instructions instead.
      def manual_guides(manifest)
        manifest.manual_configs.map do |entry|
          Config::ManualGuide.new(@root, manifest, entry: entry, dry_run: @dry_run, logger: @log)
        end
      end

      def restore_configs(manifest, key)
        names = key ? manifest.config_writers(key) : Config::Writer.registry.keys
        names.each do |name|
          Config::Writer.build(name, @root, manifest, dry_run: @dry_run, logger: @log)&.revert
        end

        manual_guides(manifest).each(&:revert)
      end

      # Config files are rewritten, not moved, so they need staging of their own
      # for the tree to still look settled on the next run.
      def stage_configs(mover, manifest)
        return if @dry_run

        names = Config::Writer.registry.keys.filter_map do |name|
          Config::Writer.build(name, @root, manifest, dry_run: true, logger: ->(_line) { })&.filename
        end
        names += manual_guides(manifest).map(&:filename)
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

      def prepared(manifest)
        @out.puts
        @out.puts <<~TEXT
          Wrote #{manifest.path}. Nothing has moved.

            to exclude a framework, delete its entire entry from #{Manifest::FILENAME}
            to change a target path, edit that entry's 'oubliette' attribute

          when you're ready, run

              rake oubliette
        TEXT
      end

      # The first run shows the developer what it proposes and waits to be told
      # to go ahead. Nothing has moved at this point; only migrate.yml has been
      # written, which is the file the answer is about.
      def confirmed?(manifest)
        show_manifest(manifest)
        return proceed("not a terminal, so proceeding without asking") unless interactive?

        @out.print("\ndo you want your test directories in this hierarchy? [y/N] ")
        @out.flush if @out.respond_to?(:flush)

        if @input.gets.to_s.strip.downcase.start_with?("y")
          proceed("moving everything into place")
        else
          declined(manifest)
          false
        end
      end

      def interactive?
        @input.respond_to?(:tty?) && @input.tty?
      end

      def proceed(reason)
        @out.puts(reason)
        true
      end

      def show_manifest(manifest)
        @out.puts
        @out.puts("this is what oubliette proposes, written to #{manifest.path}:")
        @out.puts
        manifest.render.each_line { |line| @out.puts("  #{line.chomp}") }
      end

      def declined(manifest)
        @out.puts <<~TEXT

          ok, we'll break here for now. Nothing has been moved.

            to change these paths, you can manually modify the configuration by editing
            => #{manifest.path}

            to exclude a framework from consolidation, delete the entire entry for the gem
            from #{Manifest::FILENAME}

            to change a target path, update the path in the 'oubliette' attribute to your
            preferred target path

          when you're ready to proceed, run

              rake oubliette

          again to implement your changes.
        TEXT
      end

      def finished(manifest)
        @out.puts
        @out.puts("I have turned the test suite upside down, and I have done it all for you.")
        @out.puts
        @out.puts("  #{manifest.path}")
        @out.puts("      what you asked for. Edit a path and rerun `rake oubliette`.")
        @out.puts("  #{Ledger.path_in(@root)}")
        @out.puts("      where everything came from. `rake oubliette:rollback` reads this.")
        guides = manifest.manual_configs
        guides.each do |entry|
          @out.puts("  #{@root.join("#{entry.file}.oubliette.md")}")
          @out.puts("      #{entry.file} is yours to update; these are the instructions.")
        end
        @out.puts
        @out.puts("  rake oubliette:status     where every test directory now lives")
        @out.puts("  rake oubliette:rollback   put it all back")
      end
  end
end
