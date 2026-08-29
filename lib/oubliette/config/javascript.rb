# frozen_string_literal: true

require "json"
require_relative "writer"
require_relative "../path_token"

module Oubliette
  module Config
    # Rewrites the paths the javascript runners keep in JSON.
    #
    # JSON cannot carry a comment, so there is nowhere to park the original
    # line. Instead of rewriting the file, the exact quoted strings that name a
    # relocated directory are replaced where they stand -- formatting,
    # key order, and every setting oubliette does not manage are left byte for
    # byte as they were. Undoing the edit is the same substitution backwards.
    class Javascript < Writer
      register :jest

      KEYS = %w[jest scripts].freeze

      def filename = "package.json"

      # Which top-level keys can hold a path. Subclasses point at other files.
      def keys = KEYS

      def render(current)
        return nil if current.nil?

        substitutions = javascript_substitutions
        return nil if substitutions.empty?

        rewrite(current, substitutions)
      end
      protected
        def restore(current)
          substitutions = javascript_substitutions.map(&:reverse)
          return current if substitutions.empty?

          rewrite(current, substitutions)
        end

        def javascript_substitutions
          %w[jest jasmine vitest @playwright/test cypress karma].filter_map do |key|
            pairs = @manifest.pairs(only: key).reject(&:missing?)
            next if pairs.empty?

            pairs.map { |pair| [ pair.origin, pair.oubliette ] }
          end.flatten(1).reject { |origin, oubliette| origin == oubliette }
        end
      private
        # Only the strings found inside the keys this writer manages are
        # touched, and each is replaced as a whole quoted value, so nothing else
        # in the file can be caught by accident.
        def rewrite(source, substitutions)
          parsed = JSON.parse(source)
          replacements = {}

          keys.each do |key|
            next unless parsed.key?(key)

            strings_in(parsed[key]).each do |value|
              updated = substitute(value, substitutions)
              replacements[value] = updated unless updated == value
            end
          end

          replacements.reduce(source) { |text, (from, to)| text.gsub(%("#{from}"), %("#{to}")) }
        rescue JSON::ParserError
          source
        end

        def strings_in(node)
          case node
          when Hash then node.values.flat_map { |value| strings_in(value) }
          when Array then node.flat_map { |value| strings_in(value) }
          when String then [ node ]
          else []
          end
        end

        def substitute(text, substitutions)
          substitutions.reduce(text) { |value, (from, to)| PathToken.substitute(value, from, to) }
        end
    end
  end
end
