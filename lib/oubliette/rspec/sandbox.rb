# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "stringio"
require "tmpdir"

module Oubliette
  module RSpec
    # A throwaway project on disk, so the specs exercise the real mover, the
    # real config writers and real git rather than a stack of doubles.
    #
    # It is deliberately free of any dependency on Rails or on the host
    # application, which is what lets the same specs run inside an app's suite
    # and standalone when that app's suite is broken.
    class Sandbox
      attr_reader :root, :output

      def self.create(**options)
        sandbox = new(**options)
        sandbox.build
        sandbox
      end

      def initialize(gems: [], packages: [], dirs: [], files: {}, git: true)
        @gems = gems
        @packages = packages
        @dirs = dirs
        @files = files
        @git = git
        @root = Pathname.new(Dir.mktmpdir("oubliette"))
        @output = StringIO.new
      end

      def build
        write_gemfile
        write_package_json
        @dirs.each { |dir| FileUtils.mkdir_p(@root.join(dir)) }
        @dirs.each { |dir| touch("#{dir}/.keep") }
        @files.each { |path, contents| write(path, contents) }
        commit if @git
        self
      end

      # StringIO is not a tty, so a sandbox run proceeds without prompting unless
      # an example deliberately hands it something that claims to be one.
      def runner(dry_run: false, force: false, input: StringIO.new)
        Runner.new(@root, dry_run: dry_run, out: @output, input: input, force: force)
      end

      def run(dry_run: false, input: StringIO.new)
        runner(dry_run: dry_run, input: input).call
      end

      # An answer typed at a real prompt.
      def answering(text)
        io = StringIO.new(text)
        def io.tty? = true
        io
      end

      def manifest
        Manifest.load(@root)
      end

      # For examples that never ran a migration and so have no migrate.yml.
      def manifest_built
        Manifest.build(@root)
      end

      def exist?(path) = @root.join(path).exist?

      def read(path) = @root.join(path).read

      def write(path, contents)
        target = @root.join(path)
        FileUtils.mkdir_p(target.dirname)
        target.write(contents)
        target
      end

      def touch(path)
        target = @root.join(path)
        FileUtils.mkdir_p(target.dirname)
        FileUtils.touch(target)
        target
      end

      def log = @output.string

      def commit(message = "sandbox")
        return unless @git

        run_git("init", "-q")
        run_git("config", "user.email", "oubliette@example.com")
        run_git("config", "user.name", "oubliette")
        run_git("add", "-A")
        run_git("commit", "-q", "-m", message, "--allow-empty")
      end

      def destroy
        FileUtils.remove_entry(@root) if @root.exist?
      end
      private
        def write_gemfile
          return if @gems.empty?

          body = [ "source 'https://rubygems.org'" ] + @gems.map { |name| "gem '#{name}'" }
          write("Gemfile", "#{body.join("\n")}\n")
        end

        def write_package_json
          return if @packages.empty?

          write("package.json", "#{JSON.pretty_generate(
            "name" => "sandbox",
            "private" => true,
            "scripts" => { "test" => "jest spec/javascript" },
            "devDependencies" => @packages.to_h { |name| [ name, "*" ] }
          )}\n")
        end

        def run_git(*args)
          system("git", "-C", @root.to_s, *args, out: File::NULL, err: File::NULL)
        end
    end

    # Gives every example a `sandbox` of its own and removes the temporary tree
    # afterwards, whether the example passed or not.
    module SandboxHelpers
      def self.open = @open ||= []

      def self.cleanup!
        open.each(&:destroy)
        open.clear
      end

      def sandbox(**options)
        @sandbox ||= Sandbox.create(**options).tap { |built| SandboxHelpers.open << built }
      end

      def new_sandbox(**options)
        Sandbox.create(**options).tap { |built| SandboxHelpers.open << built }
      end
    end
  end
end
