# frozen_string_literal: true

require "json"
require "pathname"
require_relative "catalog"

module Oubliette
  # Works out which test frameworks a project actually uses, from its Gemfile,
  # its Gemfile.lock, its package.json, and the directories already on disk.
  class Detector
    # `tier` records how oubliette knows about a framework, which is not the
    # same as whether it is there. A gem you put in your Gemfile is a decision;
    # one that arrived through Rails is a fact about your dependency graph; a
    # directory with no gem behind it is an inference.
    Detection = Data.define(:key, :label, :ecosystem, :evidence, :tier, :moves, :config)

    TIERS = %i[declared locked disk].freeze

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
      @gems ||= (declared_gems + locked_gems).uniq
    end

    # Named in the Gemfile: someone chose this.
    def declared_gems
      @declared_gems ||= gemfile_gems
    end

    # In the lockfile only, so it arrived as somebody else's dependency.
    def locked_gems
      @locked_gems ||= lockfile_gems - gemfile_gems
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
          tier: tier_for(evidence),
          moves: entry[:moves],
          config: entry[:config]
        )
      end

      # The Gemfile and the lockfile were reported as one thing, so a gem that
      # only ever arrived through Rails was described as one you had chosen.
      def evidence_for(entry)
        declared = (entry[:gems] || []) & declared_gems
        locked = (entry[:gems] || []) & locked_gems
        installed = (entry[:packages] || []) & packages
        present = (entry[:paths] || []).select { |path| @root.join(path).directory? }

        found = []
        found << "Gemfile: #{declared.join(', ')}" if declared.any?
        found << "Gemfile.lock: #{locked.join(', ')}" if locked.any?
        found << "package.json: #{installed.join(', ')}" if installed.any?
        found << "on disk: #{present.join(', ')}" if present.any?
        found
      end

      def tier_for(evidence)
        return :declared if evidence.any? { |line| line.start_with?("Gemfile:", "package.json:") }
        return :locked if evidence.any? { |line| line.start_with?("Gemfile.lock:") }

        :disk
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
