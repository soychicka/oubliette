# frozen_string_literal: true

require "yaml"
require "pathname"
require_relative "pair"

module Oubliette
  # rollback.yml: where each directory started, and where it is now.
  #
  # This file belongs to oubliette, not to the user. migrate.yml can be edited
  # freely -- retargeted, reordered, pruned -- without ever costing the project
  # the ability to put a directory back exactly where its framework expects it,
  # because the original location is recorded here and never rewritten.
  class Ledger
    FILENAME = "rollback.yml"
    VERSION = 1

    attr_reader :root, :path, :data

    def self.path_in(root) = Pathname.new(root).join(FILENAME)

    def self.exists_in?(root) = path_in(root).file?

    def self.load(root)
      file = path_in(root)
      new(root, file.file? ? (YAML.safe_load(file.read, aliases: false) || {}) : {})
    end

    def initialize(root, data)
      @root = Pathname.new(root)
      @path = self.class.path_in(root)
      @data = data
      @data["version"] ||= VERSION
      @data["gems"] ||= {}
    end

    # Where this directory is right now, or nil if oubliette has never moved it.
    def current(gem, origin)
      entry(gem, origin)&.fetch("oublietted", nil)
    end

    def record!(gem, origin, oublietted)
      found = entry(gem, origin)
      if found
        found["oublietted"] = oublietted
      else
        paths_for(gem) << { "origin" => origin, "oublietted" => oublietted }
      end
      self
    end

    def forget!(gem, origin)
      paths_for(gem).reject! { |path| path["origin"] == origin }
      @data["gems"].delete(gem) if paths_for(gem).empty?
      self
    end

    def gems = @data["gems"].keys

    # Everything oubliette has ever moved here, shallowest origin first, which
    # is the order a rollback wants: a parent is restored before the children
    # that were lifted out of it are put back inside.
    def pairs(only: nil)
      @data["gems"].flat_map do |gem, entry|
        next [] if only && gem != only

        Array(entry["paths"]).map do |path|
          Pair.new(
            gem: gem,
            origin: path["origin"],
            oublietted: path["origin"],
            current: path["oublietted"],
            status: status_for(path)
          )
        end
      end.sort_by { |pair| [ pair.origin.count("/"), pair.origin ] }
    end

    def save!
      @path.write(render)
      self
    end

    def render
      <<~YAML + @data.to_yaml.sub(/\A---\n/, "")
        # rollback.yml -- written by oubliette, not by you.
        #
        # `origin` is where each framework keeps this directory by default.
        # `oublietted` is where it is right now. Editing migrate.yml changes
        # where things are going; it never changes where they came from, which
        # is what `rake oubliette:rollback` reads.
      YAML
    end
    private
      def paths_for(gem)
        (@data["gems"][gem] ||= { "paths" => [] })["paths"] ||= []
      end

      def entry(gem, origin)
        Array(@data["gems"].dig(gem, "paths")).find { |path| path["origin"] == origin }
      end

      def status_for(path)
        return :settled if path["origin"] == path["oublietted"]
        return :settled if @root.join(path["oublietted"]).exist?

        :missing
      end
  end
end
