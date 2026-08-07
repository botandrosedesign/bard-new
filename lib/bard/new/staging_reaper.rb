module Bard
  # A read-only audit of every site on the staging server: which have auto-destruct
  # armed, which look like stale candidates, which are permanent. Deliberately gem-free
  # (the staging box has no bard install) and deliberately non-destructive -- removal is
  # each site's own opt-in `autodestruct` timer. Its classification is a heuristic, which
  # is fine precisely because nothing acts on it: a human reads the report and decides.
  class StagingReaper
    UNIT = "bard-audit"
    DEFAULT_TTL_DAYS = 7

    def self.script(...) = new(...).script

    def initialize(ttl_days: DEFAULT_TTL_DAYS)
      @ttl_days = ttl_days
    end

    def script_path = "$HOME/.local/state/bard/#{UNIT}.sh"

    def script
      <<~SH
        #!/usr/bin/env bash
        # Managed by bard-new (bard reap). Reports on staging sites. Never deletes anything.
        set -u

        TTL_DAYS=#{@ttl_days}
        for arg in "$@"; do
          case "$arg" in
            --ttl=*) TTL_DAYS="${arg#--ttl=}" ;;
            *) echo "usage: $(basename "$0") [--ttl=DAYS]" >&2; exit 2 ;;
          esac
        done

        STATE="$HOME/.local/state/bard"
        NOW=$(date +%s)
        armed=(); candidates=(); active=(); permanent=(); issues=()

        for dir in "$HOME"/*/; do
          dir="${dir%/}"
          name="$(basename "$dir")"

          missing=""
          [ -e "$dir/bard.rb" ] || missing="bard.rb"
          [ -e "$dir/.git" ]    || missing="${missing:+$missing, }.git"
          if [ -n "$missing" ]; then
            issues+=("$name|missing $missing")
            continue
          fi

          # Idle: freshest of git activity and the last `bard data` sync.
          newest=""
          for f in "$dir/.git/logs/HEAD" "$STATE/$name.synced"; do
            [ -e "$f" ] || continue
            if [ -z "$newest" ] || [ "$f" -nt "$newest" ]; then newest="$f"; fi
          done
          if [ -n "$newest" ]; then
            mtime=$(date -r "$newest" +%s 2>/dev/null || echo "$NOW")
          else
            mtime=$NOW
          fi
          idle_days=$(( (NOW - mtime) / 86400 ))

          if [ -e "$HOME/.config/systemd/user/bard-autodestruct-$name.timer" ]; then
            armed+=("$name|idle ${idle_days}d, autodestruct armed")
            continue
          fi

          if [ "$idle_days" -lt "$TTL_DAYS" ]; then
            active+=("$name|idle ${idle_days}d")
            continue
          fi

          # Advisory only: does the repo's authoritative config declare a production
          # target distinct from staging? If so this site is a cleanup candidate.
          cfg="$(git -C "$dir" show origin/master:bard.rb 2>/dev/null)"
          if [ -n "$cfg" ] && printf '%s\\n' "$cfg" | grep -qE '^[[:space:]]*(target|server)[[:space:]]+:production\\b'; then
            candidates+=("$name|idle ${idle_days}d, has a distinct production")
          else
            permanent+=("$name|idle ${idle_days}d, no distinct production declared")
          fi
        done

        print_section() {
          local heading="$1"; shift
          printf '%s (%s)\\n' "$heading" "$#"
          for entry in "$@"; do
            printf '  %-24s %s\\n' "${entry%%|*}" "${entry#*|}"
          done
        }

        echo
        print_section "Armed"      ${armed+"${armed[@]}"}
        print_section "Candidates" ${candidates+"${candidates[@]}"}
        print_section "Active"     ${active+"${active[@]}"}
        print_section "Permanent"  ${permanent+"${permanent[@]}"}
        print_section "Issues"     ${issues+"${issues[@]}"}
        echo
        echo "This audit never deletes. To make a site ephemeral, add \\`autodestruct <days>\\`"
        echo "to its staging target in bard.rb and run \\`bard stage\\`."
      SH
    end
  end
end
