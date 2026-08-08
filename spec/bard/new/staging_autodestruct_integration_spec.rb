require "spec_helper"
require "open3"
require "fileutils"
require "tmpdir"

# Runs the real generated scripts against a seeded $HOME of actual git repos. These are
# the artifacts that ship to the staging box, so they are exercised as bash -- no ruby,
# no gems -- exactly as systemd will run them.
describe "the generated staging auto-destruct script", :slow do
  let(:home) { Dir.mktmpdir("bard-staging-home") }

  after { FileUtils.remove_entry(home) if File.exist?(home) }

  def git(dir, *args)
    system("git", "-C", dir, "-c", "user.email=t@example.com", "-c", "user.name=Tester",
           *args, out: File::NULL, err: File::NULL) or raise "git #{args.join(' ')} failed"
  end

  def seed_site(name, bard_rb: "# no production\n", idle_days: nil)
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
    end
    dir
  end

  def write_script(name, contents)
    path = File.join(home, name)
    File.write(path, contents)
    FileUtils.chmod(0o755, path)
    path
  end

  def run(path, *args, rails_env: "staging")
    Open3.capture2e({ "HOME" => home, "RAILS_ENV" => rails_env }, "bash", path, *args)
  end

  describe "the per-project autodestruct script" do
    let(:target) { double("staging", path: "acme") }

    def autodestruct_script(duration)
      Bard::StagingAutodestruct.new(target, "acme", duration).script
    end

    it "is valid bash" do
      path = write_script("ad.sh", autodestruct_script(7.days))
      _, status = Open3.capture2e("bash", "-n", path)
      expect(status.exitstatus).to eq(0)
    end

    it "leaves a site that is still active alone" do
      seed_site("acme", idle_days: 1)
      path = write_script("ad.sh", autodestruct_script(7.days))

      run(path)

      expect(File.directory?(File.join(home, "acme"))).to be(true)
    end

    it "removes a site that has gone idle past its window" do
      seed_site("acme", idle_days: 30)
      path = write_script("ad.sh", autodestruct_script(7.days))

      out, _ = run(path)

      expect(out).to match(/idle for over 7 days/)
      expect(File.directory?(File.join(home, "acme"))).to be(false)
    end

    it "does nothing when the site is already gone" do
      path = write_script("ad.sh", autodestruct_script(7.days))
      out, status = run(path)
      expect(status.exitstatus).to eq(0)
      expect(out).to eq("")
    end
  end
end
