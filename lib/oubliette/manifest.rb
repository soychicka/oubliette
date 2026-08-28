# frozen_string_literal: true

require "yaml"
require "pathname"
require_relative "detector"

module Oubliette
  # migrate.yml, in object form. The file on disk is the single source of truth
  # for both the move and the runtime configuration, so everything here is
  # careful to preserve whatever the user typed into it by hand: a sync adds
  # newly detected frameworks and refreshes evidence, and touches nothing else.
  class Manifest
    FILENAME = "migrate.yml"
    VERSION = 1

    Move = Data.define(:gem, :from, :to, :applied, :status) do
      def moved? = status == "moved"
      def missing? = status == "missing"
      def canonical? = from == to
      def current = applied || from
    end

    attr_reader :root, :path, :data

    def self.path_in(root) = Pathname.new(root).join(FILENAME)

    def self.exists_in?(root) = path_in(root).file?

    def self.load(root)
      file = path_in(root)
      raise Error, "#{file} not found -- run `rake oubliette:prepare` first" unless file.file?

      new(root, YAML.safe_load(file.read, aliases: false) || {})
    end

    # Builds a manifest from detection, merging over an existing file when one
    # is present so hand-edited targets survive a sync.
    def self.build(root)
      existing = exists_in?(root) ? load(root) : new(root, {})
      existing.sync!
      existing
    end

    def initialize(root, data)
      @root = Pathname.new(root)
      @path = self.class.path_in(root)
      @data = data
      @data["version"] ||= VERSION
      @data["root"] ||= Catalog::ROOT
      @data["gems"] ||= {}
      @data["strays"] ||= {}
    end

    def sync!
      detector = Detector.new(@root)
      detections = detector.detections

      detections.each { |detection| merge_detection(detection) }
      merge_strays(detector.strays(claimed_top_levels))
      refresh_statuses!
      self
    end

    def gems = @data["gems"].keys

    def enabled?(key) = @data["gems"].dig(key, "enabled") == true

    def config_writers(key)
      Array(@data["gems"].dig(key, "config")).map(&:to_sym)
    end

    # Every move, deepest source first, so a nested directory is extracted
    # before its parent is relocated out from under it.
    def moves(only: nil)
      @data["gems"].flat_map do |key, gem|
        next [] unless gem["enabled"]
        next [] if only && key != only

        Array(gem["paths"]).map do |entry|
          Move.new(
            gem: key,
            from: entry["from"],
            to: entry["to"],
            applied: entry["applied"],
            status: entry["status"]
          )
        end
      end.sort_by { |move| [ -move.from.count("/"), move.from ] }
    end

    def record!(move, applied:, status:)
      entry = raw_entry(move.gem, move.from)
      entry["applied"] = applied
      entry["status"] = status
      self
    end

    def refresh_statuses!
      @data["gems"].each_value do |gem|
        Array(gem["paths"]).each do |entry|
          entry["status"] = status_for(entry)
        end
      end
      self
    end

    def missing
      moves.select(&:missing?)
    end

    # Where a framework's assets live once oubliette is done with them. Returns
    # nil when every one of its paths is missing, which is the signal for the
    # config writers to disable themselves rather than point at nothing.
    def destination(key)
      destinations(key).first
    end

    def destinations(key)
      moves(only: key).reject(&:missing?).map { |move| move.applied || move.to }.uniq
    end

    def save!
      @path.write(render)
      self
    end

    def render
      header = <<~YAML
        # migrate.yml -- oubliette's source of truth.
        #
        # Edit `to:` to send a directory somewhere else, flip `enabled:` to skip a
        # framework, then rerun `rake oubliette`. A target that changes after a move
        # is returned to its original location first, then relocated, so the config
        # only ever describes one hop.
        #
        #   status: pending   not moved yet
        #           moved     living at `applied`
        #           missing   absent from both `from` and `to` -- config is disabled
        #           canonical from and to are the same, nothing to do
      YAML
      header + @data.to_yaml.sub(/\A---\n/, "")
    end
    private
      def merge_detection(detection)
        gem = (@data["gems"][detection.key] ||= {
          "label" => detection.label,
          "ecosystem" => detection.ecosystem.to_s,
          "enabled" => true,
          "config" => detection.config.map(&:to_s),
          "paths" => []
        })
        gem["evidence"] |= detection.evidence

        detection.moves.each do |from, to|
          next if gem["paths"].any? { |entry| entry["from"] == from }
          next unless relevant?(from, to)

          gem["paths"] << { "from" => from, "to" => to, "applied" => nil, "status" => "pending" }
        end
      end

      # A catalog default only earns a line in migrate.yml if it has something to
      # describe: the source exists, or the move has already happened.
      #
      # The nesting guard matters on a sync. test/javascript is jest's default
      # home and test/javascript/jest is where it ends up, so once the move has
      # happened the parent exists again and the same rule would otherwise
      # propose folding it into its own child, forever.
      def relevant?(from, to)
        return false if to.start_with?("#{from}/") && @root.join(to).exist?
        return false if recorded_targets.include?(from)

        @root.join(from).exist?
      end

      # A destination oubliette already filled is not a source for anything.
      # Without this a sync would keep proposing to fold test/support into
      # test/support, and test/factories into test/data/factories, every time it
      # ran after the first.
      def recorded_targets
        @data["gems"].values.flat_map { |gem| Array(gem["paths"]).map { |entry| entry["to"] } }.uniq
      end

      def merge_strays(names)
        names.each do |name|
          next if @data["strays"].key?(name)

          @data["strays"][name] = {
            "enabled" => false,
            "note" => "unclaimed test-shaped directory -- set enabled: true and edit `to:` to include it",
            "paths" => [ { "from" => name, "to" => "#{@data['root']}/#{name}", "applied" => nil, "status" => "pending" } ]
          }
        end

        @data["strays"].each do |name, stray|
          next unless stray["enabled"]
          next if @data["gems"].key?(name)

          @data["gems"][name] = stray.merge("label" => name, "ecosystem" => "project", "config" => [])
        end
      end

      def claimed_top_levels
        Catalog.entries.flat_map { |entry| entry[:moves].keys }.map { |path| path.split("/").first }.uniq
      end

      def raw_entry(key, from)
        Array(@data["gems"].dig(key, "paths")).find { |entry| entry["from"] == from } ||
          raise(Error, "no path #{from.inspect} recorded for #{key}")
      end

      def status_for(entry)
        return "canonical" if entry["from"] == entry["to"]

        current = entry["applied"]
        return "moved" if current && @root.join(current).exist?

        if @root.join(entry["to"]).exist? && !@root.join(entry["from"]).exist?
          entry["applied"] ||= entry["to"]
          return "moved"
        end

        return "pending" if @root.join(entry["from"]).exist?

        "missing"
      end
  end
end
