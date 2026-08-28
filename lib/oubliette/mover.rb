# frozen_string_literal: true

require "fileutils"
require "open3"
require "pathname"
require_relative "manifest"
require_relative "config/writer"
require_relative "requires"

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

    def relocate(from, to)
      source = @root.join(from)
      target = @root.join(to)
      @log.call("  #{from} -> #{to}")
      return if @dry_run

      # Collected before the move: a merge into a shared destination must not
      # repair a neighbour's files as though they had come from here.
      ruby_files = source.directory? ? relative_ruby_files(source) : []

      raise Error, "#{from} does not exist" unless source.exist?
      raise Error, "#{to} exists and is a file" if target.file?

      if target.directory?
        merge_into(source, target)
      else
        FileUtils.mkdir_p(target.dirname)
        git_mv(source, target) || FileUtils.mv(source.to_s, target.to_s)
      end

      repaired = Requires.new(@root).repair(from: from, to: to, files: ruby_files)
      repaired.each { |file| @log.call("    fixed require_relative in #{file}") }
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
    OWNED = [ Manifest::FILENAME, Config::Writer::BACKUP_DIR.split("/").first ].freeze

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

    def porcelain
      return [] unless git?

      stdout, = Open3.capture2("git", "-C", @root.to_s, "status", "--porcelain")
      stdout.lines.map(&:chomp).reject(&:empty?).reject do |line|
        path = line[3..].to_s.split(" -> ").last.delete_prefix('"').delete_suffix('"')
        OWNED.any? { |owned| path == owned || path.start_with?("#{owned}/") }
      end
    end
    private
      def merge_into(source, target)
        source.children.each do |child|
          destination = target.join(child.basename)
          if child.directory? && destination.directory?
            merge_into(child, destination)
          elsif destination.exist?
            raise Error, "refusing to overwrite #{relative(destination)}"
          else
            git_mv(child, destination) || FileUtils.mv(child.to_s, destination.to_s)
          end
        end
        source.rmdir if source.children.empty?
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

      def relative_ruby_files(source)
        source.glob("**/*.{rb,rake}").map { |file| file.relative_path_from(source).to_s }
      end
  end
end
