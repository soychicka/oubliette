# frozen_string_literal: true

require "fileutils"
require_relative "ledger"
require_relative "paper"
require_relative "manifest"
require_relative "notice"
require_relative "runner"
require_relative "runs"

module Oubliette
  # Puts everything back and leaves no trace of oubliette -- except the things
  # that are not oubliette's to remove.
  #
  # Only a file whose entire content oubliette wrote, and which nobody has
  # touched since, is deleted. That is checked by regenerating the file and
  # comparing, rather than by trusting a record: if it still says exactly what
  # oubliette would say, nobody has been in it. Everything else is listed, and
  # the listing says what was removed as well as what was left, because
  # "deliberately kept" and "forgotten" look identical otherwise.
  class Uninstall
    def initialize(root, out: $stdout, input: $stdin, force: false)
      @root = Pathname.new(root)
      @out = out
      @input = input
      @force = force
    end

    def call
      return :absent unless Manifest.exists_in?(@root)
      return :declined unless confirmed?

      Runner.new(@root, out: @out, input: @input, force: @force).rollback
      removed = remove_ours
      report(removed, kept)
      :done
    end
    private
      # No paths in the question: on a project of any size the list is a wall,
      # and the detail belongs in the report afterwards.
      def confirmed?
        return true unless interactive?

        @out.puts
        @out.puts("this puts every test directory back where it started, undoes the")
        @out.puts("configuration changes, and removes oubliette's own files.")
        @out.print("\nuninstall oubliette? [Y/n] ")
        @out.flush if @out.respond_to?(:flush)
        reply = @input.gets.to_s.strip.downcase

        reply.empty? || reply.start_with?("y")
      end

      def interactive? = @input.respond_to?(:tty?) && @input.tty?

      def remove_ours
        ours.select(&:file?).map do |path|
          relative = path.relative_path_from(@root).to_s
          path.delete
          relative
        end.tap { prune_empty }
      end

      # rollback.yml is the only file oubliette can be sure is entirely its
      # own once the rollback has finished. Guides are handled by the rollback
      # itself, which removes the untouched ones and leaves the rest.
      def ours = [ @root.join(Ledger::PATH) ]

      def kept
        [
          [ Manifest::PATH, "your configuration, edited by hand" ],
          [ Runs::PATH, "test history" ],
          [ "#{HOME}/history", "rotated test history" ]
        ].select { |path, _| @root.join(path).exist? } +
          modified_guides + backups + layout_spec + stale_output
      end

      # Coverage reports and screenshots were never moved, only pointed at a new
      # directory. Restoring the configuration sends the next run back to the
      # original path, which leaves the last run's output stranded where nothing
      # will overwrite it.
      def stale_output
        Manifest.load(@root).pairs.select(&:generated)
                .map { |pair| @root.join(pair.oubliette) }
                .select(&:directory?)
                .map { |path| [ path.relative_path_from(@root).to_s, "output from your last run, now stale" ] }
      rescue Error
        []
      end

      # Anything still here after the rollback is a guide somebody wrote in --
      # the rollback removes the untouched ones, and takes its own README and
      # recovery note with them.
      def modified_guides
        @root.glob("#{HOME}/*.md")
             .map { |path| path.relative_path_from(@root).to_s }
             .reject { |path| Paper.filenames.include?(path) }
             .map { |path| [ path, "a guide you have edited" ] }
      end

      def backups
        @root.glob("**/*#{Repair::SUFFIX}")
             .reject { |path| path.to_s.include?("/.git/") }
             .map { |path| [ path.relative_path_from(@root).to_s, "backup taken before a line was rewritten" ] }
      end

      def layout_spec
        @root.glob("**/oubliette_spec.rb")
             .map { |path| [ path.relative_path_from(@root).to_s, "the layout spec, which needs the gem" ] }
      end

      def prune_empty
        [ @root.join(SUPPORT), @root.join(HOME) ].each do |directory|
          directory.rmdir if directory.directory? && directory.children.empty?
        end
      end

      def report(removed, listed)
        @out.puts
        @out.puts("oubliette has put everything back.")

        unless listed.empty?
          @out.puts
          @out.puts(Notice.rule)
          @out.puts
          @out.puts("these are yours to remove or keep:")
          @out.puts
          width = listed.map { |path, _| path.length }.max
          listed.each { |path, why| @out.puts(format("  %-#{width}s   %s", path, why)) }
          @out.puts
          @out.puts(Notice.rule)
        end

        @out.puts
        @out.puts("removed automatically: #{removed.empty? ? 'nothing' : removed.join(', ')}")
        @out.puts
        @out.puts("remove `gem \"oubliette\"` from your Gemfile when you are ready.")
      end
  end
end
