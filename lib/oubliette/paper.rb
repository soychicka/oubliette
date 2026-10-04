# frozen_string_literal: true

require "fileutils"
require "pathname"
require_relative "notice"

module Oubliette
  # A document oubliette writes for the developer and owns outright.
  #
  # Unlike a config file, which is edited in place around whatever else is in
  # it, a paper is regenerated from scratch on every run. That is the whole
  # point of it -- a recovery note that has drifted from where the directories
  # actually are is worse than no note at all -- and it is why each one says so
  # at the top rather than letting somebody find out by losing an edit.
  #
  # Papers exist only while something is displaced. Once everything is home
  # there is nothing to explain and nothing to recover from, so they go.
  class Paper
    def self.kinds = [ Paper::Readme, Paper::Recovery ]

    # So that anything scanning this directory for guides can tell oubliette's
    # own two documents apart from the notes it leaves beside a config file.
    def self.filenames = kinds.map { |kind| kind::FILENAME }

    def self.refresh(root, ledger, out: nil)
      kinds.map do |kind|
        kind.new(root, ledger, out: out).refresh
      end
    end

    def initialize(root, ledger, out: nil)
      @root = Pathname.new(root)
      @ledger = ledger
      @out = out
    end

    def filename = raise NotImplementedError

    def render = raise NotImplementedError

    def path = @root.join(filename)

    def refresh
      displaced.empty? ? remove : write
    end
    private
      attr_reader :root, :ledger

      def displaced = @displaced ||= @ledger.pairs.reject { |pair| pair.origin == pair.current }

      def write
        contents = render
        return :unchanged if path.file? && Oubliette.read(path) == contents

        FileUtils.mkdir_p(path.dirname)
        path.write(contents)
        @out&.puts("  #{filename}: written")
        :written
      end

      def remove
        return :unchanged unless path.file?

        path.delete
        @out&.puts("  #{filename}: removed, nothing is displaced any more")
        :removed
      end

      # A markdown table wide enough to line up, so a long list of paths reads
      # as a column of data rather than as prose the reader has to parse.
      def table(rows, headers)
        width = ([ headers ] + rows).transpose.map { |column| column.map(&:length).max }
        lines = [ row(headers, width), row(width.map { |n| "-" * n }, width) ]
        lines += rows.map { |cells| row(cells, width) }
        lines.join("\n")
      end

      def row(cells, width)
        "| #{cells.each_with_index.map { |cell, index| cell.ljust(width[index]) }.join(' | ')} |"
      end
  end
end
