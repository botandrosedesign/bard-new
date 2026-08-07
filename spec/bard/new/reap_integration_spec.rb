require "spec_helper"
require "open3"
require "fileutils"
require "tmpdir"

# Runs the real generated reaper script against a seeded $HOME of actual git repos.
# This is the artifact that ships to the staging box, so it is exercised as bash --
# no ruby, no gems -- exactly as systemd will run it. Uses --dry-run so nothing is
# destroyed, which is what makes it safe to run on a dev machine.
describe "the staging reaper script", :slow do
  let(:home) { Dir.mktmpdir("bard-reap-home") }
  let(:script) { File.join(home, "bard-reap.sh") }

  before do
    File.write(script, Bard::StagingReaper.new.script)
    FileUtils.chmod(0o755, script)
  end

  after { FileUtils.remove_entry(home) if File.exist?(home) }

  def git(dir, *args)
    system("git", "-C", dir, "-c", "user.email=t@example.com", "-c", "user.name=Tester",
           *args, out: File::NULL, err: File::NULL) or raise "git #{args.join(' ')} failed"
  end

  # Creates ~/<name> as a git checkout whose origin/master holds the given bard.rb.
  def seed_site(name, bard_rb:, idle_days: nil)
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

    if idle_days
      t = Time.now - idle_days * 86_400
      git_log = File.join(dir, ".git", "logs", "HEAD")
      File.utime(t, t, git_log) if File.exist?(git_log)
      marker_dir = File.join(home, ".local", "state", "bard")
      FileUtils.mkdir_p(marker_dir)
      marker = File.join(marker_dir, "#{name}.synced")
      FileUtils.touch(marker)
      File.utime(t, t, marker)
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

  def run_reaper(*args, rails_env: "staging")
    Open3.capture2e({ "HOME" => home, "RAILS_ENV" => rails_env }, "bash", script, *args)
  end

  it "reaps ripe ephemeral sites, keeps fresh ones, and flags permanents and broken dirs" do
    seed_site("ripe",  bard_rb: distinct_production, idle_days: 9)
    seed_site("fresh", bard_rb: distinct_production, idle_days: 1)
    seed_site("perm",  bard_rb: "# permanent resident, no production\n", idle_days: 30)
    FileUtils.mkdir_p(File.join(home, "broken")) # no bard.rb / .git

    out, status = run_reaper("--dry-run")

    expect(out).to match(/Would reap \(1\).*\bripe\b/m)
    expect(out).to match(/Left \(1\).*\bfresh\b/m)
    expect(out).to match(/Unknown \(1\).*\bperm\b/m)
    expect(out).to match(/Issues \(1\).*\bbroken\b/m)
    expect(status.exitstatus).to eq(0)
  end

  it "leaves every site in place on a dry run" do
    seed_site("ripe", bard_rb: distinct_production, idle_days: 30)
    run_reaper("--dry-run")
    expect(File.directory?(File.join(home, "ripe"))).to be(true)
  end

  it "honours --ttl" do
    seed_site("recent", bard_rb: distinct_production, idle_days: 3)
    out, _ = run_reaper("--dry-run", "--ttl=2")
    expect(out).to match(/Would reap \(1\).*\brecent\b/m)
  end

  it "refuses to run outside a staging environment" do
    out, status = run_reaper("--dry-run", rails_env: "development")
    expect(out).to match(/refusing to run outside a staging environment/)
    expect(status.exitstatus).to eq(1)
  end

  it "is valid bash" do
    _, status = Open3.capture2e("bash", "-n", script)
    expect(status.exitstatus).to eq(0)
  end
end
