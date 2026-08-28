# frozen_string_literal: true

require "oubliette"

# Rake claims -n/--dry-run for itself and skips task actions outright, which
# would print nothing useful. When an oubliette task is what was asked for, take
# the flag over and let the task body do the reporting.
if Rake.application.options.dryrun &&
   Rake.application.top_level_tasks.any? { |name| name.start_with?("oubliette") }
  Rake.application.options.dryrun = false
  ENV["OUBLIETTE_DRY_RUN"] = "1"
end

def oubliette_dry_run?
  ENV["OUBLIETTE_DRY_RUN"] == "1" || ENV["DRY_RUN"] == "1"
end

def oubliette_runner(dry_run: oubliette_dry_run?)
  Oubliette::Runner.new(Oubliette.root, dry_run: dry_run, force: ENV["FORCE"] == "1")
end

desc "Move every test asset under test/, sync newly installed frameworks, rewrite config"
task :oubliette do
  oubliette_runner.call
end

namespace :oubliette do
  desc "Write migrate.yml without moving anything, so the targets can be edited first"
  task :prepare do
    oubliette_runner(dry_run: false).prepare
  end

  desc "Show what `rake oubliette` would move and rewrite"
  task :dry_run do
    oubliette_runner(dry_run: true).call
  end

  desc "Report where every test directory currently lives"
  task :status do
    oubliette_runner(dry_run: true).status
  end

  desc "Return directories to their origin, the framework's own default location " \
       "(rollback[gem_name] for one framework)"
  task :rollback, [ :gem ] do |_task, args|
    oubliette_runner.rollback(args[:gem])
  end

  desc "Alias for rollback -- put the directories back where their frameworks expect them"
  task :put_back, [ :gem ] do |_task, args|
    oubliette_runner.put_back(args[:gem])
  end

  desc "Overwrite migrate.yml's targets with oubliette's own defaults, then move to match"
  task :reset, [ :gem ] do |_task, args|
    oubliette_runner.reset(args[:gem])
  end

  desc "Run oubliette's own specs in a process that loads none of this application"
  task :selftest do
    require "oubliette/rspec"

    load_path = File.expand_path("../..", __dir__)
    command = [ "rspec", "--options", File::NULL, "-I", load_path,
                "-r", "oubliette/rspec/standalone_helper", *Oubliette::RSpec.spec_paths ]

    puts command.join(" ")
    abort "oubliette selftest failed" unless system(*command)
  end

  desc "Write the integration spec that checks this project's layout as part of its own suite"
  task :install_specs do
    manifest = Oubliette::Manifest.build(Oubliette.root)
    home = manifest.destination("rspec-rails") || "spec"
    target = Oubliette.root.join(home, "oubliette_spec.rb")

    require "fileutils"
    FileUtils.mkdir_p(target.dirname)
    target.write(<<~RUBY)
      # frozen_string_literal: true

      # Checks that every test directory is where migrate.yml says it is, and
      # that each framework's config agrees. Runs with the rest of the suite.
      #
      # The same expectations run without loading this application at all:
      #
      #   rake oubliette:selftest
      require "oubliette/rspec"

      RSpec.describe "test layout" do
        it_behaves_like "an oubliette-managed project", Rails.root
      end
    RUBY

    puts "wrote #{target.relative_path_from(Oubliette.root)}"
  end
end
