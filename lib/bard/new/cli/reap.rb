require "bard/new/staging_reaper"

class Bard::CLI
  option :"dry-run", type: :boolean, default: false, desc: "report only; reap nothing"
  option :ttl, type: :numeric, desc: "days of idleness before a site is reaped (default: #{Bard::StagingReaper::DEFAULT_TTL_DAYS})"
  option :install_only, type: :boolean, default: false, desc: "install/refresh the reaper and timer without sweeping now"
  desc "reap", "installs the staging site reaper on the staging server and sweeps idle ephemeral sites"
  def reap
    target = config[:staging]
    target.require_capability!(:ssh)

    reaper = Bard::StagingReaper.new(ttl_days: options[:ttl] || Bard::StagingReaper::DEFAULT_TTL_DAYS)
    install_reaper(target, reaper)
    return if options[:install_only]

    args = options[:"dry-run"] ? " --dry-run" : ""
    puts target.run!("#{reaper.script_path}#{args}", home: true, capture: true)
  end

  no_commands do
    # The staging box has no bard install, so everything is written as plain shell.
    # Idempotent: re-running just refreshes the script and re-enables the timer.
    def install_reaper(target, reaper)
      unit = Bard::StagingReaper::UNIT
      puts "Installing the staging site reaper on #{target.key}..."
      target.run! "mkdir -p ~/.local/state/bard ~/.config/systemd/user", home: true
      write_remote_file target, "~/.local/state/bard/#{unit}.sh", reaper.script
      target.run! "chmod +x ~/.local/state/bard/#{unit}.sh", home: true
      write_remote_file target, "~/.config/systemd/user/#{unit}.service", reaper.service_unit
      write_remote_file target, "~/.config/systemd/user/#{unit}.timer", reaper.timer_unit
      target.run! "sudo loginctl enable-linger \"$USER\"", home: true
      target.run! "systemctl --user daemon-reload && systemctl --user enable --now #{unit}.timer", home: true
    end

    # A quoted heredoc so $VARS in the payload land on the target verbatim.
    def write_remote_file(target, path, content)
      target.run! "cat > #{path} <<'BARD_EOF'\n#{content}BARD_EOF", home: true
    end
  end
end
