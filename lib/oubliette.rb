# frozen_string_literal: true

require "pathname"
require_relative "oubliette/version"

module Oubliette
  class Error < StandardError; end

  # Oubliette's own files live under the tree it builds, not scattered through
  # the project root. HOME holds what the developer reads and edits; SUPPORT
  # holds the bookkeeping that belongs to oubliette alone.
  HOME = "test/oubliette"
  SUPPORT = "test/oubliette/support"

  class << self
    attr_writer :root

    def root
      @root ||= default_root
    end

    # Where a framework's assets actually are, for code that needs to build a
    # path of its own. This reads rollback.yml before migrate.yml on purpose: an
    # application asking at runtime wants the directory that exists, not the one
    # somebody has typed into the manifest but not yet applied. Returns nil when
    # oubliette has never run here.
    # Where a framework's directories are now, or nil to say "wherever your
    # framework puts them". Callers pair this with their own default, so nil
    # has to mean nothing moved -- never a guess at where a migration would
    # have put things had it run.
    def path(key)
      return nil unless Manifest.exists_in?(root) && Ledger.displaced?(root)

      location = Manifest.load(root).location(key)
      location && root.join(location)
    end
    private
      def default_root
        return Pathname.new(Rails.root) if defined?(Rails) && Rails.respond_to?(:root) && Rails.root

        Pathname.new(Dir.pwd)
      end
  end
end

require_relative "oubliette/text"
require_relative "oubliette/notice"
require_relative "oubliette/path_token"
require_relative "oubliette/catalog"
require_relative "oubliette/pair"
require_relative "oubliette/ledger"
require_relative "oubliette/detector"
require_relative "oubliette/manifest"
require_relative "oubliette/requires"
require_relative "oubliette/mover"
require_relative "oubliette/reporter"
require_relative "oubliette/scanner"
require_relative "oubliette/suite"
require_relative "oubliette/runs"
require_relative "oubliette/test_run"
require_relative "oubliette/paper"
require_relative "oubliette/paper/readme"
require_relative "oubliette/paper/recovery"
require_relative "oubliette/playground"
require_relative "oubliette/repair"
require_relative "oubliette/runner"
require_relative "oubliette/uninstall"
require_relative "oubliette/runtime"
require_relative "oubliette/railtie" if defined?(Rails::Railtie)
