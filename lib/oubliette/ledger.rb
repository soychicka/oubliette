# frozen_string_literal: true

require "fileutils"
require "yaml"
require "pathname"
require_relative "pair"
require_relative "text"

module Oubliette
  # rollback.yml: where each directory started, and where it is now.
  #
  # This file belongs to oubliette, not to the user. migrate.yml can be edited
  # freely -- retargeted, reordered, pruned -- without ever costing the project
  # the ability to put a directory back exactly where its framework expects it,
  # because the original location is recorded here and never rewritten.
  class Ledger
    FILENAME = "rollback.yml"
    PATH = "#{SUPPORT}/#{FILENAME}"
    VERSION = 1

    attr_reader :root, :path, :data

    def self.path_in(root) = Pathname.new(root).join(PATH)

    # Whether anything is actually somewhere other than its origin.
    #
    # This is the question every runtime caller is really asking. migrate.yml
    # says where directories are *meant* to go; only rollback.yml says where
    # they are. With no rollback.yml -- after `prepare`, or after an uninstall
    # that leaves migrate.yml behind because it is yours -- nothing has moved,
    # and answering from migrate.yml would point a suite at directories that do
    # not exist.
    def self.displaced?(root)
      return false unless exists_in?(root)

      load(root).pairs.any? { |pair| pair.origin != pair.current }
    end

    def self.exists_in?(root)
      adopt_legacy(root)
      path_in(root).file?
    end

    # As with migrate.yml: a project written by an older gem keeps its record of
    # where everything came from rather than losing the ability to roll back.
    def self.adopt_legacy(root)
      legacy = Pathname.new(root).join(FILENAME)
      target = path_in(root)
      return if !legacy.file? || target.file?

      FileUtils.mkdir_p(target.dirname)
      FileUtils.mv(legacy.to_s, target.to_s)
    end

    def self.load(root)
      adopt_legacy(root)
      file = path_in(root)
      new(root, file.file? ? (YAML.safe_load(Oubliette.read(file), aliases: false) || {}) : {})
    end

    def initialize(root, data)
      @root = Pathname.new(root)
      @path = self.class.path_in(root)
      @data = data
      @data["version"] ||= VERSION
      @data["gems"] ||= {}
      @data["known_gems"] ||= []
    end

    # Every framework oubliette has written into migrate.yml at least once.
    # Without this it cannot tell a framework the developer deleted from one it
    # has simply never seen, and would helpfully put the deleted one back.
    def known?(key) = @data["known_gems"].include?(key)

    def remember!(keys)
      @data["known_gems"] = (@data["known_gems"] | Array(keys)).sort
      self
    end

    # Forgetting makes a deleted entry eligible to come back, which is what
    # `rake oubliette:reset` is for.
    def forget_known!(key = nil)
      @data["known_gems"] = key ? @data["known_gems"] - [ key ] : []
      self
    end

    # Where this directory is right now, or nil if oubliette has never moved it.
    def current(gem, origin)
      entry(gem, origin)&.fetch("oubliette", nil)
    end

    def record!(gem, origin, oubliette)
      found = entry(gem, origin)
      if found
        found["oubliette"] = oubliette
      else
        paths_for(gem) << { "origin" => origin, "oubliette" => oubliette }
      end
      self
    end

    def forget!(gem, origin)
      paths_for(gem).reject! { |path| path["origin"] == origin }
      @data["gems"].delete(gem) if paths_for(gem).empty?
      self
    end

    def gems = @data["gems"].keys

    # Everything oubliette has ever moved here, deepest origin first -- the same
    # order the forward migration uses, and for the same reason. A child whose
    # target sits inside its parent's target (spec/system inside spec) must be
    # lifted out before the parent is moved, or the parent carries it along and
    # the child's recorded location stops being true.
    def pairs(only: nil)
      @data["gems"].flat_map do |gem, entry|
        next [] if only && gem != only

        Array(entry["paths"]).map do |path|
          Pair.new(
            gem: gem,
            origin: path["origin"],
            oubliette: path["origin"],
            current: path["oubliette"],
            status: status_for(path),
            generated: false
          )
        end
      end.sort_by { |pair| [ -pair.origin.count("/"), pair.origin ] }
    end

    def save!
      FileUtils.mkdir_p(@path.dirname)
      @path.write(render)
      self
    end

    def render
      Text.t("ledger.header") + @data.to_yaml.sub(/\A---\n/, "")
    end
    private
      def paths_for(gem)
        (@data["gems"][gem] ||= { "paths" => [] })["paths"] ||= []
      end

      def entry(gem, origin)
        Array(@data["gems"].dig(gem, "paths")).find { |path| path["origin"] == origin }
      end

      def status_for(path)
        return :settled if path["origin"] == path["oubliette"]
        return :settled if @root.join(path["oubliette"]).exist?

        :missing
      end
  end
end
