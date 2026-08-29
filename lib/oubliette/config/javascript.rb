# frozen_string_literal: true

require "json"
require_relative "writer"

module Oubliette
  module Config
    # Rewrites the JavaScript runners' paths.
    #
    # Both jest.config.js and the jest/scripts blocks in package.json refer to
    # their directories as plain strings, so the same path substitution works on
    # either. package.json is edited through a JSON round trip on the keys that
    # can hold paths, never as raw text, so a stray match cannot corrupt it.
    class Javascript < Writer
      register :jest

      KEYS = %w[jest scripts].freeze

      def filename = "package.json"

      # Which top-level keys can hold a path. Subclasses point at other files.
      def keys = KEYS

      def render
        substitutions = javascript_substitutions
        return nil if substitutions.empty?

        source = original
        return nil if source.nil?

        parsed = JSON.parse(source)
        keys.each { |key| parsed[key] = substitute(parsed[key], substitutions) if parsed.key?(key) }
        "#{JSON.pretty_generate(parsed)}\n"
      rescue JSON::ParserError
        nil
      end
      protected
        def javascript_substitutions
          %w[jest jasmine vitest @playwright/test cypress karma].filter_map do |key|
            pairs = @manifest.pairs(only: key).reject(&:missing?)
            next if pairs.empty?

            pairs.map { |pair| [ pair.origin, pair.oubliette ] }
          end.flatten(1).reject { |origin, oubliette| origin == oubliette }
        end

        def substitute(node, substitutions)
          case node
          when Hash then node.transform_values { |value| substitute(value, substitutions) }
          when Array then node.map { |value| substitute(value, substitutions) }
          when String
            substitutions.reduce(node) do |text, (from, to)|
              text.gsub(/(?<![\w\/.-])#{Regexp.escape(from)}(?=[\s\/'"]|$)/, to)
            end
          else node
          end
        end

        def original
          source = backup_path.file? ? backup_path : @root.join(filename)
          return nil unless source.file?

          contents = source.read
          contents == Writer::ABSENT ? nil : contents
        end
    end
  end
end
