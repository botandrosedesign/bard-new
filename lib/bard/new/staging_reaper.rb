require "bard/new/site_removal"

module Bard
  # Renders a self-contained staging-site reaper: a bash script plus a systemd --user
  # timer, installed onto the staging server. Deliberately gem-free — the staging box
  # has no bard/bard-cli install (see the provision steps), so everything the reaper
  # needs must be plain shell. The teardown commands are generated from SiteRemoval so
  # `bard destroy`, `bard remove` and this reaper stay on one definition.
  class StagingReaper
    UNIT = "bard-reap"
    DEFAULT_TTL_DAYS = 7

    def self.script(ttl_days: DEFAULT_TTL_DAYS) = new(ttl_days:).script
    def self.service_unit = new.service_unit
    def self.timer_unit = new.timer_unit

    def initialize(ttl_days: DEFAULT_TTL_DAYS)
      @ttl_days = ttl_days
    end

    def script_path = "$HOME/.local/state/bard/#{UNIT}.sh"

    # Teardown steps rendered against shell placeholders the loop below fills in.
    def teardown_steps
      SiteRemoval.new('"$dir"', name: '"$name"').steps
    end

    def script
      <<~SH
        #!/usr/bin/env bash
        # Managed by bard-new (bard reap). Reaps idle ephemeral staging sites.
        # Self-contained: needs only git, systemd and coreutils — no ruby, no gems.
        set -u

        TTL_DAYS=#{@ttl_days}
        DRY_RUN=0
        for arg in "$@"; do
          case "$arg" in
            --dry-run) DRY_RUN=1 ;;
            --ttl=*)   TTL_DAYS="${arg#--ttl=}" ;;
            *) echo "usage: $(basename "$0") [--dry-run] [--ttl=DAYS]" >&2; exit 2 ;;
          esac
        done

        # This tears down whole sites; refuse anywhere that is not the staging box.
        if [ "${RAILS_ENV:-}" != "staging" ]; then
          echo "bard-reap: refusing to run outside a staging environment (RAILS_ENV=staging)." >&2
          exit 1
        fi

        STATE="$HOME/.local/state/bard"
        NOW=$(date +%s)
        reaped=(); left=(); unknown=(); issues=()

        for dir in "$HOME"/*/; do
          dir="${dir%/}"
          name="$(basename "$dir")"

          # Report anything that cannot be classified rather than skipping it silently.
          missing=""
          [ -e "$dir/bard.rb" ] || missing="bard.rb"
          [ -e "$dir/.git" ]    || missing="${missing:+$missing, }.git"
          if [ -n "$missing" ]; then
            issues+=("$name|missing $missing")
            continue
          fi

          # Classify from the repo's authoritative config, not the local checkout,
          # which may predate the project gaining a real production target.
          git -C "$dir" fetch -q origin master >/dev/null 2>&1
          cfg="$(git -C "$dir" show origin/master:bard.rb 2>/dev/null)"
          if [ -z "$cfg" ]; then
            unknown+=("$name|could not read origin/master:bard.rb")
            continue
          fi
          # Ephemeral only when a production target distinct from staging is declared.
          # Anything we cannot positively identify is left alone.
          if ! printf '%s\\n' "$cfg" | grep -qE '^[[:space:]]*(target|server)[[:space:]]+:production\\b|^[[:space:]]*github_pages\\b'; then
            unknown+=("$name|no distinct production target — treated as permanent")
            continue
          fi

          # Idle = freshest of git activity and the last `bard data` sync. Both are
          # immune to bot traffic and need no browser visit.
          newest=""
          for f in "$dir/.git/logs/HEAD" "$STATE/$name.synced"; do
            [ -e "$f" ] || continue
            if [ -z "$newest" ] || [ "$f" -nt "$newest" ]; then newest="$f"; fi
          done
          [ -n "$newest" ] || newest="$dir"

          mtime=$(date -r "$newest" +%s 2>/dev/null || echo "$NOW")
          idle_days=$(( (NOW - mtime) / 86400 ))

          if [ "$idle_days" -lt "$TTL_DAYS" ]; then
            left+=("$name|reaps in $(( TTL_DAYS - idle_days ))d")
            continue
          fi

          if [ "$DRY_RUN" -eq 1 ]; then
            reaped+=("$name|idle ${idle_days}d")
            continue
          fi

        #{teardown_steps.map { |label, cmd| "  # #{label}\n  ( #{cmd} ) >/dev/null 2>&1" }.join("\n")}
          reaped+=("$name|idle ${idle_days}d")
        done

        print_section() { # $1 heading, rest: entries
          local heading="$1"; shift
          printf '%s (%s)\\n' "$heading" "$#"
          for entry in "$@"; do
            printf '  %-24s %s\\n' "${entry%%|*}" "${entry#*|}"
          done
        }

        echo
        if [ "$DRY_RUN" -eq 1 ]; then
          print_section "Would reap" ${reaped+"${reaped[@]}"}
        else
          print_section "Reaped" ${reaped+"${reaped[@]}"}
        fi
        print_section "Left"    ${left+"${left[@]}"}
        print_section "Unknown" ${unknown+"${unknown[@]}"}
        print_section "Issues"  ${issues+"${issues[@]}"}
      SH
    end

    def service_unit
      <<~UNIT
        [Unit]
        Description=Reap idle ephemeral bard staging sites

        [Service]
        Type=oneshot
        Environment=RAILS_ENV=staging
        ExecStart=%h/.local/state/bard/#{UNIT}.sh
      UNIT
    end

    def timer_unit
      <<~UNIT
        [Unit]
        Description=Run the bard staging site reaper daily

        [Timer]
        OnCalendar=daily
        Persistent=true

        [Install]
        WantedBy=timers.target
      UNIT
    end
  end
end
