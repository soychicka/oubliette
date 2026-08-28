# Oubliette

> *oubliette* — a dungeon reachable only through a trapdoor in its ceiling.

Every test framework a Rails project picks up brings its own directory, and they
all land in the project root: `spec/`, `features/`, `test/`, `cypress/`,
`coverage/`, `test_results/`, plus the fixture and factory data they quietly
share. Oubliette works out which frameworks are actually in use, moves their
assets under a single `test/` tree, and rewrites each framework's own config so
the default commands keep working.

## Install

```ruby
group :development, :test do
  gem "oubliette"
end
```

## Use

```bash
rake oubliette:prepare   # write migrate.yml so you can edit the targets first
rake oubliette           # move whatever changed, and sync frameworks added since
rake oubliette:dry_run   # show what would change, touch nothing
rake oubliette:status    # report where every test directory currently lives
rake oubliette:reset     # discard your edits, restore oubliette's targets, move to match
rake oubliette:rollback  # return everything to its origin
rake oubliette:put_back[cucumber-rails]   # return one framework
rake oubliette:selftest  # run the gem's own specs, with no app code loaded
rake oubliette:install_specs   # add the layout spec to this project's suite
```

`rake oubliette --dry-run` works too; the task takes rake's own flag over.

The same commands exist as a CLI for non-Rails projects: `oubliette prepare`,
`oubliette run`, `oubliette status`, `oubliette rollback [gem]`.

## Two files

**migrate.yml is yours.** It says where you want each framework's directories to
live, and nothing else. `rake oubliette:prepare` writes it; if you never run
`prepare`, the first `rake oubliette` generates it, uses it, and tells you that
you can edit it and rerun.

```yaml
gems:
  rspec-rails:
    enabled: true
    config: [rspec]
    paths:
    - origin: spec
      oublietted: test/rspec
  factory_bot_rails:
    enabled: true
    config: [factory_bot]
    paths:
    - origin: spec/factories
      oublietted: test/data/factories
    - origin: test/factories
      oublietted: test/data/factories
```

**rollback.yml is oubliette's.** It records the same pairs, but `oublietted` is
where each directory *actually is*, and `origin` is the framework's own default
location, written once and never rewritten.

```yaml
gems:
  rspec-rails:
    paths:
    - origin: spec
      oublietted: test/examples
```

The split is the point. You can retarget a directory in migrate.yml as often as
you like, or delete the file, or mangle it — `rake oubliette:rollback` still
knows that `spec` is where RSpec expects its specs, because that answer was
never stored in the file you edit.

## What each command does with them

`rake oubliette` compares the two files pair by pair and **only touches entries
that differ**. A pair whose `oublietted` already matches rollback.yml is skipped
entirely, which is why the same command serves as the first migration, the sync
after installing a new framework, and the way you apply an edit. A directory
whose target changed goes back to its `origin` first and is then moved to the
new target, so the configuration only ever describes a single hop.

`rake oubliette:reset` overwrites the targets in migrate.yml with oubliette's own
defaults, discarding your edits, and then moves the directories to match.
`rake oubliette:reset[rspec-rails]` resets one framework and leaves the rest of
your edits alone.

`rake oubliette:rollback` — and `rake oubliette:put_back`, which is the same
thing — reads rollback.yml and returns every directory to its `origin`. Both
take a framework name to scope them: `rake oubliette:put_back[cucumber-rails]`.

Set `enabled: false` on a gem in migrate.yml to leave it alone. Directories that
look like test trees but belong to no known framework are listed under
`strays:`, disabled, so including one is a deliberate edit.

## Layout

```
test/
├── rspec/            spec/
├── minitest/         test/models, test/controllers, ...
├── unit/             test/unit
├── system/           spec/system, spec/features, test/system
├── cucumber/
│   ├── features/     features/
│   └── aruba/
├── javascript/
│   ├── jest/  jasmine/  vitest/  playwright/  cypress/  karma/
├── data/
│   ├── factories/    spec/factories, test/factories
│   ├── fixtures/     test/fixtures, spec/fixtures
│   ├── attributes/   spec/attributes
│   ├── seeds/        spec/seeds, db/seeds/test
│   ├── cassettes/    spec/vcr_cassettes
│   └── exemplars/    spec/exemplars
├── support/          spec/support, test/support
└── results/          test_results/, coverage/, screenshots
```

Assets that several frameworks share — factories, fixtures, attribute sets,
seeds, cassettes and support helpers — are pulled out of whichever framework's
directory they happened to be sitting in and given a home of their own under
`data/` and `support/`, so a fixture set is not the property of RSpec merely
because RSpec was installed first.

## How the frameworks are told where to look

| Framework | Mechanism |
|---|---|
| RSpec | `--default-path` in `.rspec`, regenerated from your original options |
| Cucumber | feature paths substituted inside your existing `cucumber.yml` |
| Jest and friends | path strings rewritten in `package.json`, through a JSON round trip |
| Rails fixtures | `ActiveSupport::TestCase.fixture_paths`, overridden as a reader from the railtie, because `rails/test_help` appends the default path from a hook that runs later |
| FactoryBot | `FactoryBot.definition_file_paths` |
| VCR | `cassette_library_dir` |
| SimpleCov | `coverage_dir` |
| Capybara | `save_path` for screenshots |

The file-based ones are backed up to `.oubliette/backups/` before they are
touched, and rollback is a restore.

## When something is missing

If a framework's directories are absent from both their original and their new
location, oubliette says so on the command line, declines to write a config
pointing at nothing, and raises at runtime rather than letting a suite start
with no fixtures loaded.

## Testing

The gem's specs live in `lib/oubliette/rspec/specs`, not in `spec/`, on purpose.
They are packaged with the gem, so they run three ways:

- standalone, in this repository: `bundle exec rspec`
- inside a host application's suite, via the shared example group:

  ```ruby
  require "oubliette/rspec"

  RSpec.describe "test layout" do
    it_behaves_like "an oubliette-managed project", Rails.root
  end
  ```

- inside a host application but *outside* its RSpec setup, for when the
  migration is what broke the suite: `rake oubliette:selftest`

Every example builds a real project in a temporary directory, with a real git
repository, and runs the real mover against it.

`bin/e2e /some/build/dir` goes further: it generates a brand new Rails
application with RSpec, Cucumber, Minitest, FactoryBot, Capybara, VCR, SimpleCov
and Jest installed, proves `rspec`, `cucumber` and `bin/rails test` all pass,
migrates it, proves they still pass, and then rolls the whole thing back.

## Safety

Oubliette refuses to move anything while the working tree has unstaged or
untracked changes (`FORCE=1` overrides). Moves go through `git mv` where git
will take them, so history follows the files.
