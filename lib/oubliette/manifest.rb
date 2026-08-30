# frozen_string_literal: true

require "fileutils"
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
    PATH = "#{HOME}/#{FILENAME}"
    VERSION = 1

    attr_reader :root, :path, :data
    attr_writer :ledger

    def self.path_in(root) = Pathname.new(root).join(PATH)

    def self.exists_in?(root)
      adopt_legacy(root)
      path_in(root).file?
    end

    # Earlier versions kept this at the project root. Move it rather than
    # ignoring it, so a project that migrated with an older gem keeps its
    # answers instead of being asked everything again.
    def self.adopt_legacy(root)
      legacy = Pathname.new(root).join(FILENAME)
      target = path_in(root)
      return if !legacy.file? || target.file?

      FileUtils.mkdir_p(target.dirname)
      FileUtils.mv(legacy.to_s, target.to_s)
    end

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

    # Frameworks whose directories oubliette moves but whose configuration it
    # will not touch, because the paths live in a javascript module rather than
    # in JSON. Only reported when the config file is really there.
    ManualConfig = Data.define(:gem, :file, :pairs, :settings)

    def manual_configs
      @data["gems"].flat_map do |key, gem|
        next [] unless gem["enabled"] && config_writers(key).include?(:manual)

        moving = pairs(only: key).reject { |pair| pair.missing? || pair.canonical? }
        next [] if moving.empty?

        Array(Catalog.find(key)&.dig(:manual_config))
          .select { |file| @root.join(file).file? }
          .map do |file|
            ManualConfig.new(
              gem: key,
              file: file,
              pairs: moving,
              settings: Array(Catalog.find(key)&.dig(:manual_settings))
            )
          end
      end
    end

    def pending = pairs.select(&:pending?)

    # Where a framework's assets are meant to live. nil when every one of its
    # directories is missing from both locations, which is the signal for the
    # config writers to disable themselves rather than point at nothing.
    def destination(key) = destinations(key).first

    def destinations(key)
      pairs(only: key).reject(&:missing?).map(&:oubliette).uniq
    end

    # Where a framework's directories actually are, which is a different
    # question from where migrate.yml wants them and the only one worth asking
    # at runtime. After a rollback the answer is the origin, whatever target
    # migrate.yml still names.
    def location(key) = locations(key).first

    def locations(key)
      live = ledger.pairs(only: key).map(&:current).select { |path| @root.join(path).exist? }
      live.any? ? live.uniq : destinations(key)
    end

    # Throws hand-edited targets away and puts oubliette's own defaults back.
    def reset_targets!(only: nil)
      each_raw_pair(only: only) do |key, path|
        default = default_target(key, path["origin"])
        path["oubliette"] = default if default
      end
      self
    end

    def save!
      FileUtils.mkdir_p(@path.dirname)
      @path.write(render)
      ledger.remember!(gems).save!
      self
    end

    def render
      <<~YAML + @data.to_yaml.sub(/\A---\n/, "")
        # migrate.yml -- where you want each framework's directories to live.
        #
        # Edit `oubliette:` to send a directory somewhere else, flip `enabled:`
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
        oubliette = path["oubliette"]
        current = ledger.current(key, origin) || origin

        generated = generated?(key, origin)

        Pair.new(
          gem: key,
          origin: origin,
          oubliette: oubliette,
          current: current,
          status: generated ? :configured : status_for(origin, oubliette, current),
          generated: generated
        )
      end

      def status_for(origin, oubliette, current)
        return :canonical if origin == oubliette
        return :settled if @root.join(oubliette).exist? && current == oubliette
        return :pending if @root.join(current).exist?
        return :settled if @root.join(oubliette).exist?
        # The destination is gone but the origin is back: something outside
        # oubliette reverted the move -- a git reset, most likely -- and this
        # needs migrating again rather than being reported as lost.
        return :pending if @root.join(origin).exist?

        :missing
      end

      def generated?(key, origin)
        Array(Catalog.find(key)&.dig(:generated)).include?(origin)
      end

      def merge_detection(detection)
        return if deleted?(detection.key)

        gem = (@data["gems"][detection.key] ||= {
          "enabled" => true,
          "config" => detection.config.map(&:to_s),
          "paths" => []
        })

        detection.moves.each do |origin, oubliette|
          next if Array(gem["paths"]).any? { |path| path["origin"] == origin }
          next unless relevant?(detection.key, origin, oubliette)

          gem["paths"] << { "origin" => origin, "oubliette" => oubliette }
        end
      end

      # A framework oubliette has written down before and that is no longer in
      # the file was taken out on purpose. Leave it out.
      def deleted?(key)
        !@data["gems"].key?(key) && ledger.known?(key)
      end

      # A catalog default earns a line only when the directory is really there
      # and oubliette has not already dealt with it. The second guard is what
      # makes a sync idempotent: a destination oubliette has filled is not a
      # source for anything. Without it, spec/support having become test/support
      # would have the catalog propose test/support -> test/support on the next
      # run, and test/javascript -> test/javascript/jest would fold jest into
      # its own child, forever.
      def relevant?(key, origin, oubliette)
        return false if nests_inside_itself?(origin, oubliette)
        return false if empty_directory?(origin)
        return false if ledger.current(key, origin)
        return false if ledger.pairs.any? { |pair|
          pair.current == origin || pair.current.to_s.start_with?("#{origin}/")
        }

        @root.join(origin).exist?
      end

      # test/javascript is jest's default home and test/javascript/jest is where
      # it ends up, so once the move has happened the parent exists again and
      # the catalog would propose folding it into its own child. This is checked
      # structurally rather than against rollback.yml, because a project whose
      # ledger has been lost still must not eat its own directory.
      # An empty directory has nothing to move, and proposing it only invites
      # the kind of trouble a leftover parent causes.
      # FNM_DOTMATCH because a directory holding nothing but a .keep is not
      # empty: the placeholder is a tracked file, and moving it is the point.
      def empty_directory?(origin)
        dir = @root.join(origin)
        dir.directory? && dir.glob("**/*", File::FNM_DOTMATCH).none?(&:file?)
      end

      def nests_inside_itself?(origin, oubliette)
        oubliette.start_with?("#{origin}/") && @root.join(oubliette).exist?
      end

      def merge_strays(names)
        names.each do |name|
          next if @data["strays"].key?(name) || @data["gems"].key?(name)

          @data["strays"][name] = {
            "enabled" => false,
            "note" => "unclaimed test-shaped directory -- set enabled: true to include it",
            "paths" => [ { "origin" => name, "oubliette" => "#{@data['root']}/#{name}" } ]
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
          @data["strays"].dig(key, "paths", 0, "oubliette")
      end
  end
end
