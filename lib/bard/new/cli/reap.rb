require "bard/config"
require "bard/new/site_removal"
require "shellwords"

class Bard::CLI
  DEFAULT_STAGING_TTL_DAYS = 7

  option :"dry-run", type: :boolean, default: false, desc: "report only; reap nothing"
  option :ttl, type: :numeric, desc: "days of idleness before a site is reaped (default: #{DEFAULT_STAGING_TTL_DAYS})"
  option :force, type: :boolean, default: false, desc: "run even when RAILS_ENV is not staging"
  desc "reap", "reaps idle ephemeral staging sites under $HOME (run on the staging server)"
  def reap
    unless ENV["RAILS_ENV"] == "staging" || options[:force]
      raise Thor::Error.new("`bard reap` refuses to run outside a staging environment (RAILS_ENV=staging). Pass --force to override.")
    end

    ttl = (options[:ttl] || DEFAULT_STAGING_TTL_DAYS).to_f
    reaped, left, unknown, issues = [], [], [], []

    reap_candidates.each do |name|
      dir = File.join(Dir.home, name)

      missing = reap_missing_files(dir)
      if missing.any?
        issues << [name, "missing #{missing.join(", ")}"]
        next
      end

      status, reason = reap_classify(dir, name)
      case status
      when :permanent
        unknown << [name, "no distinct production target — treated as permanent"]
      when :unknown
        unknown << [name, reason]
      when :ephemeral
        age = reap_idle_days(dir)
        if age >= ttl
          Bard::SiteRemoval.new(dir).call unless options[:"dry-run"]
          reaped << [name, age]
        else
          left << [name, ttl - age]
        end
      end
    end

    reap_print_report(reaped, left, unknown, issues)
    exit 1 if issues.any?
  end

  no_commands do
    def reap_candidates
      Dir.children(Dir.home)
        .reject { |e| e.start_with?(".") }
        .select { |e| File.directory?(File.join(Dir.home, e)) }
        .sort
    end

    def reap_missing_files(dir)
      %w[bard.rb .git].reject { |f| File.exist?(File.join(dir, f)) }
    end

    # A site is ephemeral (reapable) only if its authoritative config — the repo's
    # origin/master:bard.rb, not the possibly-stale local checkout — declares a
    # production distinct from staging. Anything else is left untouched.
    def reap_classify(dir, name)
      source = reap_origin_bard_rb(dir)
      return [:unknown, "could not read origin/master:bard.rb"] if source.nil? || source.strip.empty?
      cfg = Bard::Config.new(name, source: source)
      cfg[:production] == cfg[:staging] ? [:permanent, nil] : [:ephemeral, nil]
    rescue StandardError, ScriptError => e
      [:unknown, "error reading config: #{e.message.lines.first&.strip}"]
    end

    def reap_origin_bard_rb(dir)
      system("git -C #{Shellwords.escape(dir)} fetch -q origin master", out: File::NULL, err: File::NULL)
      `git -C #{Shellwords.escape(dir)} show origin/master:bard.rb 2>/dev/null`
    end

    def reap_idle_days(dir)
      marker = File.join(dir, "tmp", "restart.txt")
      marker = File.join(dir, ".git") unless File.exist?(marker)
      (Time.now - File.mtime(marker)) / 86400.0
    end

    def reap_print_report(reaped, left, unknown, issues)
      verb = options[:"dry-run"] ? "Would reap" : "Reaped"
      puts
      puts green("#{verb} (#{reaped.size})")
      reaped.sort_by(&:first).each { |name, age| puts "  #{name}  (idle #{reap_fmt_days(age)})" }
      puts "Left (#{left.size})"
      left.sort_by(&:first).each { |name, remaining| puts "  #{name}  (reaps in #{reap_fmt_days(remaining)})" }
      puts "Unknown (#{unknown.size})"
      unknown.sort_by(&:first).each { |name, reason| puts "  #{name}  (#{reason})" }
      if issues.any?
        puts red("Issues (#{issues.size})")
        issues.sort_by(&:first).each { |name, reason| puts "  #{name}  (#{reason})" }
      end
    end

    def reap_fmt_days(days)
      d = days.floor
      h = ((days - d) * 24).floor
      d > 0 ? "#{d}d #{h}h" : "#{h}h"
    end
  end
end
