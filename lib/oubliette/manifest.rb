# frozen_string_literal: true

require "yaml"
require "pathname"
require_relative "detector"
require_relative "ledger"
require_relative "pair"

module Oubliette
  # migrate.yml: where you want each framework's directories to live.
  #
  # This is the file you edit. It says nothing about where anything came from or
  # where anything currently is -- that is rollback.yml's job -- so retargeting a
  # directory here can never cost the project the ability to put it back.
  class Manifest
    FILENAME = "migrate.yml"
    VERSION = 1

    attr_reader :root, :path, :data
    attr_writer :ledger

    def self.path_in(root) = Pathname.new(root).join(FILENAME)

    def self.exists_in?(root) = path_in(root).file?

    def self.load(root)
      file = path_in(root)
      raise Error, "#{file} not found -- run `rake oubliette:prepare` first" unless file.file?

      new(root, YAML.safe_load(file.read, aliases: false) || {})
    end

    def self.build(root)
      manifest = exists_in?(root) ? load(root) : new(root, {})
      manifest.sync!
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

    def ledger
      @ledger ||= Ledger.load(@root)
    end

    def sync!
      detector = Detector.new(@root)
      detector.detections.each { |detection| merge_detection(detection) }
      merge_strays(detector.strays(claimed_top_levels))
      self
    end

    def gems = @data["gems"].keys

    def enabled?(key) = @data["gems"].dig(key, "enabled") == true

    def config_writers(key)
      Array(@data["gems"].dig(key, "config")).map(&:to_sym)
    end

    # Deepest origin first, so a nested directory is extracted before its parent
    # is relocated out from under it.
    def pairs(only: nil)
      @data["gems"].flat_map do |key, gem|
        next [] unless gem["enabled"]
        next [] if only && key != only

        Array(gem["paths"]).map { |path| pair_for(key, path) }
      end.sort_by { |pair| [ -pair.origin.count("/"), pair.origin ] }
    end

    def missing = pairs.select(&:missing?)

    def pending = pairs.select(&:pending?)

    # Where a framework's assets are meant to live. nil when every one of its
    # directories is missing from both locations, which is the signal for the
    # config writers to disable themselves rather than point at nothing.
    def destination(key) = destinations(key).first

    def destinations(key)
      pairs(only: key).reject(&:missing?).map(&:oublietted).uniq
    end

    # Throws hand-edited targets away and puts oubliette's own defaults back.
    def reset_targets!(only: nil)
      each_raw_pair(only: only) do |key, path|
        default = default_target(key, path["origin"])
        path["oublietted"] = default if default
      end
      self
    end

    def save!
      @path.write(render)
      self
    end

    def render
      <<~YAML + @data.to_yaml.sub(/\A---\n/, "")
        # migrate.yml -- where you want each framework's directories to live.
        #
        # Edit `oublietted:` to send a directory somewhere else, flip `enabled:`
        # to skip a framework, then rerun `rake oubliette`. Only the entries that
        # differ from rollback.yml are touched, so a rerun is cheap.
        #
        #   rake oubliette              move whatever changed here
        #   rake oubliette:reset        put oubliette's own targets back, and move
        #   rake oubliette:rollback     return everything to its `origin`
      YAML
    end
    private
      def pair_for(key, path)
        origin = path["origin"]
        oublietted = path["oublietted"]
        current = ledger.current(key, origin) || origin

        Pair.new(
          gem: key,
          origin: origin,
          oublietted: oublietted,
          current: current,
          status: status_for(origin, oublietted, current)
        )
      end

      def status_for(origin, oublietted, current)
        return :canonical if origin == oublietted
        return @root.join(oublietted).exist? ? :settled : :missing if current == oublietted
        return :pending if @root.join(current).exist?
        return :settled if @root.join(oublietted).exist?

        :missing
      end

      def merge_detection(detection)
        gem = (@data["gems"][detection.key] ||= {
          "enabled" => true,
          "config" => detection.config.map(&:to_s),
          "paths" => []
        })

        detection.moves.each do |origin, oublietted|
          next if Array(gem["paths"]).any? { |path| path["origin"] == origin }
          next unless relevant?(detection.key, origin)

          gem["paths"] << { "origin" => origin, "oublietted" => oublietted }
        end
      end

      # A catalog default earns a line only when the directory is really there
      # and oubliette has not already dealt with it. The second guard is what
      # makes a sync idempotent: a destination oubliette has filled is not a
      # source for anything. Without it, spec/support having become test/support
      # would have the catalog propose test/support -> test/support on the next
      # run, and test/javascript -> test/javascript/jest would fold jest into
      # its own child, forever.
      def relevant?(key, origin)
        return false if ledger.current(key, origin)
        return false if ledger.pairs.any? { |pair|
          pair.current == origin || pair.current.to_s.start_with?("#{origin}/")
        }

        @root.join(origin).exist?
      end

      def merge_strays(names)
        names.each do |name|
          next if @data["strays"].key?(name) || @data["gems"].key?(name)

          @data["strays"][name] = {
            "enabled" => false,
            "note" => "unclaimed test-shaped directory -- set enabled: true to include it",
            "paths" => [ { "origin" => name, "oublietted" => "#{@data['root']}/#{name}" } ]
          }
        end

        @data["strays"].each do |name, stray|
          next unless stray["enabled"]
          next if @data["gems"].key?(name)

          @data["gems"][name] = stray.merge("config" => [])
        end
      end

      def claimed_top_levels
        Catalog.entries.flat_map { |entry| entry[:moves].keys }
                       .map { |path| path.split("/").first }.uniq
      end

      def each_raw_pair(only: nil)
        @data["gems"].each do |key, gem|
          next if only && key != only

          Array(gem["paths"]).each { |path| yield key, path }
        end
      end

      def default_target(key, origin)
        Catalog.find(key)&.dig(:moves, origin) ||
          @data["strays"].dig(key, "paths", 0, "oublietted")
      end
  end
end
