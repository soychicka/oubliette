# frozen_string_literal: true

module Oubliette
  module Config
    # A reversible edit to a config file that comments rather than deletes.
    #
    # Oubliette never rewrites a config file wholesale. What it changes it wraps
    # in a marked block: the developer's own line is kept, commented out and
    # prefixed so it can be restored exactly, and the replacement sits below it.
    # Undoing the edit means uncommenting the original and dropping the rest --
    # everything outside the block, including anything edited since, is left
    # untouched because it is never read or rewritten.
    module ManagedBlock
      OPEN = ">>> oubliette >>>"
      CLOSE = "<<< oubliette <<<"
      WAS = "was:"

      module_function

      # `reason` explains, in the file itself, why the edit was made.
      def wrap(reason:, replacement:, original: [], comment: "#")
        lines = [ "#{comment} #{OPEN}" ]
        Array(reason).each { |line| lines << "#{comment} #{line}" }
        Array(original).each { |line| lines << "#{comment} #{WAS} #{line}" }
        lines.concat(Array(replacement))
        lines << "#{comment} #{CLOSE}"
        "#{lines.join("\n")}\n"
      end

      # Puts the file back the way it was, block by block, and leaves every
      # other line exactly as it found it.
      def unwrap(contents, comment: "#")
        return contents if contents.nil? || !contents.include?(OPEN)

        inside = false
        contents.lines.filter_map do |line|
          stripped = line.strip

          if stripped == "#{comment} #{OPEN}"
            inside = true
            next
          elsif stripped == "#{comment} #{CLOSE}"
            inside = false
            next
          end

          next line unless inside

          original_of(stripped, comment)
        end.join
      end

      def wrapped?(contents) = contents.to_s.include?(OPEN)

      def original_of(stripped, comment)
        prefix = "#{comment} #{WAS} "
        return nil unless stripped.start_with?(prefix)

        "#{stripped.delete_prefix(prefix)}\n"
      end
    end
  end
end
