# bard-new

A plugin for the [bard](https://github.com/botandrose/bard) CLI that scaffolds new Rails projects and provisions Ubuntu servers into Bot & Rose production targets.

Adds two subcommands:

- `bard new <project-name>` — scaffold a new Rails app, push it to GitHub, and stage a deploy.
- `bard provision [ssh_url]` — idempotently provision a fresh Ubuntu 24.04 host into a production target.

## Installation

```bash
gem install bard-new
```

The parent `bard` gem auto-requires installed plugins by convention, so the new commands appear under `bard --help` once the gem is installed.

## `bard new`

```bash
bard new my_project
```

Steps:

1. Validates the project name (lowercase letters and digits only, must start with a letter).
2. Creates an RVM gemset (`ruby-4.0.2@<project-name>`) and installs Rails (`~> 8.1.0`).
3. Runs `rails new` against [`lib/bard/new/rails_template.rb`](lib/bard/new/rails_template.rb), which:
   - writes a Gemfile with `bard-rails`, `solid_*`, sprockets + dartsass, importmap/turbo/stimulus, `exception_notification`, and `puma`
   - writes a `Procfile`
   - adds a `bootstrap` rake task (runs `db:prepare`, and in production runs `assets:precompile`, exports systemd-user units via `foreman`, and restarts the service)
   - runs `bard install && bin/setup && bard setup`
4. Creates a private GitHub repo, pushes the initial commit, uploads `config/master.key` as an Actions secret, and enables branch protection on `master`.
5. Stages the new project (`bard deploy --clone`).

Options:

- `--skip-github` — skip GitHub repo creation and push.
- `--skip-stage` — skip the staging deploy.

## `bard provision`

```bash
bard provision deploy@new-server.example.com:22
```

If `ssh_url` is omitted, the `:production` target's SSH URL from `bard.rb` is used.

The command iterates through the provisioning steps in order and dispatches each to a class under `Bard::Provision`. Every step is **idempotent** — it inspects current state and skips work that's already done — so re-running against a partially or fully provisioned host is safe.

| Step             | What it does                                                                 |
|------------------|------------------------------------------------------------------------------|
| `SSH`            | Hardens sshd, switches to the port configured on the production target.     |
| `User`           | Creates the deploy user.                                                    |
| `AuthorizedKeys` | Installs SSH keys.                                                          |
| `Swapfile`       | Allocates a swapfile.                                                       |
| `Apt`            | Installs base system packages.                                              |
| `MySQL`          | Installs and configures MySQL, creates the app database and user.           |
| `Repo`           | Clones the application repo into the deploy path.                           |
| `MasterKey`      | Installs `config/master.key`.                                               |
| `RVM`            | Installs RVM and the project's Ruby version.                                |
| `App`            | Runs `bin/setup` / app bootstrap.                                           |
| `Nginx`          | Installs and configures nginx + TLS.                                        |
| `Deploy`         | Performs the initial deploy.                                                |
| `HTTP`           | Verifies the site responds.                                                 |
| `LogRotation`    | Configures logrotate.                                                       |
| `Data`           | Syncs initial data.                                                         |

Options:

- `--steps step1 step2 …` — run only a subset of steps (names match the table above).

## Development

The test suite uses real Podman containers to exercise both commands end-to-end. You need:

- Podman with the user socket enabled: `systemctl --user start podman.socket`

```bash
bundle install

# Full suite (rspec + cucumber)
bundle exec rake

# Unit specs
bundle exec rspec
bundle exec rspec spec/bard/new/provision/nginx_spec.rb

# Cucumber — tags select which container image gets built
bundle exec cucumber features/new.feature        # @new
bundle exec cucumber features/provision.feature  # @provision
```

Cucumber runs are slow because they build and boot containers; run individual features rather than the full suite.

## Adding a provision step

1. Add the class name to `PROVISION_STEPS` in [`lib/bard/new/cli/provision.rb`](lib/bard/new/cli/provision.rb) at the correct position — ordering matters (e.g. `SSH` must run before `User`, which must run before `AuthorizedKeys`).
2. Create `lib/bard/new/provision/<name>.rb` defining `Bard::Provision::<Name>` as a subclass of `Bard::Provision` (a `Struct.new(:config, :ssh_url)`) with a `#call` method.
3. Make `#call` idempotent — check current state before making changes.
4. Follow the output convention: `print "Name:"`, then one `print " action,"` per side effect, then `puts " ✓"`.
5. Use `provision_server` to SSH to the host being provisioned (raw `ssh_url`) and `target` for the final production target from `bard.rb`. The `SSH` step rewrites `ssh_url` to the configured port mid-flight, so later steps connect to the reconfigured host.
6. Add `spec/bard/new/provision/<name>_spec.rb`.

## License

MIT. Copyright (c) Micah Geisel.
