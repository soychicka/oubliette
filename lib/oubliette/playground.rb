# frozen_string_literal: true

require "pathname"
require_relative "notice"

module Oubliette
  # Builds the demonstration application, so that trying oubliette out never
  # means trying it on something you care about.
  #
  # The heavy lifting is a shell script -- `rails new`, `bundle install`, npm,
  # a scaffold per framework -- and it stays a shell script. This is the front
  # door: it works out where the application should go, makes sure an existing
  # one is not flattened by accident, and hands over.
  class Playground
    SCRIPT = "bin/playground"
    DEFAULT_NAME = "oubliette-playground"

    class << self
      def gem_root = Pathname.new(File.expand_path("../..", __dir__))

      def script = gem_root.join(SCRIPT)
    end

    def initialize(root, target: nil, out: $stdout, input: $stdin)
      @root = Pathname.new(root)
      @target = target
      @out = out
      @input = input
    end

    def call
      return :unavailable unless available?

      target = @target ? Pathname.new(@target).expand_path : ask_where
      return :declined if target.nil?
      return :declined if target.exist? && !overwrite?(target)

      build(target)
    end
    private
      def available?
        return true if self.class.script.executable?

        @out.puts("\n#{SCRIPT} is not in this copy of the gem, so there is nothing to build.")
        false
      end

      # Beside the project rather than inside it: a second Rails application
      # under this one would be picked up by every glob in the parent.
      def default_target = @root.parent.join(DEFAULT_NAME)

      def ask_where
        suggestion = default_target
        return suggestion unless interactive?

        @out.puts
        @out.puts("oubliette will build a small rails application with one passing test per")
        @out.puts("framework it knows about, so there is something safe to run it against.")
        @out.print("\nwhere should it go? [#{suggestion}] ")
        flush
        reply = @input.gets.to_s.strip

        reply.empty? ? suggestion : Pathname.new(reply).expand_path
      end

      # `rm -rf` on a directory somebody named by hand deserves more than a
      # keystroke, so this is the one prompt in oubliette that will not take y.
      def overwrite?(target)
        unless interactive?
          @out.puts(Notice.error("#{target} already exists.",
                                 "Building the playground would delete it. Remove it yourself, or run\n" \
                                 "the task where you can answer the prompt."))
          return false
        end

        @out.puts
        @out.puts("#{target} already exists, and building the playground deletes it first.")
        @out.print("\ntype YES to delete it and build: ")
        flush

        @input.gets.to_s.strip.casecmp?("YES")
      end

      def build(target)
        @out.puts
        @out.puts("building #{target}")
        @out.puts
        @out.puts(Notice.rule)
        ok = system(self.class.script.to_s, target.to_s)
        @out.puts(Notice.rule)
        @out.puts

        if ok
          @out.puts("the playground is ready. `cd #{target}`, then uncomment oubliette in the")
          @out.puts("Gemfile and `bundle install` when you want the rake tasks.")
          :built
        else
          @out.puts("#{SCRIPT} did not finish. Whatever it managed to build is at #{target}.")
          :failed
        end
      end

      def interactive? = @input.respond_to?(:tty?) && @input.tty?

      def flush
        @out.flush if @out.respond_to?(:flush)
      end
  end
end
