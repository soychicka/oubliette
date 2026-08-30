# frozen_string_literal: true

require "fileutils"
require_relative "config/managed_block"
require_relative "notice"

module Oubliette
  # Offers to make the stale-reference edits, rather than leaving them as
  # homework.
  #
  # Oubliette already knows what each line should say -- the fix is the same path
  # substitution that rewrites cucumber.yml -- so the only real question is
  # whether the developer wants it touching application code, which is asked
  # rather than assumed.
  class Repair
    SUFFIX = ".bak"

    def initialize(root, findings, out: $stdout, input: $stdin)
      @root = Pathname.new(root)
      @findings = findings.select(&:fixable?)
      @out = out
      @input = input
    end

    def offer
      code, comments = @findings.partition { |finding| !finding.comment? }
      return :nothing if code.empty?

      show(code, comments)
      return :manual unless interactive?

      accepted? ? :easy : :manual
    end

    def apply(files = nil)
      chosen = files ? @findings.select { |f| files.include?(f.file) } : @findings.reject(&:comment?)

      chosen.group_by(&:file).map do |file, findings|
        back_up(file)
        rewrite(file, findings)
        file
      end
    end
    private
      def show(code, comments)
        @out.puts
        @out.puts("some files still name the old locations. oubliette does not change")
        @out.puts("application code on its own.")
        @out.puts
        @out.puts(Notice.rule)
        code.group_by(&:file).each { |file, group| show_file(file, group) }
        @out.puts
        @out.puts(Notice.rule)
        mention(comments)
        @out.puts
        @out.puts(options(code))
      end

      def show_file(file, group)
        @out.puts
        @out.puts("  #{file}")
        group.each do |finding|
          @out.puts(format("  %5d   %s", finding.line, finding.text))
          @out.puts(format("          ->  %s", finding.suggestion))
        end
      end

      def mention(comments)
        return if comments.empty?

        @out.puts
        @out.puts("#{comments.length} more mention an old path inside a comment. Those are left alone:")
        @out.puts("a note about what a generator does is not a statement about your layout.")
      end

      def options(code)
        files = code.map(&:file).uniq

        <<~TEXT
          you can update these lines yourself -- but you'll have to run the test suite
          yourself for a sanity check once the files are updated.

          --OR--

           I'll do the following for you:

            1. create backups of the current files at #{files.map { |f| f + SUFFIX }.join(', ')}
            2. update the files for you directly, preserving the original lines as comments
            3. run the entire test suite to verify everything works (this may be slow,
               depending on the length of your test suite)
        TEXT
      end

      def accepted?
        @out.print("how do you want to roll?  [ 1: manual | 2: easy - <default> ]: ")
        @out.flush if @out.respond_to?(:flush)
        reply = @input.gets.to_s.strip.downcase

        reply.empty? || reply.start_with?("2", "e")
      end

      def interactive?
        @input.respond_to?(:tty?) && @input.tty?
      end

      # Both nets. The comment keeps the original where you are reading and lets
      # rollback reverse it; the .bak is a whole file you can move back without
      # parsing anything, which application code earns over configuration.
      def back_up(file)
        source = @root.join(file)
        FileUtils.cp(source.to_s, "#{source}#{SUFFIX}")
      end

      def rewrite(file, findings)
        target = @root.join(file)
        wanted = findings.to_h { |finding| [ finding.line, finding ] }
        comment = file.end_with?(".js", ".ts") ? "//" : "#"

        rewritten = target.read(encoding: "UTF-8").scrub.lines.each_with_index.map do |line, index|
          finding = wanted[index + 1]
          next line if finding.nil?

          Config::ManagedBlock.wrap(
            reason: [ "this named a directory that moved. Your line is kept below, commented out." ],
            original: [ line.chomp ],
            replacement: [ line.chomp.sub(finding.text, finding.suggestion) ],
            comment: comment
          )
        end

        target.write(rewritten.join)
      end
  end
end
