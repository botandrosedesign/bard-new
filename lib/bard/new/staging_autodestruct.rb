require "bard/new/site_removal"

class Bard::Target
  # Opt-in on a staging target: `autodestruct 7` removes the site after 7 idle days.
  def autodestruct(days = nil)
    days.nil? ? @autodestruct : @autodestruct = days
  end
end

module Bard
  # Per-project staging auto-destruct. `bard stage` arms this on targets that opt in
  # via `autodestruct <days>`; it installs a self-contained bash script and a systemd
  # --user timer on the server. Deliberately gem-free: the staging box has no
  # bard/bard-cli install, so what ships is a rendered string. Teardown comes from
  # SiteRemoval, shared with `bard destroy` and `bard remove`.
  class StagingAutodestruct
    def self.arm(target, project_name)
      days = target.respond_to?(:autodestruct) ? target.autodestruct : nil
      return unless days
      new(target, project_name, days).arm
    end

    attr_reader :target, :name, :days

    def initialize(target, name, days)
      @target = target
      @name = name
      @days = days
    end

    def unit = "bard-autodestruct-#{name}"
    def dir = "$HOME/#{target.path}"

    def arm
      target.run! "mkdir -p ~/.local/state/bard ~/.config/systemd/user", home: true
      write "~/.local/state/bard/#{unit}.sh", script
      target.run! "chmod +x ~/.local/state/bard/#{unit}.sh", home: true
      write "~/.config/systemd/user/#{unit}.service", service_unit
      write "~/.config/systemd/user/#{unit}.timer", timer_unit
      target.run! "sudo loginctl enable-linger \"$USER\"", home: true
      target.run! "systemctl --user daemon-reload && systemctl --user enable --now #{unit}.timer", home: true
      self
    end

    # Teardown rendered against the one site this timer owns.
    def teardown_steps
      SiteRemoval.new(dir, name: name).steps
    end

    def script
      <<~SH
        #!/usr/bin/env bash
        # Managed by bard-new. Removes this staging site once it has gone idle.
        # Self-contained: needs only git, systemd and coreutils -- no ruby, no gems.
        set -u

        DIR="#{dir}"
        NAME="#{name}"
        STATE="$HOME/.local/state/bard"
        IDLE_MIN=$(( #{days} * 1440 ))

        [ -d "$DIR" ] || exit 0

        # Stay alive while EITHER signal is fresh: git activity (commit/checkout/deploy)
        # or the last `bard data` sync. Both are immune to bot traffic and need no visit.
        newest=""
        for f in "$DIR/.git/logs/HEAD" "$STATE/$NAME.synced"; do
          [ -e "$f" ] || continue
          if [ -z "$newest" ] || [ "$f" -nt "$newest" ]; then newest="$f"; fi
        done
        # No activity signal at all: do nothing rather than guess.
        [ -n "$newest" ] || exit 0
        [ -n "$(find "$newest" -maxdepth 0 -mmin +$IDLE_MIN 2>/dev/null)" ] || exit 0

        echo "bard: $NAME has been idle for over #{days} days; removing it."
        #{teardown_steps.map { |label, cmd| "# #{label}\n( #{cmd} ) >/dev/null 2>&1" }.join("\n")}
      SH
    end

    def service_unit
      <<~UNIT
        [Unit]
        Description=Auto-destruct the idle #{name} staging site

        [Service]
        Type=oneshot
        Environment=RAILS_ENV=staging
        ExecStart=%h/.local/state/bard/#{unit}.sh
      UNIT
    end

    def timer_unit
      <<~UNIT
        [Unit]
        Description=Check daily whether the #{name} staging site has gone idle

        [Timer]
        OnCalendar=daily
        Persistent=true

        [Install]
        WantedBy=timers.target
      UNIT
    end

    private

    # A quoted heredoc so $VARS in the payload land on the target verbatim.
    def write(path, content)
      target.run! "cat > #{path} <<'BARD_EOF'\n#{content}BARD_EOF", home: true
    end
  end
end
