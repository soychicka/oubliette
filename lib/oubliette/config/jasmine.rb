# frozen_string_literal: true

require_relative "javascript"

module Oubliette
  module Config
    # Rewrites the paths in jasmine.json.
    #
    # The jasmine runner reads its spec directory from a config file rather than
    # from package.json, so relocating the specs without touching it leaves
    # jasmine looking in an empty directory and reporting cheerful success.
    class Jasmine < Javascript
      register :jasmine

      KEYS = %w[spec_dir helpers spec_files].freeze

      def filename = "jasmine.json"

      def keys = KEYS
    end
  end
end
