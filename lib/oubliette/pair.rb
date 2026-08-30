# frozen_string_literal: true

module Oubliette
  # One directory, in both of the places it can be named.
  #
  # A `generated` pair is one oubliette configures rather than moves: coverage
  # reports and screenshots are written afresh by the tool that makes them, so
  # pointing that tool at the new location is the whole job. Moving yesterday's
  # copy achieves nothing and guarantees a collision the next time it is written.
  #
  # `origin` is the framework's own default location and never changes -- it is
  # what makes a rollback possible however far migrate.yml has drifted.
  # `oubliette` is where that directory is meant to end up, and `current` is
  # where it actually is according to rollback.yml.
  Pair = Data.define(:gem, :origin, :oubliette, :current, :status, :generated) do
    def settled? = status == :settled
    def configured? = status == :configured
    def pending? = status == :pending
    def missing? = status == :missing
    def canonical? = origin == oubliette

    # A directory whose target changed goes home before it goes anywhere new, so
    # the configuration only ever describes a single hop.
    def hops
      return [] if settled? || missing?
      return [ [ current, oubliette ] ] if current == origin

      [ [ current, origin ], [ origin, oubliette ] ].reject { |from, to| from == to }
    end
  end
end
