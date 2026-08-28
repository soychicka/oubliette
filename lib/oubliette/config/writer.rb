# frozen_string_literal: true

require "fileutils"
require "pathname"

module Oubliette
  module Config
    # Base for the writers that rewrite a framework's own config file so its
    # default command finds the relocated directories.
    #
    # Every writer backs the original file up before touching it, because the
    # formats involved (.rspec in particular) cannot carry a comment marker to
    # delimit a managed region. Restoring the backup is therefore the whole of
    # rollback.
    class Writer
      BACKUP_DIR = ".oubliette/backups"
      ABSENT = "oubliette:file-did-not-exist"

      class << self
        def registry
          @registry ||= {}
        end

        def register(name)
          Writer.registry[name] = self
        end

        def for(name)
          Writer.registry[name]
        end

        def build(name, root, manifest, **options)
          klass = Writer.for(name)
          klass&.new(root, manifest, **options)
        end
      end

      def initialize(root, manifest, dry_run: false, logger: nil)
        @root = Pathname.new(root)
        @manifest = manifest
        @dry_run = dry_run
        @log = logger || ->(line) { puts line }
      end

      def filename
        raise NotImplementedError
      end

      # Returns nil when the framework's directories are missing from both the
      # old and the new location, which disables the config rather than pointing
      # it at a path that is not there.
      def render
        raise NotImplementedError
      end

      def apply
        return :skipped if filename.nil?

        contents = render
        if contents.nil?
          @log.call("  #{filename}: skipped, nothing to point at")
          return :skipped
        end

        target = @root.join(filename)
        return :unchanged if target.file? && target.read == contents

        @log.call("  #{filename}: rewritten")
        return :written if @dry_run

        back_up(target)
        FileUtils.mkdir_p(target.dirname)
        target.write(contents)
        :written
      end

      def revert
        return :unchanged if filename.nil?

        target = @root.join(filename)
        backup = backup_path
        return :unchanged unless backup.file?

        @log.call("  #{filename}: restored")
        return :restored if @dry_run

        saved = backup.read
        if saved == ABSENT
          target.delete if target.exist?
        else
          target.write(saved)
        end
        backup.delete
        :restored
      end

      private

      attr_reader :root, :manifest

      def destination(key)
        @manifest.destination(key)
      end

      def back_up(target)
        backup = backup_path
        return if backup.file?

        FileUtils.mkdir_p(backup.dirname)
        backup.write(target.file? ? target.read : ABSENT)
      end

      def backup_path
        @root.join(BACKUP_DIR, filename.gsub("/", "__"))
      end
    end
  end
end
