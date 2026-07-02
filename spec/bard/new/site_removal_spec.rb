require "spec_helper"
require "shellwords"

describe Bard::SiteRemoval do
  subject(:removal) { described_class.new("/home/www/acme") }

  def script_for(label)
    removal.steps.find { |l, _| l == label }.last
  end

  it "derives the site name from the directory" do
    expect(removal.send(:instance_variable_get, :@name)).to eq("acme")
  end

  it "tears down in order: stop, db:drop, nginx, gemset, rm" do
    expect(removal.steps.map(&:first)).to eq([
      "stopping services",
      "dropping database",
      "removing nginx site",
      "removing rvm gemset",
      "removing project directory",
    ])
  end

  it "stops the systemd units" do
    expect(script_for("stopping services")).to eq(
      "systemctl --user stop acme.target 2>/dev/null || true; " \
      "systemctl --user disable acme.target 2>/dev/null || true; " \
      "rm -f ~/.config/systemd/user/acme*.service ~/.config/systemd/user/acme.target; " \
      "rm -rf ~/.config/systemd/user/acme.target.wants; " \
      "systemctl --user daemon-reload 2>/dev/null || true"
    )
  end

  it "drops the database in a login shell so rvm activates the app's gemset" do
    expect(script_for("dropping database")).to eq(
      "bash -lc #{Shellwords.escape("cd /home/www/acme && bin/rake db:drop")} >/dev/null 2>&1 || true"
    )
  end

  it "removes the nginx site" do
    expect(script_for("removing nginx site")).to eq(
      "sudo rm -f /etc/nginx/sites-available/acme /etc/nginx/sites-enabled/acme; sudo service nginx reload || true"
    )
  end

  it "removes the gemset named after the checkout's own ruby" do
    expect(script_for("removing rvm gemset")).to eq(
      "env -i bash -lc 'source ~/.rvm/scripts/rvm && rvm --force gemset delete \"$(cat /home/www/acme/.ruby-version 2>/dev/null)@acme\" || true'"
    )
  end

  it "deletes the directory last" do
    expect(script_for("removing project directory")).to eq("rm -rf /home/www/acme")
  end

  describe "#call" do
    it "runs every step locally and quietly" do
      ran = []
      allow(removal).to receive(:system) { |c| ran << c; true }
      removal.call
      expect(ran.size).to eq(5)
      expect(ran).to all(match(/>\/dev\/null 2>&1\z/))
    end
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
