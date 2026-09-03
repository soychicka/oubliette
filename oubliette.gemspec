# frozen_string_literal: true

require_relative "lib/oubliette/version"

Gem::Specification.new do |spec|
  spec.name = "oubliette"
  spec.version = Oubliette::VERSION
  spec.authors = [ "soychicka" ]
  spec.email = [ "soychicka@gmail.com" ]

  spec.summary = "Hide every test asset under one central test/ directory."
  spec.description = <<~TEXT
    Oubliette detects the test frameworks a project actually uses, moves their
    directories under a single test/ tree, and rewrites each framework's
    configuration so the default commands keep working. Every move is described
    by a migrate.yml the user owns and can edit, and every move is reversible.
  TEXT
  spec.homepage = "https://github.com/soychicka/oubliette"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "lib/**/*.rake",
    "lib/**/*.yml",
    "exe/*",
    "bin/playground",
    "README.md",
    "LICENSE.txt"
  ]
  spec.bindir = "exe"
  spec.executables = [ "oubliette" ]
  spec.require_paths = [ "lib" ]
end
