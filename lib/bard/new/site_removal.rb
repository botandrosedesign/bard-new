require "shellwords"

module Bard
  # Tears down a single deployed site rooted at `dir`: stops its services, drops
  # its database, removes its nginx site and rvm gemset, and deletes the directory.
  # Shared by `bard destroy` (which runs the steps over a target, remote or local)
  # and `bard reap` / `bard remove` (which run them locally). Exposed as ordered
  # [label, shell-command] steps so each caller executes them in its own context.
  class SiteRemoval
    def initialize(dir = Dir.pwd)
      @dir = dir.to_s
      @name = File.basename(@dir)
    end

    def steps
      [
        ["stopping services",          stop_services_script],
        ["dropping database",          drop_database_script],
        ["removing nginx site",        remove_nginx_script],
        ["removing rvm gemset",        remove_gemset_script],
        ["removing project directory", "rm -rf #{@dir}"],
      ]
    end

    # Run the teardown locally and quietly (used by `bard reap` and `bard remove`).
    def call
      steps.each { |_, script| system("( #{script} ) >/dev/null 2>&1") }
    end

    private

    def stop_services_script
      data_reap = "bard-data-reap-#{@name}"
      [
        "systemctl --user stop #{@name}.target 2>/dev/null || true",
        "systemctl --user disable #{@name}.target 2>/dev/null || true",
        "rm -f ~/.config/systemd/user/#{@name}*.service ~/.config/systemd/user/#{@name}.target",
        "rm -rf ~/.config/systemd/user/#{@name}.target.wants",
        # `bard data` arms this per-project data-expiry timer; without this it would
        # outlive the site and fire daily against a deleted directory.
        "systemctl --user disable --now #{data_reap}.timer 2>/dev/null || true",
        "rm -f ~/.config/systemd/user/#{data_reap}.timer ~/.config/systemd/user/#{data_reap}.service",
        "rm -f ~/.local/state/bard/#{data_reap}.sh ~/.local/state/bard/#{@name}.synced",
        "systemctl --user daemon-reload 2>/dev/null || true",
      ].join("; ")
    end

    # Login shell + cd so rvm activates the app's own gemset/ruby before rake runs;
    # ambient RAILS_ENV picks the right database. Best-effort (no-op for sqlite).
    def drop_database_script
      "bash -lc #{Shellwords.escape("cd #{@dir} && bin/rake db:drop")} >/dev/null 2>&1 || true"
    end

    def remove_nginx_script
      "sudo rm -f /etc/nginx/sites-available/#{@name} /etc/nginx/sites-enabled/#{@name}; sudo service nginx reload || true"
    end

    # Reads the checkout's own ruby so it removes the right gemset regardless of
    # which ruby the site was built with (staging sites vary).
    def remove_gemset_script
      "env -i bash -lc 'source ~/.rvm/scripts/rvm && rvm --force gemset delete \"$(cat #{@dir}/.ruby-version 2>/dev/null)@#{@name}\" || true'"
    end
  end
end
