require "spec_helper"
require "open3"
require "fileutils"
require "tmpdir"

# Exercises the real `bard reap` command end-to-end against a seeded $HOME of
# actual git repos: the classifier really fetches each site's origin/master:bard.rb
# and the report buckets are produced for real. Runs --dry-run so nothing is
# destroyed (no sudo/nginx/rm), which is what makes it safe to run on a dev box.
describe "bard reap (integration)", :slow do
  let(:home) { Dir.mktmpdir("bard-reap-home") }
  let(:root) { File.expand_path("../../..", __dir__) }

  after { FileUtils.remove_entry(home) if File.exist?(home) }

  def git(dir, *args)
    system("git", "-C", dir, "-c", "user.email=t@example.com", "-c", "user.name=Tester",
           *args, out: File::NULL, err: File::NULL) or raise "git #{args.join(' ')} failed"
  end

  # Creates ~/<name> as a git checkout whose origin/master holds the given bard.rb.
  def seed_site(name, bard_rb:, staged_days_ago:)
    dir = File.join(home, name)
    origin = File.join(home, ".origins", "#{name}.git")
    FileUtils.mkdir_p(origin)
    system("git", "init", "--bare", "-q", origin, out: File::NULL, err: File::NULL)

    FileUtils.mkdir_p(dir)
    git(dir, "init", "-q", "-b", "master")
    File.write(File.join(dir, "bard.rb"), bard_rb)
    git(dir, "add", "-A")
    git(dir, "commit", "-qm", "seed")
    git(dir, "remote", "add", "origin", origin)
    git(dir, "push", "-q", "origin", "master")

    if staged_days_ago
      FileUtils.mkdir_p(File.join(dir, "tmp"))
      restart = File.join(dir, "tmp", "restart.txt")
      FileUtils.touch(restart)
      t = Time.now - staged_days_ago * 86_400
      File.utime(t, t, restart)
    end
    dir
  end

  let(:distinct_production) do
    <<~RUBY
      target :production do
        ssh "deploy@prod.example.com:22022"
      end
    RUBY
  end

  # HOME is overridden only for the bard process (not the login shell), so rvm
  # still resolves from the real home and the bard-new gemset activates on cd.
  def run_reap(rails_env: "staging", flags: "--dry-run")
    Open3.capture2e("bash", "-lc",
      "cd #{root} && HOME=#{home} RAILS_ENV=#{rails_env} bundle exec bard reap #{flags}")
  end

  it "reaps ripe ephemeral sites, keeps fresh ones, and flags permanents and broken dirs" do
    seed_site("ripe",  bard_rb: distinct_production, staged_days_ago: 9)
    seed_site("fresh", bard_rb: distinct_production, staged_days_ago: 1)
    seed_site("perm",  bard_rb: "# permanent resident, no production\n", staged_days_ago: 30)
    FileUtils.mkdir_p(File.join(home, "broken")) # no bard.rb / .git

    out, status = run_reap

    expect(out).to match(/Would reap \(1\).*\bripe\b/m)
    expect(out).to match(/Left \(1\).*\bfresh\b/m)
    expect(out).to match(/Unknown \(1\).*\bperm\b/m)
    expect(out).to match(/Issues \(1\).*\bbroken\b/m)
    expect(status.exitstatus).to eq(0) # issues are flagged but not fatal
  end

  it "refuses to run outside a staging environment" do
    out, status = run_reap(rails_env: "development")
    expect(out).to match(/refuses to run outside a staging environment/)
    expect(status.exitstatus).not_to eq(0)
  end
end
