# frozen_string_literal: true

require "pathname"
require_relative "oubliette/version"

module Oubliette
  class Error < StandardError; end

  class << self
    attr_writer :root

    def root
      @root ||= default_root
    end

    # The relocated home of a framework's assets, for code that needs to build a
    # path of its own. Falls back to the original location when oubliette has
    # not run here.
    def path(key)
      return nil unless Manifest.exists_in?(root)

      destination = Manifest.load(root).destination(key)
      destination && root.join(destination)
    end
    private
      def default_root
        return Pathname.new(Rails.root) if defined?(Rails) && Rails.respond_to?(:root) && Rails.root

        Pathname.new(Dir.pwd)
      end
  end
end

require_relative "oubliette/catalog"
require_relative "oubliette/pair"
require_relative "oubliette/ledger"
require_relative "oubliette/detector"
require_relative "oubliette/manifest"
require_relative "oubliette/requires"
require_relative "oubliette/mover"
require_relative "oubliette/reporter"
require_relative "oubliette/scanner"
require_relative "oubliette/runner"
require_relative "oubliette/runtime"
require_relative "oubliette/railtie" if defined?(Rails::Railtie)
