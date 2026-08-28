# frozen_string_literal: true

module Oubliette
  # One directory, in both of the places it can be named.
  #
  # `origin` is the framework's own default location and never changes -- it is
  # what makes a rollback possible however far migrate.yml has drifted.
  # `oublietted` is where that directory is meant to end up, and `current` is
  # where it actually is according to rollback.yml.
  Pair = Data.define(:gem, :origin, :oublietted, :current, :status) do
    def settled? = status == :settled
    def pending? = status == :pending
    def missing? = status == :missing
    def canonical? = origin == oublietted

    # A directory whose target changed goes home before it goes anywhere new, so
    # the configuration only ever describes a single hop.
    def hops
      return [] if settled? || missing?
      return [ [ current, oublietted ] ] if current == origin

      [ [ current, origin ], [ origin, oublietted ] ].reject { |from, to| from == to }
    end
  end
end
