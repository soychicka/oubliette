# frozen_string_literal: true

# The gem's suite is the portable suite. Keeping the examples inside lib/ is
# what lets a host application run them with `rake oubliette:selftest`, in a
# process that has loaded none of its own code.
Oubliette::RSpec.spec_paths.each { |path| require path }
