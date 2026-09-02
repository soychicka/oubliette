# frozen_string_literal: true

require "yaml"

module Oubliette
  # Every string a person reads, kept out of the code that decides to say it.
  #
  # The store is YAML, which this gem already reads and writes, so there is no
  # new dependency and no second mental model. Placeholders are `%{name}`,
  # which is what the i18n gem uses: if this ever needs to become real
  # internationalisation, the locale files carry over untouched and only the
  # lookup below is replaced.
  #
  #   Text.t("uninstall.done")
  #   Text.t("mover.relocated", from: "spec", to: "test/rspec")
  #
  # A missing key raises. A string nobody can read is a bug, and a migration
  # tool that prints a blank line where it meant to warn you is worse than one
  # that stops.
  module Text
    DIRECTORY = File.expand_path("locales", __dir__)
    DEFAULT = :en

    class Missing < Error; end

    class << self
      attr_writer :locale

      def locale = @locale ||= DEFAULT

      def available = Dir.children(DIRECTORY).grep(/\.yml\z/).map { |name| File.basename(name, ".yml").to_sym }

      def t(key, **values)
        template = lookup(key)
        # Only interpolate when there is something to interpolate, so a string
        # containing a bare `%` does not have to be escaped for no reason.
        return template unless template.include?("%{")

        # The hash is passed positionally and always, so a missing value fails
        # as `KeyError: key<items> not found` rather than the useless
        # `ArgumentError: one hash required` that `format` gives for no args.
        format(template, values)
      end

      # A whole branch, symbol-keyed, for the few places that look a label up by
      # something decided at runtime -- a status, a tier. Building the key
      # instead (`"status.#{value}"`) would work and would be worse: the suite
      # greps for literal keys to prove the file and the code agree, and a key
      # assembled at runtime is a key nobody can find.
      def group(key)
        found = branch(key)
        raise Missing, "no group at #{key.inspect}" unless found.is_a?(Hash)

        found.transform_keys(&:to_sym)
      end

      def reload! = @tables = nil

      def key?(key)
        lookup(key)
        true
      rescue Missing
        false
      end
      private
        def lookup(key)
          found = fetch(key) { |node| node.is_a?(Hash) ? nil : node }
          raise Missing, "no text for #{key.inspect} in #{locale}" if found.nil?

          found
        end

        def branch(key) = fetch(key) { |node| node }

        def fetch(key)
          path = key.to_s.split(".")
          found = yield(dig(table(locale), path))
          found = yield(dig(table(DEFAULT), path)) if found.nil? && locale != DEFAULT
          found
        end

        def dig(node, path)
          path.each do |segment|
            return nil unless node.is_a?(Hash) && node.key?(segment)

            node = node[segment]
          end
          node
        end

        def table(name)
          tables[name] ||= begin
            file = File.join(DIRECTORY, "#{name}.yml")
            raise Missing, "no locale file for #{name}" unless File.file?(file)

            YAML.safe_load_file(file) || {}
          end
        end

        def tables = @tables ||= {}
    end
  end
end
