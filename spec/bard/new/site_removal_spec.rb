require "spec_helper"

describe Bard::ProcessManager do
  describe ".for" do
    it "selects the procsd backend when procsd.yml is present" do
      allow(File).to receive(:exist?).with("/app/procsd.yml").and_return(true)
      expect(described_class.for("/app")).to be_a(Bard::ProcessManager::Procsd)
    end

    it "defaults to the systemd-user backend" do
      allow(File).to receive(:exist?).with("/app/procsd.yml").and_return(false)
      expect(described_class.for("/app")).to be_a(Bard::ProcessManager::SystemdUser)
    end
  end

  describe Bard::ProcessManager::SystemdUser do
    it "stops, disables, and removes the app's units" do
      cmd = described_class.new("/home/www/acme").teardown_command
      expect(cmd).to eq(
        "systemctl --user stop acme.target 2>/dev/null || true; " \
        "systemctl --user disable acme.target 2>/dev/null || true; " \
        "rm -f ~/.config/systemd/user/acme*.service ~/.config/systemd/user/acme.target; " \
        "rm -rf ~/.config/systemd/user/acme.target.wants; " \
        "systemctl --user daemon-reload 2>/dev/null || true"
      )
    end
  end

  describe Bard::ProcessManager::Procsd do
    it "runs procsd destroy in the app directory" do
      expect(described_class.new("/home/www/acme").teardown_command)
        .to eq("cd /home/www/acme && procsd destroy 2>/dev/null || true")
    end
  end
end

describe Bard::SiteRemoval do
  subject(:removal) { described_class.new("/home/www/acme") }

  before do
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with("/home/www/acme/procsd.yml").and_return(false)
    allow(FileUtils).to receive(:rm_rf)
  end

  it "derives the site name from the directory" do
    expect(removal.name).to eq("acme")
  end

  it "stops processes, drops the db, removes nginx, then deletes the directory in order" do
    calls = []
    allow(removal).to receive(:sh) { |c| calls << c; true }

    removal.call

    expect(calls).to eq([
      Bard::ProcessManager::SystemdUser.new("/home/www/acme").teardown_command,
      "bash -lc #{Shellwords.escape("cd /home/www/acme && bin/rake db:drop")} >/dev/null 2>&1",
      "sudo rm -f /etc/nginx/sites-available/acme /etc/nginx/sites-enabled/acme",
      "sudo service nginx reload || true",
    ])
    expect(FileUtils).to have_received(:rm_rf).with("/home/www/acme")
  end

  it "reports whether the database was dropped" do
    allow(removal).to receive(:sh).and_return(true, false, true, true)
    expect(removal.call.db_dropped).to eq(false)
  end
end

describe "bard remove" do
  let(:cli) { Bard::CLI.new([], yes: true) }

  before do
    allow(cli).to receive(:puts)
    allow(cli).to receive(:print)
    allow(cli).to receive(:green).and_return("")
    allow(cli).to receive(:red).and_return("")
    allow(cli).to receive(:yellow).and_return("")
  end

  it "removes the site in the current directory" do
    removal = instance_double(Bard::SiteRemoval, call: nil)
    expect(Bard::SiteRemoval).to receive(:new).with(Dir.pwd).and_return(removal)
    cli.remove
  end

  context "without --yes" do
    let(:cli) { Bard::CLI.new }

    it "aborts when the typed name does not match" do
      allow(cli).to receive(:puts)
      allow(cli).to receive(:print)
      allow(cli).to receive(:yellow).and_return("")
      allow(cli).to receive(:red).and_return("")
      allow($stdin).to receive(:gets).and_return("nope\n")
      allow(cli).to receive(:exit).with(1).and_raise(SystemExit)

      expect(Bard::SiteRemoval).not_to receive(:new)
      expect { cli.remove }.to raise_error(SystemExit)
    end
  end
end
