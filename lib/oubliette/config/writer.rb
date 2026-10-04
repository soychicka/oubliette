# frozen_string_literal: true

require "fileutils"
require "pathname"
require_relative "managed_block"
require_relative "../text"

module Oubliette
  module Config
    # Base for the writers that tell a framework where its directories went.
    #
    # No writer ever replaces a file wholesale. Each one reads what is on disk
    # now -- not a snapshot taken before the first migration -- and changes only
    # the lines it is responsible for, leaving the developer's own edits in
    # place whether they were made before the move or long after it.
    class Writer
      class << self
        def registry = @registry ||= {}

        def register(name) = Writer.registry[name] = self

        def for(name) = Writer.registry[name]

        def build(name, root, manifest, **options)
          Writer.for(name)&.new(root, manifest, **options)
        end
      end

      def initialize(root, manifest, dry_run: false, logger: nil)
        @root = Pathname.new(root)
        @manifest = manifest
        @dry_run = dry_run
        @log = logger || ->(line) { puts line }
      end

      def filename = raise NotImplementedError

      # Returns the new contents given what is on disk, or nil to do nothing.
      def render(_current) = raise NotImplementedError

      def apply
        return :skipped if filename.nil?

        current = read
        updated = render(current)
        if updated.nil?
          @log.call(Text.t("writer.skipped", file: filename))
          return :skipped
        end
        return :unchanged if updated == current

        # Both keys spelled out rather than computed: the suite greps for
        # `Text.t("...")` to prove the locale file and the code agree, and a key
        # assembled at runtime is a key nobody can find.
        if current.nil?
          @log.call(Text.t("writer.written", file: filename))
        else
          @log.call(Text.t("writer.updated", file: filename))
        end
        write(updated)
        :written
      end

      def revert
        return :unchanged if filename.nil?

        current = read
        return :unchanged if current.nil?

        updated = restore(current)
        return :unchanged if updated == current

        if updated.strip.empty?
          @log.call(Text.t("writer.removed", file: filename))
          remove
        else
          @log.call(Text.t("writer.restored", file: filename))
          write(updated)
        end
        :restored
      end
      private
        attr_reader :root, :manifest

        # Undoing an edit is uncommenting what was commented out. Anything the
        # developer added since is outside the block and simply passes through.
        def restore(current) = ManagedBlock.unwrap(current)

        def destination(key) = @manifest.destination(key)

        def read
          target = @root.join(filename)
          target.file? ? Oubliette.read(target) : nil
        end

        def write(contents)
          return if @dry_run

          target = @root.join(filename)
          FileUtils.mkdir_p(target.dirname)
          target.write(contents)
        end

        def remove
          return if @dry_run

          target = @root.join(filename)
          target.delete if target.exist?
        end
    end
  end
end
