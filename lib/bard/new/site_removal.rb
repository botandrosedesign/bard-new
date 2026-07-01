require "fileutils"
require "shellwords"

module Bard
  # Knows how to tear down an app's process-supervision units, whatever
  # supervisor the project uses. Passenger-served staging sites have none, so
  # every backend is a safe no-op there.
  class ProcessManager
    def self.for(dir)
      if File.exist?(File.join(dir, "procsd.yml"))
        Procsd.new(dir)
      else
        SystemdUser.new(dir)
      end
    end

    attr_reader :dir, :name

    def initialize(dir)
      @dir = dir
      @name = File.basename(File.expand_path(dir))
    end

    def teardown_command
      raise NotImplementedError
    end

    class SystemdUser < ProcessManager
      def teardown_command
        [
          "systemctl --user stop #{name}.target 2>/dev/null || true",
          "systemctl --user disable #{name}.target 2>/dev/null || true",
          "rm -f ~/.config/systemd/user/#{name}*.service ~/.config/systemd/user/#{name}.target",
          "rm -rf ~/.config/systemd/user/#{name}.target.wants",
          "systemctl --user daemon-reload 2>/dev/null || true",
        ].join("; ")
      end
    end

    class Procsd < ProcessManager
      def teardown_command
        "cd #{Shellwords.escape(dir)} && procsd destroy 2>/dev/null || true"
      end
    end
  end

  # Removes a single deployed site living at `dir` on the local machine: stops
  # its processes, drops its database, removes its nginx site, and deletes the
  # directory. Shared by `bard remove`, `bard reap`, and (over SSH) `bard destroy`.
  class SiteRemoval
    Result = Struct.new(:name, :db_dropped, keyword_init: true)

    attr_reader :dir, :name

    def initialize(dir = Dir.pwd)
      @dir = File.expand_path(dir)
      @name = File.basename(@dir)
    end

    def call
      stop_processes
      db_dropped = drop_database
      remove_nginx_site
      remove_directory
      Result.new(name: name, db_dropped: db_dropped)
    end

    private

    def stop_processes
      sh ProcessManager.for(dir).teardown_command
    end

    # Best-effort: the crown jewel (master key) is removed regardless below, but
    # for non-sqlite adapters the data lives outside the directory and must be
    # dropped explicitly. Runs in a login shell so rvm activates the app's own
    # gemset/ruby on cd; uses the ambient RAILS_ENV to target the right database.
    def drop_database
      sh "bash -lc #{Shellwords.escape("cd #{dir} && bin/rake db:drop")} >/dev/null 2>&1"
    end

    def remove_nginx_site
      sh "sudo rm -f /etc/nginx/sites-available/#{name} /etc/nginx/sites-enabled/#{name}"
      sh "sudo service nginx reload || true"
    end

    def remove_directory
      FileUtils.rm_rf(dir)
    end

    def sh(command)
      system(command)
    end
  end
end
