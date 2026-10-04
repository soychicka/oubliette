# Oubliette

<img src="assets/oubliette.svg" alt="Hands encircling a labyrinth" align="right" width="150">

> *oubliette* — a dungeon reachable only through a trapdoor in its ceiling.

Every test framework a Rails project picks up brings its own directory, and they
all land in the project root: `spec/`, `features/`, `test/`, `cypress/`,
`coverage/`, `test_results/`, plus the fixture and factory data they quietly
share. Oubliette works out which frameworks are actually in use, moves their
assets under a single `test/` tree, and rewrites each framework's own config so
the default commands keep working.

## Install

Not on rubygems yet, so take it from the repository:

```ruby
group :development, :test do
  gem "oubliette", github: "soychicka/oubliette"
end
```

Or from a checkout, which is what you want if you are changing the gem as well
as using it:

```ruby
group :development, :test do
  gem "oubliette", path: "../oubliette"
end
```

On release the line becomes `gem "oubliette"` and nothing else about this
changes.

## Quick start

Six commands. One of them moves anything.

```bash
bundle install
rake oubliette:test      # what passes now -- there is nothing to compare to yet
rake oubliette:prepare   # writes test/oubliette/migrate.yml, and stops
rake oubliette:dry_run   # what would move, and what config would change
rake oubliette           # do it, after answering the question it asks
rake oubliette:test      # same suites, same counts?
```

Run `oubliette:test` **before** you migrate. It reports drift against its own
history, so the first run is only a baseline -- without it, the run afterwards
has nothing to be measured against, and measuring it is the entire point. A
suite that quietly stopped collecting half its tests still exits zero.

`oubliette:prepare` writes a plan and nothing else. The plan is a file you own:
delete a gem's entry to leave that framework where it is, change an entry's
target to send it somewhere else. `rake oubliette` then asks before acting on
it, once.

If anything is wrong:

```bash
rake oubliette:rollback  # every directory back where it started
```

Rollback also uncomments the config lines oubliette commented out. Anything you
wrote yourself is outside the blocks it manages, so it survives both directions.

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
rake oubliette:test      # run every suite, report drift, record how long it took
rake oubliette:playground      # build a demo application to try this on
rake oubliette:uninstall # roll back, then remove oubliette's own files
rake oubliette:hoggle    # the same thing, shown out by someone who knows the way
```

`rake oubliette --dry-run` works too; the task takes rake's own flag over.

The same commands exist as a CLI for non-Rails projects: `oubliette prepare`,
`oubliette run`, `oubliette status`, `oubliette rollback [gem]`.

## The first run asks first

`rake oubliette` on a project that has never run it prints the migrate.yml it
just wrote and waits:

```
do you want your test directories in this hierarchy? [y/N]
```

Answer no and nothing moves. You get told where the file is, that deleting a
gem's entry excludes it, and that editing an entry's `oubliette` attribute
changes where it lands. Run `rake oubliette` again when you are happy with it --
the question is only asked once, because from then on migrate.yml is a file you
have already read.

When there is no terminal attached, as in CI, it says so and proceeds.

## Two files

Oubliette keeps its own paperwork inside the tree it builds rather than
scattering it through the project root:

```
test/oubliette/
├── migrate.yml                 the file you edit
├── cypress.config.js.md        instructions for a config it will not rewrite
└── support/
    └── rollback.yml            its own bookkeeping, not yours to edit
```

**test/oubliette/migrate.yml is yours.** It says where you want each framework's directories to
live, and nothing else. `rake oubliette:prepare` writes it; if you never run
`prepare`, the first `rake oubliette` generates it, uses it, and tells you that
you can edit it and rerun.

```yaml
gems:
  # frameworks you declared -----------------------------------------------
  rspec-rails:
    enabled: true
    tier: declared
    config: [rspec]
    paths:
    - origin: spec
      oubliette: test/rspec

  # shared test material -- fixtures, factories, helpers, output ----------
  factory_bot_rails:
    enabled: true
    tier: declared
    config: [factory_bot]
    paths:
    - origin: spec/factories
      oubliette: test/data/factories
    - origin: test/factories
      oubliette: test/data/factories
