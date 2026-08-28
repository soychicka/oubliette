# frozen_string_literal: true

require "json"
require "pathname"
require_relative "catalog"

module Oubliette
  # Works out which test frameworks a project actually uses, from its Gemfile,
  # its Gemfile.lock, its package.json, and the directories already on disk.
  class Detector
    Detection = Data.define(:key, :label, :ecosystem, :evidence, :moves, :config)

    def initialize(root)
      @root = Pathname.new(root)
    end

    def detections
      Catalog.entries.filter_map { |entry| detect(entry) }
    end

    # Directories that look like test trees but no catalog entry claimed.
    def strays(claimed)
      @root.children.select(&:directory?).filter_map do |child|
        name = child.basename.to_s
        next unless name.match?(Catalog::STRAY_PATTERN)
        next if name == Catalog::ROOT
        next if claimed.include?(name)

        name
      end.sort
    end

    def gems
      @gems ||= (gemfile_gems + lockfile_gems).uniq
    end

    def packages
      @packages ||= begin
        file = @root.join("package.json")
        if file.file?
          parsed = JSON.parse(file.read)
          %w[dependencies devDependencies peerDependencies].flat_map { |k| (parsed[k] || {}).keys }.uniq
        else
          []
        end
      rescue JSON::ParserError
        []
      end
    end
    private
      def detect(entry)
        evidence = evidence_for(entry)
        return nil if evidence.empty?

        Detection.new(
          key: entry[:key],
          label: entry[:label],
          ecosystem: entry[:ecosystem],
          evidence: evidence,
          moves: entry[:moves],
          config: entry[:config]
        )
      end

      def evidence_for(entry)
        found = []
        matched_gems = (entry[:gems] || []) & gems
        matched_packages = (entry[:packages] || []) & packages
        matched_paths = (entry[:paths] || []).select { |path| @root.join(path).directory? }

        found << "Gemfile: #{matched_gems.join(', ')}" if matched_gems.any?
        found << "package.json: #{matched_packages.join(', ')}" if matched_packages.any?
        found << "on disk: #{matched_paths.join(', ')}" if matched_paths.any?
        found
      end

      def gemfile_gems
        file = @root.join("Gemfile")
        return [] unless file.file?

        file.read.scan(/^\s*gem\s+["']([^"']+)["']/).flatten
      end

      def lockfile_gems
        file = @root.join("Gemfile.lock")
        return [] unless file.file?

        file.read.scan(/^\s{4}([a-zA-Z0-9_.\-]+) \(/).flatten
      end
  end
end
