# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this gem is

`bard-new` is a plugin for the `bard` CLI gem (sibling repo at `../bard`). It adds two subcommands:

- `bard new <project-name>` — scaffolds a new Rails app using `lib/bard/new/rails_template.rb`, optionally pushes to GitHub and stages a deploy.
- `bard provision [ssh_url]` — idempotently provisions a fresh Ubuntu 24.04 host into a production target, step by step.

The plugin entry point is `lib/bard/plugins/new.rb`. The parent `bard` gem's plugin loader auto-requires it (by convention); the gemspec depends on `bard`.

## Architecture

### CLI layer (`lib/bard/new/cli/`)
Reopens `Bard::CLI` (a Thor subclass from the `bard` gem) and adds `new` and `provision` commands. `new.rb` shells out to `env -i bash -lc` + RVM to run `rails new` with the template; `provision.rb` iterates over `PROVISION_STEPS` and dispatches each to a `Bard::Provision::<Step>` class.

### Provision steps (`lib/bard/new/provision/`)
Each step is a `Struct.new(:config, :ssh_url)` subclass of `Bard::Provision` (see `base.rb`) implementing `#call`. Steps are **idempotent** — they check current state before acting (e.g. `Nginx#http_responding?`, `SSH#password_auth_enabled?`) and print ` ✓` at the end. `provision_server` returns a duped target whose `ssh` points at the raw `ssh_url` being provisioned; `target` is the final production target from `bard.rb`. The order in `PROVISION_STEPS` matters (SSH → User → AuthorizedKeys → ... → Data).

### Rails template (`lib/bard/new/rails_template.rb`)
Drives `rails new -m` — generates Gemfile (bard-rails, solid_*, sprockets+dartsass, importmap/turbo/stimulus, exception_notification, puma), writes `Procfile`, adds a `bootstrap` rake task that does `db:prepare` + (in production) `assets:precompile` + `foreman export systemd-user` + `systemctl --user restart`, and runs `bard install && bin/setup && bard setup` after bundle. Reads `ruby_version` and `project_name` from the current `rvm current name`.

### Test infrastructure
Both cucumber features spin up a real **Podman** container (via `docker-api` against the podman socket) using `spec/acceptance/docker/Dockerfile.{new,provision}`, then SSH in with `spec/acceptance/docker/test_key`. The `@new` tag gives a deploy-ready Ubuntu + RVM + pre-installed bard/bard-new gems for exercising `bard new`. The `@provision` tag gives a raw-ish Ubuntu + systemd for exercising the provision steps end-to-end; the `Dockerfile.provision` build context is the **parent directory** so it can `COPY bard/ ...` from the sibling repo.

Coverage is written by both cucumber (`features/support/env.rb`) and rspec (`spec/spec_helper.rb`) via SimpleCov — the cucumber runs shell out through `features/support/bard-coverage`, a wrapper that starts SimpleCov before exec'ing the `bard` binary so the subprocess's line coverage is merged in.

## Commands

```bash
# Full suite (default rake task runs both)
bundle exec rake

# Unit specs only
bundle exec rspec
bundle exec rspec spec/bard/new/provision/nginx_spec.rb  # single file

# Cucumber — tags select which container gets built/started
bundle exec cucumber features/new.feature          # @new tag
bundle exec cucumber features/provision.feature    # @provision tag
```

Cucumber runs are slow (they build and boot containers). Per global rules: **always** pipe cucumber output to a uniquely-named file in `/tmp/` and grep it, and never run the full cucumber suite speculatively.

Podman must be installed and `systemctl --user start podman.socket` must succeed — the test harness auto-starts it and sets `DOCKER_HOST` to the user socket. The sibling `../bard` checkout must exist because both the Dockerfiles and the `Gemfile` (`gem "bard", path: "../bard"`) reference it.

## Conventions specific to this repo

- Provision step output format is `print "Name:"` → one `print " action,"` per side effect → `puts " ✓"`. Preserve this when adding/editing steps.
- Provision steps MUST be idempotent and check state before acting — they are re-run against already-provisioned servers.
- `provision_server` (raw `ssh_url`) vs `target` (configured production target) is a load-bearing distinction; the SSH step rewrites `ssh_url` to the target port mid-flight so later steps connect to the reconfigured port.
- New provision steps: add the class name to `PROVISION_STEPS` in `lib/bard/new/cli/provision.rb` in the correct order, create `lib/bard/new/provision/<name>.rb` with a `Bard::Provision::<Name>` class, and add `spec/bard/new/provision/<name>_spec.rb`.
- The rails template's Ruby version is hardcoded to `ruby-4.0.2` in `cli/new.rb#new_ruby_version`.
