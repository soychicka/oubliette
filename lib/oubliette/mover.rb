# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"
require_relative "manifest"
require_relative "ledger"
require_relative "config/writer"
require_relative "requires"
require_relative "text"

module Oubliette
  # Performs the relocations described by the manifest. Directories are merged
  # rather than replaced, because several frameworks can legitimately feed the
  # same destination (spec/factories and test/factories both become
  # test/data/factories), and every relocation is recorded so it can be undone.
  class Mover
    def initialize(root, dry_run: false, logger: nil)
      @root = Pathname.new(root)
      @dry_run = dry_run
      @log = logger || ->(line) { puts line }
      @protected = []
    end

    # Directories the run still intends to move. Emptying spec/ by extracting
    # spec/javascript out of it does not make spec/ rubbish -- it is the next
    # thing on the list.
    def protect(paths)
      @protected = paths.compact.uniq
    end

    def dry_run? = @dry_run

    # A move whose target changed since it was applied goes home first, so the
    # manifest never has to describe more than one hop.
    def apply(move)
      return :canonical if move.canonical?
      return :missing if move.missing?

      if move.moved? && move.applied != move.to
        relocate(move.applied, move.from)
        relocate(move.from, move.to)
        :rehomed
      elsif move.moved?
        :unchanged
      else
        return :missing unless @root.join(move.from).exist?

        relocate(move.from, move.to)
        :moved
      end
    end

    def revert(move)
      return :canonical if move.canonical?

      current = move.applied
      return :unchanged unless current && @root.join(current).exist?
      return :unchanged if current == move.from

      relocate(current, move.from)
      :reverted
    end

    # What relocating would overwrite, without relocating anything. The runner
    # asks this of every move before it makes the first one, so a collision
    # stops the migration while the project is still whole.
    def conflicts(from, to)
      source = @root.join(from)
      target = @root.join(to)
      return [] unless source.directory? && target.directory?

      collisions(source, target)
    end

    # The files a directory would contribute to its destination, relative to it.
    # Placeholders are left out: one .keep replaces another without complaint.
    def files_in(from)
      source = @root.join(from)
      return [] unless source.directory?

      source.glob("**/*", File::FNM_DOTMATCH)
            .select { |path| path.file? && !placeholder?(path) }
            .map { |path| path.relative_path_from(source).to_s }
    end

    def relocate(from, to)
      source = @root.join(from)
      target = @root.join(to)
      @log.call(Text.t("mover.relocated", from: from, to: to))
      return if @dry_run

      # Collected before the move: a merge into a shared destination must not
      # repair a neighbour's files as though they had come from here.
      ruby_files = source.directory? ? relative_ruby_files(source) : []

      raise Error, "#{from} does not exist" unless source.exist?
      raise Error, "refusing to move #{from} into its own subdirectory #{to}" if to.start_with?("#{from}/")
      raise Error, "#{to} exists and is a file" if target.file?

      if target.directory?
        merge_into(source, target)
      else
        FileUtils.mkdir_p(target.dirname)
        git_mv(source, target) || FileUtils.mv(source.to_s, target.to_s)
      end

      prune_empty_ancestors(from)
      repaired = Requires.new(@root).repair(from: from, to: to, files: ruby_files)
      repaired.each { |file| @log.call(Text.t("mover.repaired", file: file)) }
      stage(from, to)
    end

    def git?
      return @git if defined?(@git)

      @git = system("git", "-C", @root.to_s, "rev-parse", "--is-inside-work-tree",
                    out: File::NULL, err: File::NULL)
    end

    def clean?
      porcelain.empty?
    end

    # Looser than clean?, and the condition the runner actually enforces: work
    # that git has not been told about at all. Oubliette stages its own moves as
    # it makes them, so this stays true across repeated runs while still
    # catching a developer who has edits in flight.
    def stable?
      porcelain.none? { |line| line.start_with?("??") || line[1] != " " }
    end

    # migrate.yml and the config backups are oubliette's own working files, so
    # their being uncommitted is never a reason to refuse to run.
    PLACEHOLDERS = %w[.keep .gitkeep].freeze

    # ".oubliette" held the config backups older versions took before they
    # learned to edit in place. Nothing writes it now, but a project that has
    # one should not be told its tree is dirty because of it.
    # Oubliette's own files. Their being uncommitted is never a reason to
    # refuse to run. ".oubliette" held the config backups older versions took
    # before they learned to edit in place; nothing writes it now.
    OWNED = [ HOME, Manifest::FILENAME, Ledger::FILENAME, ".oubliette" ].freeze

    # Kept public because the runner stages the config files it rewrites, which
    # is what lets a second run see a tree it still considers stable.
    # One pathspec at a time: git add fails outright when any pathspec in the
    # list matches nothing, and a source directory that has just been moved away
    # matches nothing.
    def stage(*paths)
      return unless git?

      paths.each do |path|
        system("git", "-C", @root.to_s, "add", "-A", "--", path,
               out: File::NULL, err: File::NULL)
      end
    end

    # Work git has not been told about, inside the directories this run touches.
    # Uncommitted changes to a Gemfile, or to anything else the migration cannot
    # affect, are none of oubliette's business.
    def unsettled_within(paths)
      porcelain.filter_map do |line|
        next unless line.start_with?("??") || line[1] != " "

        path = path_of(line)
        next unless paths.any? { |dir| touching?(path, dir) }

        path
      end.uniq
    end

    def path_of(line)
      line[3..].to_s.split(" -> ").last.delete_prefix('"').delete_suffix('"')
    end

    def touching?(path, dir)
      path == dir || path.start_with?("#{dir}/") || dir.start_with?(path.chomp("/"))
    end

    def porcelain
      return [] unless git?

      stdout, = Open3.capture2("git", "-C", @root.to_s, "status", "--porcelain")
      stdout.lines.map(&:chomp).reject(&:empty?).reject { |line| owned?(path_of(line)) }
    end

    # git reports a wholly untracked directory as the directory, so the first
    # run -- which creates test/oubliette inside a test/ that did not exist --
    # shows up as "?? test/". Look inside before calling that the developer's
    # uncommitted work.
    def owned?(path)
      return true if OWNED.any? { |owned| path == owned || path.start_with?("#{owned}/") }
      return false unless path.end_with?("/")

      files = @root.glob("#{path}**/*").select(&:file?)
      files.any? && files.all? { |file| owned?(file.relative_path_from(@root).to_s) }
    end
    private
      def collisions(source, target)
        source.children.flat_map do |child|
          destination = target.join(child.basename)
          if child.directory? && destination.directory?
            collisions(child, destination)
          elsif destination.exist? && !placeholder?(child)
            [ relative(destination) ]
          else
            []
          end
        end
      end

      def merge_into(source, target)
        source.children.each do |child|
          destination = target.join(child.basename)
          if child.directory? && destination.directory?
            merge_into(child, destination)
          elsif destination.exist?
            discard(child, destination)
          else
            git_mv(child, destination) || FileUtils.mv(child.to_s, destination.to_s)
          end
        end
        source.rmdir if source.directory? && source.children.empty?
      end

      # Two directories merging into one can each carry a git placeholder, and
      # one placeholder is as good as another -- refusing the whole migration
      # over a pair of empty .keep files would be absurd. Anything with content
      # is a real collision and stops the run.
      def discard(child, destination)
        raise Error, "refusing to overwrite #{relative(destination)}" unless placeholder?(child)

        git_rm(child) || child.delete
      end

    def placeholder?(path)
      PLACEHOLDERS.include?(path.basename.to_s) && path.file? && path.size.zero?
    end

      def git_rm(path)
        return false unless git?

        system("git", "-C", @root.to_s, "rm", "-q", "-f", "--", relative(path),
               out: File::NULL, err: File::NULL)
        !path.exist?
      end

      # git mv refuses a directory that holds untracked files, so its success is
      # confirmed against the filesystem rather than its exit status, and a
      # plain move finishes the job whenever it declines.
      def git_mv(source, target)
        return false unless git?

        system("git", "-C", @root.to_s, "mv", relative(source), relative(target),
               out: File::NULL, err: File::NULL)
        target.exist? && !source.exist?
      end

      def relative(path) = Pathname.new(path).relative_path_from(@root).to_s

      # Moving test/javascript/jest out of test/javascript leaves the parent
      # standing and empty. Left there it is found again on the next run, and
      # the catalog -- which knows test/javascript as jest's default home --
      # proposes folding it into its own child. Take it away with its contents.
      def prune_empty_ancestors(from)
        dir = @root.join(from).parent

        while dir.to_s.start_with?(@root.to_s) && dir != @root && dir.directory? && dir.children.empty?
          break if @protected.include?(relative(dir))

          dir.rmdir
          dir = dir.parent
        end
      end

      def relative_ruby_files(source)
        source.glob("**/*.{rb,rake}").map { |file| file.relative_path_from(source).to_s }
      end
  end
end
