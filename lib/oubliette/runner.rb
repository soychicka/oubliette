# frozen_string_literal: true

require_relative "ledger"
require_relative "manifest"
require_relative "mover"
require_relative "reporter"
require_relative "scanner"
require_relative "test_run"
require_relative "notice"
require_relative "text"
require_relative "repair"
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
    FINDINGS_SHOWN = 40
    FINDING_WIDTH = 68

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
      first_run = !Manifest.exists_in?(@root)
      manifest = Manifest.build(@root)
      manifest.save! unless @dry_run
      ensure_movable!(manifest.pairs.reject(&:configured?).flat_map { |pair| [ pair.origin, pair.current, pair.oubliette ] })

      return manifest if first_run && !@dry_run && !confirmed?(manifest)

      mover = Mover.new(@root, dry_run: @dry_run, logger: @log)
      done = []

      begin
        move(manifest, mover, done)
        write_configs(manifest)
        stage_configs(mover, manifest)
      rescue StandardError => error
        undo(manifest, mover, done, error)
      end

      record(manifest, done)
      refresh_papers(manifest.ledger)
      moved = done.length
      report(manifest)
      report_stale_references(manifest)
      finished(manifest) if moved.to_i.positive? && !@dry_run
      manifest
    end

    # Puts migrate.yml's targets back to oubliette's own defaults, discarding
    # hand edits, and then moves the directories to match.
    def reset(key = nil)
      Ledger.load(@root).forget_known!(key).save!
      manifest = Manifest.build(@root)
      manifest.reset_targets!(only: key)
      manifest.save! unless @dry_run
      @out.puts(Text.t("runner.reset", scope: key || Text.t("runner.reset_all")))
      call
    end

    # Returns directories to their `origin` -- the framework's own default
    # location, as recorded in rollback.yml when they were first moved. What
    # migrate.yml says is irrelevant here, deliberately.
    def rollback(key = nil)
      manifest = Manifest.exists_in?(@root) ? Manifest.load(@root) : Manifest.new(@root, {})
      ledger = Ledger.load(@root)
      ensure_movable!(ledger.pairs(only: key).flat_map { |pair| [ pair.origin, pair.current ] })
      mover = Mover.new(@root, dry_run: @dry_run, logger: @log)

      @out.puts(@dry_run ? Text.t("runner.would_roll_back") : Text.t("runner.rolling_back"))
      mover.protect(ledger.pairs(only: key).map(&:origin))
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
          @out.puts(Text.t("runner.cannot_restore",
                            gem: pair.gem, current: pair.current, origin: pair.origin))
        end
      end

      stage_configs(mover, manifest)
      unless @dry_run
        ledger.save!
        refresh_papers(ledger)
      end
      ledger
    end
    alias put_back rollback

    def status
      manifest = Manifest.exists_in?(@root) ? Manifest.load(@root) : Manifest.build(@root)
      report(manifest)
      manifest
    end
    private
      def move(manifest, mover, done)
        work = manifest.pairs.reject { |pair| pair.settled? || pair.canonical? || pair.configured? }
        mover.protect(manifest.pairs.flat_map { |pair| [ pair.origin, pair.current ] })

        @out.puts
        @out.puts(@dry_run ? Text.t("runner.would_move") : Text.t("runner.moving"))
        @out.puts(Text.t("runner.nothing_to_do")) if work.empty?

        movable = work.reject do |pair|
          pair.missing? && @out.puts(Text.t("runner.skipped_missing", gem: pair.gem, origin: pair.origin))
        end
        refuse_on_conflicts!(mover, movable)

        movable.each do |pair|
          pair.hops.each { |from, to| mover.relocate(from, to) }
          done << pair
        end
      end

      # Nothing is written down until the whole run has succeeded, so a failure
      # can put the directories back and leave no trace of having tried.
      def record(manifest, done)
        return if @dry_run || done.empty?

        done.each { |pair| manifest.ledger.record!(pair.gem, pair.origin, pair.oubliette) }
        manifest.ledger.save!
      end

      # The README and the recovery note describe where things are, so they are
      # rewritten from the ledger every time that changes -- and deleted once
      # nothing is displaced, since a recovery note for an empty oubliette is
      # just something else to be out of date.
      def refresh_papers(ledger)
        return if @dry_run

        Paper.refresh(@root, ledger, out: @out)
      end

      # A migration that stops halfway is the worst outcome available: the
      # directories are somewhere new and every framework still points at where
      # they were. Rollback already knows how to reverse a move, so a failed run
      # reverses its own instead of asking the developer to do it.
      def undo(manifest, mover, done, error)
        # Nothing moved, so there is nothing to undo and nothing to explain away:
        # the collision pre-flight and the dirty-tree refusal already say exactly
        # what is wrong, and wrapping them would throw that away.
        # Oubliette's own errors explain themselves -- the collision pre-flight
        # and the dirty-tree refusal name the files that matter -- so they pass
        # through untouched. Anything else is a surprise and gets wrapped, even
        # with nothing moved, rather than reaching rake as a bare backtrace.
        raise error if @dry_run || error.is_a?(Error)

        restore_configs(manifest, nil)
        mover.protect(done.flat_map { |pair| [ pair.origin, pair.current ] })
        failed = undo_moves(mover, done)

        raise Error, Notice.error(*undone_message(error, done, failed))
      end

      def undo_moves(mover, done)
        done.reverse.filter_map do |pair|
          mover.relocate(pair.oubliette, pair.current)
          nil
        rescue StandardError => undo_error
          "  #{pair.oubliette} -> #{pair.current}: #{undo_error.message.lines.first.to_s.chomp}"
        end
      end

      # Not put_back: that name is already the public alias for rollback.
      def restored_note(count)
        return "" if count.zero?

        return Text.t("runner.restored_one") if count == 1

        Text.t("runner.restored_many", count: count)
      end

      def undone_message(error, done, failed)
        headline = error.message.lines.first.to_s.chomp
        if failed.empty?
          [ headline, Text.t("runner.nothing_changed", note: restored_note(done.length)) ]
        else
          [ headline, Text.t("runner.undo_failed", failed: failed.join("\n")) ]
        end
      end

      # Everything is checked before anything is moved. A migration that stops
      # halfway leaves directories in their new homes and the configuration
      # still pointing at the old ones, which is worse than not starting.
      def refuse_on_conflicts!(mover, pairs)
        clashes = pairs.flat_map { |pair| pair.hops.flat_map { |from, to| mover.conflicts(from, to) } }
        clashes += converging(mover, pairs)
        clashes = clashes.uniq
        return if clashes.empty?

        raise Error, Notice.error(
          Text.t("runner.conflicts.headline"),
          Text.t("runner.conflicts.body", clashes: clashes.map { |path| "  #{path}" }.join("\n"))
        )
      end

      # Two directories heading for the same destination collide with each other
      # rather than with anything on disk, so there is nothing to compare against
      # until the first has already moved. Compare their contents instead.
      def converging(mover, pairs)
        pairs.group_by(&:oubliette).flat_map do |target, group|
          next [] if group.length < 2

          seen = {}
          group.flat_map do |pair|
            mover.files_in(pair.current).filter_map do |file|
              seen.key?(file) ? "#{target}/#{file}" : (seen[file] = true and nil)
            end
          end
        end
      end

      def ensure_movable!(paths)
        return if @dry_run || @force

        mover = Mover.new(@root)
        return unless mover.git?

        dirty = mover.unsettled_within(paths.compact.uniq)
        return if dirty.empty?

        raise Error, Notice.error(
          Text.t("runner.dirty.headline"),
          Text.t("runner.dirty.body", dirty: dirty.map { |path| "  #{path}" }.join("\n"))
        )
      end

      def write_configs(manifest)
        names = manifest.gems.select { |key| manifest.enabled?(key) }
                             .flat_map { |key| manifest.config_writers(key) }
                             .uniq - [ :manual ]
        guides = manual_guides(manifest)
        return if names.empty? && guides.empty?

        @out.puts
        @out.puts(@dry_run ? Text.t("runner.would_rewrite") : Text.t("runner.rewriting"))
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
        previews = Scanner.preview_of(@root, manifest) if @dry_run
        findings = Scanner.new(@root, manifest, previews: previews).findings
        return if findings.empty?

        repair = Repair.new(@root, findings, out: @out, input: @input)

        case repair.offer
        when :nothing
          @out.puts
          @out.puts(Text.t("runner.stale.heading"))
          @out.puts
          @out.puts(Notice.rule)
          render_findings(findings)
          @out.puts
          @out.puts(Notice.rule)
        when :easy
          repaired = repair.apply
          @out.puts
          if repaired.length == 1
            @out.puts(Text.t("runner.stale.repaired_one"))
          else
            @out.puts(Text.t("runner.stale.repaired_many", count: repaired.length))
          end
          @out.puts
          TestRun.new(@root, out: @out).call
        end
      end

      # Grouped by file, because the path is the repetitive part -- one run had
      # the same helper listed six times -- and because a flat table would push
      # the matched text past column fifty and leave nothing to read.
      #
      # Files holding real code come first: a match inside a comment is far less
      # likely to be something you must act on.
      def render_findings(findings)
        shown = findings.first(FINDINGS_SHOWN)
        grouped = shown.group_by(&:file)
        ordered = grouped.sort_by { |file, group| [ group.all? { |f| comment?(f) } ? 1 : 0, file ] }

        ordered.each do |file, group|
          @out.puts
          @out.puts(Text.t("runner.stale.file", file: file))
          group.each { |finding| @out.puts(format("  %5d   %s", finding.line, clip(finding.text))) }
        end

        return if findings.length <= FINDINGS_SHOWN

        @out.puts
        @out.puts(Text.t("runner.stale.more", count: findings.length - FINDINGS_SHOWN))
      end

      def comment?(finding)
        finding.text.start_with?("#", "//", "/*", "*")
      end

      def clip(text)
        text.length > FINDING_WIDTH ? "#{text[0, FINDING_WIDTH - 1]}\u2026" : text
      end

      def prepared(manifest)
        @out.puts
        @out.puts(Text.t("runner.prepared", path: manifest.path, filename: Manifest::FILENAME))
      end

      # The first run shows the developer what it proposes and waits to be told
      # to go ahead. Nothing has moved at this point; only migrate.yml has been
      # written, which is the file the answer is about.
      def confirmed?(manifest)
        show_manifest(manifest)
        return proceed("not a terminal, so proceeding without asking") unless interactive?

        @out.print("\n#{Text.t('runner.confirm')}")
        @out.flush if @out.respond_to?(:flush)

        if accepted?(@input.gets)
          proceed("moving everything into place")
        else
          declined(manifest)
          false
        end
      end

      # Enter accepts, because running this task is already the decision. The
      # strictness moves to the other side: anything unrecognised declines, so a
      # fat-fingered line cannot start a migration.
      def accepted?(answer)
        reply = answer.to_s.strip.downcase

        reply.empty? || reply == "y" || reply == "yes"
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
        @out.puts(Text.t("runner.proposal", path: manifest.path))
        @out.puts
        @out.puts(Notice.rule)
        @out.puts
        manifest.render.each_line { |line| @out.puts(Text.t("runner.proposal_line", line: line.chomp)) }
        @out.puts
        @out.puts(Notice.rule)
      end

      def declined(manifest)
        @out.puts(Text.t("runner.declined", path: manifest.path, filename: Manifest::FILENAME))
      end

      def finished(manifest)
        @out.puts
        @out.puts(Text.t("runner.finished.headline"))
        @out.puts
        @out.puts(Notice.rule)
        @out.puts
        @out.puts(Text.t("runner.finished.manifest", path: manifest.path))
        @out.puts(Text.t("runner.finished.manifest_note"))
        @out.puts(Text.t("runner.finished.ledger", path: Ledger.path_in(@root)))
        @out.puts(Text.t("runner.finished.ledger_note"))
        @out.puts(Text.t("runner.finished.recovery", path: @root.join(Paper::Recovery::FILENAME)))
        @out.puts(Text.t("runner.finished.recovery_note"))
        # Asked of the guide rather than rebuilt from the entry: this printed a
        # filename it had worked out for itself, and the two rules had drifted.
        manual_guides(manifest).each do |guide|
          @out.puts(Text.t("runner.finished.guide", path: @root.join(guide.filename)))
          @out.puts(Text.t("runner.finished.guide_note", file: guide.entry.file))
        end
        @out.puts
        @out.puts(Notice.rule)
        @out.puts
        @out.puts(Text.t("runner.finished.status"))
        @out.puts(Text.t("runner.finished.rollback"))
      end
  end
end