```

`tier` records how oubliette knows about a framework: `declared` if you named it,
`locked` if it arrived as another gem's dependency, `disk` if only a directory
gave it away. The sections are ordered by it, and the file ends with a list of
what oubliette knows but did not find here.

**rollback.yml is oubliette's.** It records the same pairs, but `oubliette` is
where each directory *actually is*, and `origin` is the framework's own default
location, written once and never rewritten.

```yaml
gems:
  rspec-rails:
    paths:
    - origin: spec
      oubliette: test/examples
```

The split is the point. You can retarget a directory in migrate.yml as often as
you like, or delete the file, or mangle it — `rake oubliette:rollback` still
knows that `spec` is where RSpec expects its specs, because that answer was
never stored in the file you edit.

## What each command does with them

`rake oubliette` compares the two files pair by pair and **only touches entries
that differ**. A pair whose `oubliette` already matches rollback.yml is skipped
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

There are two ways to leave a framework alone. Delete its entry from migrate.yml
and it stays deleted -- oubliette records which frameworks it has written down,
so it can tell one you removed from one it has never met, and will not put it
back. Or set `enabled: false` on the entry, which does the same thing while
keeping the decision visible in the file. `rake oubliette:reset` undoes either.

Directories that look like test trees but belong to no known framework are listed
under `strays:`, disabled, so including one is a deliberate edit.

## Somewhere to try it

`rake oubliette:playground` builds a small Rails application with one passing
test per framework oubliette knows about -- rspec, minitest, cucumber, jest,
jasmine, factory_bot, vcr, simplecov -- plus Administrate, so there is a real
engine with its own javascript for oubliette to leave alone. Everything is green
and in its default location, and oubliette is commented out in the Gemfile, so
installing it is part of what you get to try.

It goes next to your project rather than inside it, since a second Rails
application under this one would turn up in every glob the first one runs. Pass
a path to put it elsewhere: `rake "oubliette:playground[~/scratch/demo]"`.
Building over a directory that already exists deletes it first, so that prompt
is the one place in oubliette that will not take `y` -- it wants YES.

## What is left in test/oubliette

Two documents, both written by oubliette and rewritten on every run:

- `README.md` explains the directory to whoever opens it next, and lists every
  framework that was moved -- separating the ones whose configuration was
  rewritten for you from the four javascript ones you have to finish by hand.
- `RECOVERY.md` is how to undo all of it, including with no gem installed: the
  origin of every directory, and the markers to search your config files for.

Both say at the top that edits to them are overwritten, because they are only
worth anything while they match where the directories actually are. Both are
deleted once nothing is displaced -- a recovery note for an empty oubliette is
one more thing to be out of date.

## Leaving

`rake oubliette:uninstall` is a rollback that also takes oubliette out of the
project. It asks first, and the question names no paths, because on a project of
any size that list is a wall of text in front of a yes/no. The report comes after.

Only one file is deleted automatically: `rollback.yml`, which is oubliette's
bookkeeping and nobody else's, and only once every directory is home and every
config restored. Everything else is listed for you to remove or keep, because
each one has something of yours in it -- migrate.yml is your configuration, the
test log is your history, an edited guide is your notes, the layout spec is a
test in your suite, and `test/` itself may well predate oubliette.

`rake oubliette:hoggle` is the same task under another name, for anyone who
first met the word in a labyrinth.

Then remove `gem "oubliette"` from your Gemfile. Nothing left behind depends on
it.

## Layout

```
test/
├── rspec/            spec/
│   ├── system/       spec/system, spec/features
│   └── support/      spec/support
├── minitest/         test/models, test/controllers, ...
├── unit/             test/unit
├── system/           test/system, Rails' own system tests
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
├── support/          test/support, minitest's own
└── results/          test_results/, coverage/, screenshots
```

RSpec's system specs are the one place the tree bends to a tool rather than the
other way round. `rspec` collects from a single `--default-path`, so a system
spec moved outside that path is quietly never run again; they stay under
`test/rspec/system`. `test/system` belongs to Rails' own system tests.

Assets that several frameworks share — factories, fixtures, attribute sets,
seeds, cassettes and support helpers — are pulled out of whichever framework's
directory they happened to be sitting in and given a home of their own under
`data/` and `support/`, so a fixture set is not the property of RSpec merely
because RSpec was installed first.

## Degrees of support

Three things can happen to a framework: its directories are moved, its config is
updated, and its suite is run before and after so the example counts prove
nothing was lost. Which of the three you get is what the last column says.

- **Verified** — moved, configured for you, then run before and after with the
  counts compared. A suite that silently shrinks is the failure worth fearing,
  and this is the only tier that rules it out.
- **Configured** — moved, and pointed at the new location for you. No suite of
  its own; it is exercised by whichever suite does run.
- **Guided** — moved, and a generated note names the one setting to change and
  the line to paste. You change it.
- **Moved** — nothing to configure, because the path it is found by did not
  change.

| Ruby | Found by | Lands at | Support |
|---|---|---|---|
| RSpec | `rspec-rails`, `rspec` | `test/rspec` | Verified |
| Cucumber | `cucumber-rails`, `cucumber` | `test/cucumber/features` | Verified |
| Minitest / Rails default | `minitest`, `minitest-rails` | `test/minitest/*` | Verified\* |
| Capybara | `capybara` | `test/rspec/system`, `test/system` | Configured |
| VCR | `vcr` | `test/data/cassettes` | Configured |
| SimpleCov | `simplecov` | `test/results/coverage` | Configured |
| Test::Unit | `test-unit` | `test/unit` | Moved |
| Aruba | `aruba` | `test/cucumber/aruba` | Moved |

\* Minitest has no config to rewrite. Rails' `test` task globs the whole of
`test/`, and the move stays inside it.

| JavaScript | Found by | Lands at | Support |
|---|---|---|---|
| Jest | `jest` | `test/javascript/jest` | Verified\*\* |
| Jasmine | `jasmine`, `jasmine-core` | `test/javascript/jasmine` | Verified\*\* |
| Vitest | `vitest` | `test/javascript/vitest` | Guided |
| Playwright | `@playwright/test`, `playwright` | `test/javascript/playwright` | Guided |
| Cypress | `cypress` | `test/javascript/cypress` | Guided |
| Karma | `karma` | `test/javascript/karma` | Guided |

\*\* Counted through a single `npm test`, because script names are the project's
own and guessing at a runner command is worse than using the entry point the
project declared. Verification is therefore only as good as what that script
drives: a jest suite `npm test` does not reach is moved but unproven.

The shared asset kinds are all Configured — factories, fixtures, attribute sets,
exemplars, seeds, support helpers and reports are moved and then wired at
runtime, since their locations are settings rather than text in a file.

Guided is a deliberate stop, not a gap waiting to be filled; see
[What it does not do](#what-it-does-not-do).

## How the frameworks are told where to look

| Framework | Mechanism |
|---|---|
| RSpec | `--default-path` in `.rspec`, regenerated from your original options |
| Cucumber | feature paths substituted inside your existing `cucumber.yml` |
| Jest and friends | path strings rewritten in `package.json`, through a JSON round trip |
| Jasmine | `spec_dir` rewritten in `jasmine.json`, which is where jasmine keeps it |
| Rails fixtures | `ActiveSupport::TestCase.fixture_paths`, overridden as a reader from the railtie, because `rails/test_help` appends the default path from a hook that runs later |
| FactoryBot | `FactoryBot.definition_file_paths` |
| VCR | `cassette_library_dir` |
| SimpleCov | `coverage_dir` |
| Capybara | `save_path` for screenshots |

## Your edits are never overwritten

No config file is ever replaced wholesale. Oubliette reads what is on disk now,
changes only the lines it is responsible for, and comments the original out
rather than deleting it:

```
--require spec_helper
# >>> oubliette >>>
# the spec tree moved to test/rspec, and rspec reads from a single default path.
# the `was:` line below is yours, commented out rather than deleted.
# `rake oubliette:rollback` removes this block and leaves the rest of the file alone.
# was: --default-path spec
--default-path test/rspec
# <<< oubliette <<<
--color
```

Rolling back uncomments the `was:` line and drops the rest of the block.
Everything outside it is never read and never rewritten, so an edit made after
the migration survives -- which a design that restored a snapshot taken before it
could not manage.

JSON has nowhere to put a comment, so `package.json` and `jasmine.json` are
handled differently: the exact quoted strings that name a relocated directory are
replaced where they stand, and rollback runs the same substitution backwards.
Formatting, key order and every setting oubliette does not manage are left byte
for byte as they were.

## What it does not do

Vitest, Playwright, Cypress and Karma are detected and moved, but their config
files are not rewritten: those keep their paths in a javascript module rather
than in JSON, and there is no round trip that cannot corrupt a module. RSpec,
Cucumber, Jest and Jasmine are rewritten for you.

For the four it will not touch, oubliette writes the instructions instead. A
`cypress.config.js` gets a `test/oubliette/cypress.config.js.md` naming the move,
the setting to change, and the line to paste:

```js
// after
e2e: { specPattern: "test/javascript/cypress/**/*" }
```

The note is treated as a config file oubliette owns, so `rake oubliette:rollback`
deletes it along with putting the directories back -- but only while it still says
exactly what oubliette wrote. A guide is a natural place to jot down what you
worked out while following it, so an edited one is kept and named in the report
instead. The run also lists them under "CONFIG YOU MUST UPDATE BY HAND" so they
are not discovered by surprise.

Oubliette rewrites framework configuration and repairs ruby's `require_relative`
when a directory changes depth. It does not rewrite application code, and it does
not repair javascript's `require` or `import` -- a jest test that reaches its
subject through `../../app/javascript/thing` will be one level out after the move.
Anchor those to the project root, or fix them by hand; the stale-reference report
will not catch them either, because a relative path does not name the directory
that moved.

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

`bin/playground` builds a durable application to try the gem against by hand: two
CRUD models, javascript with both unit-testable logic and a clickable counter,
the Administrate engine with its own stimulus controllers, and one passing suite
per framework -- rspec model, request and system specs, three of Administrate's
own `:js` specs ported onto the local models and driven in headless Chrome,
cucumber scenarios, minitest with fixtures, a spec in the legacy `test/unit`
location, a VCR cassette, and the same javascript behaviour covered twice, once
in jest and once in jasmine. Oubliette is left commented out in its Gemfile so
the install can be demonstrated.

`bin/full-pass [build-dir]` runs everything in sequence and prints a pass/fail
table: the gem's own suite and rubocop, `bin/e2e`, a regenerated playground, and
then, from inside that application, every suite before and after a migration, a
rollback, a second migration, `rake oubliette:selftest`, and the layout spec
installed by `rake oubliette:install_specs`.

`bin/e2e /some/build/dir` goes further: it generates a brand new Rails
application with RSpec, Cucumber, Minitest, FactoryBot, Capybara, VCR, SimpleCov
and Jest installed, proves `rspec`, `cucumber` and `bin/rails test` all pass,
migrates it, proves they still pass, and then rolls the whole thing back.

## Safety

Oubliette refuses to move anything while the working tree has unstaged or
untracked changes (`FORCE=1` overrides). Generated directories it knows about --
`coverage/` above all -- should be in `.gitignore`, or the first SimpleCov run
will block the next migration. Moves go through `git mv` where git
will take them, so history follows the files.
