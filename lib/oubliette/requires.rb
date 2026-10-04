# frozen_string_literal: true

require "pathname"

module Oubliette
  # Repairs `require_relative` after a directory changes depth.
  #
  # Every rspec-rails project has `require_relative "../config/environment"` at
  # the top of its generated rails_helper, and spec/ becoming test/rspec/ puts
  # that one directory further down. The rewrite is mechanical: a require that
  # pointed outside the directory being moved is recomputed from where the file
  # now sits, and one that pointed inside it is left alone, because its target
  # travelled along with it.
  class Requires
    LITERAL = /require_relative\s*\(?\s*(?<quote>["'])(?<path>[^"'\#]+)\k<quote>/

    def initialize(root)
      @root = Pathname.new(root)
    end

    # `files` are paths relative to the directory that moved, collected before
    # the move so a merge into a shared destination cannot pick up a neighbour's
    # files by mistake.
    def repair(from:, to:, files:)
      return [] if from == to

      files.filter_map { |file| repair_file(from, to, file) }
    end
    private
      def repair_file(from, to, file)
        target = @root.join(to, file)
        return nil unless target.file?

        old_dir = @root.join(from, file).dirname
        new_dir = target.dirname
        return nil if old_dir == new_dir

        # Scrubbed for the same reason the scanner scrubs: a real project holds
        # files with bytes that are not valid in the default encoding, and a
        # migration must not die halfway through because one of them exists.
        source = Oubliette.read(target).scrub
        rewritten = rewrite(source, from, old_dir, new_dir)
        return nil if rewritten == source

        target.write(rewritten)
        "#{to}/#{file}"
      rescue ArgumentError, EncodingError, SystemCallError
        nil
      end

      def rewrite(source, from, old_dir, new_dir)
        moved_tree = @root.join(from).cleanpath

        source.gsub(LITERAL) do |match|
          path = Regexp.last_match(:path)
          resolved = Pathname.new(File.expand_path(path, old_dir))
          next match if inside?(resolved, moved_tree)

          replacement = resolved.relative_path_from(new_dir).to_s
          match.sub(path, replacement)
        end
      end

      def inside?(path, tree)
        path.to_s == tree.to_s || path.to_s.start_with?("#{tree}/")
      end
  end
end
