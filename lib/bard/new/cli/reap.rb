require "bard/new/staging_reaper"

class Bard::CLI
  option :ttl, type: :numeric, desc: "days of idleness before a site counts as stale (default: #{Bard::StagingReaper::DEFAULT_TTL_DAYS})"
  desc "reap", "audits staging sites: which have auto-destruct armed, which look stale. Never deletes."
  def reap
    target = config[:staging]
    target.require_capability!(:ssh)

    reaper = Bard::StagingReaper.new(ttl_days: options[:ttl] || Bard::StagingReaper::DEFAULT_TTL_DAYS)
    unit = Bard::StagingReaper::UNIT

    # Left on the box so it can be re-run by hand over ssh, not just through bard.
    target.run! "mkdir -p ~/.local/state/bard", home: true
    target.run! "cat > ~/.local/state/bard/#{unit}.sh <<'BARD_EOF'\n#{reaper.script}BARD_EOF", home: true
    target.run! "chmod +x ~/.local/state/bard/#{unit}.sh", home: true

    puts target.run!(reaper.script_path, home: true, capture: true)
  end
end
