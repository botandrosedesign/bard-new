class Bard::CLI
  no_commands do
    # Called by bard core's `stage` after a successful staging deploy. Arms the
    # ephemeral-staging autodestruct and, when the site was rebuilt from scratch,
    # offers to restore its data from production.
    def after_stage(target, restored:)
      arm_autodestruct(target)

      if restored
        puts "#{project_name} was rebuilt from scratch; its database and files are empty."
        if $stdin.tty? && yes?("Restore #{project_name}'s data from production now? (bard data --from production --to staging) [y/N]")
          invoke :data, [], from: "production", to: "staging"
        else
          puts "Run #{yellow("bard data --from production --to staging")} to restore its data."
        end
      end
    end

    # Resets the reap clock (via tmp/restart.txt, which also triggers Passenger's
    # reload) and idempotently installs the box-wide reaper timer. The first stage
    # after this ships bootstraps the reaper for every site on the staging box.
    def arm_autodestruct(target)
      target.run! "mkdir -p tmp && touch tmp/restart.txt"
      target.run! reaper_install_script, home: true
      puts "#{project_name} staging self-destructs after #{DEFAULT_STAGING_TTL_DAYS} days idle unless re-staged."
    end

    # Pinned to ruby-3.3.4@bard-reap: the staging box's default gemset is ruby
    # 3.1.3, but bard requires >= 3.3, so the timer can't run reap from the default.
    def reaper_install_script
      <<~'SH'
        mkdir -p ~/.config/systemd/user
        cat > ~/.config/systemd/user/bard-reap.service <<'UNIT'
        [Unit]
        Description=Reap idle ephemeral bard staging sites

        [Service]
        Type=oneshot
        ExecStartPre=/bin/bash -lc 'rvm use ruby-3.3.4@bard-reap --create && gem install bard-new'
        ExecStart=/bin/bash -lc 'rvm use ruby-3.3.4@bard-reap && bard reap'
        UNIT
        cat > ~/.config/systemd/user/bard-reap.timer <<'UNIT'
        [Unit]
        Description=Daily reap of idle ephemeral bard staging sites

        [Timer]
        OnCalendar=daily
        Persistent=true

        [Install]
        WantedBy=timers.target
        UNIT
        sudo loginctl enable-linger "$USER"
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        systemctl --user daemon-reload
        systemctl --user enable --now bard-reap.timer
      SH
    end
  end
end
