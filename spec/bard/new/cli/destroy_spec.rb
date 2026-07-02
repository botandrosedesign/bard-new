require "spec_helper"

describe "bard destroy" do
  let(:cli) { Bard::CLI.new([], yes: true) }

  before do
    allow(cli).to receive(:puts)
    allow(cli).to receive(:print)
    allow(cli).to receive(:green).and_return("")
    allow(cli).to receive(:red).and_return("")
    allow(cli).to receive(:yellow).and_return("")
    allow(cli).to receive(:run!)
  end

  describe "#destroy" do
    it "tears down remote, github, and local in order" do
      expect(cli).to receive(:destroy_remote).ordered
      expect(cli).to receive(:destroy_github).ordered
      expect(cli).to receive(:destroy_local).ordered
      cli.destroy("testproject")
    end

    it "does not prompt for confirmation with --yes" do
      allow(cli).to receive(:destroy_remote)
      allow(cli).to receive(:destroy_github)
      allow(cli).to receive(:destroy_local)
      expect(cli).not_to receive(:destroy_confirm)
      cli.destroy("testproject")
    end

    context "without --yes" do
      let(:cli) { Bard::CLI.new }

      it "prompts for confirmation" do
        allow(cli).to receive(:destroy_remote)
        allow(cli).to receive(:destroy_github)
        allow(cli).to receive(:destroy_local)
        expect(cli).to receive(:destroy_confirm)
        cli.destroy("testproject")
      end
    end

  end

  describe "#destroy_confirm" do
    let(:cli) { Bard::CLI.new }

    before do
      allow(cli).to receive(:puts)
      allow(cli).to receive(:print)
      allow(cli).to receive(:red).and_return("")
      allow(cli).to receive(:yellow).and_return("")
      cli.instance_variable_set(:@destroy_project_name, "testproject")
    end

    it "aborts when the typed name does not match" do
      allow($stdin).to receive(:gets).and_return("nope\n")
      expect(cli).to receive(:exit).with(1)
      cli.send(:destroy_confirm)
    end

    it "proceeds when the typed name matches" do
      allow($stdin).to receive(:gets).and_return("testproject\n")
      expect(cli).not_to receive(:exit)
      cli.send(:destroy_confirm)
    end
  end

  describe "#destroy_remote" do
    let(:target) { double("production") }
    let(:dconfig) { double("config") }

    before do
      cli.instance_variable_set(:@destroy_project_name, "testproject")
      allow(cli).to receive(:destroy_config).and_return(dconfig)
    end

    context "when the target has ssh" do
      before do
        allow(dconfig).to receive(:[]).with(:production).and_return(target)
        allow(target).to receive(:has_capability?).with(:ssh).and_return(true)
        allow(target).to receive(:key).and_return(:production)
      end

      it "stops services, drops the db, removes the nginx site and gemset, and the app" do
        expect(target).to receive(:run!).with(
          "systemctl --user stop testproject.target 2>/dev/null || true; systemctl --user disable testproject.target 2>/dev/null || true; rm -f ~/.config/systemd/user/testproject*.service ~/.config/systemd/user/testproject.target; rm -rf ~/.config/systemd/user/testproject.target.wants; systemctl --user daemon-reload 2>/dev/null || true",
          home: true, quiet: true)
        expect(target).to receive(:run!).with(
          "bash -lc #{Shellwords.escape("cd ~/testproject && bin/rake db:drop")} >/dev/null 2>&1 || true",
          home: true, quiet: true)
        expect(target).to receive(:run!).with(
          "sudo rm -f /etc/nginx/sites-available/testproject /etc/nginx/sites-enabled/testproject; sudo service nginx reload || true",
          home: true, quiet: true)
        expect(target).to receive(:run!).with(
          "env -i bash -lc 'source ~/.rvm/scripts/rvm && rvm --force gemset delete \"$(cat ~/testproject/.ruby-version 2>/dev/null)@testproject\" || true'",
          home: true, quiet: true)
        expect(target).to receive(:run!).with("rm -rf ~/testproject", home: true, quiet: true)

        cli.send(:destroy_remote)
      end
    end

    context "when the target has no ssh capability" do
      before do
        allow(dconfig).to receive(:[]).with(:production).and_return(target)
        allow(target).to receive(:has_capability?).with(:ssh).and_return(false)
      end

      it "does nothing" do
        expect(target).not_to receive(:run!)
        cli.send(:destroy_remote)
      end
    end
  end

  describe "#destroy_github" do
    let(:github) { double("github") }

    before do
      cli.instance_variable_set(:@destroy_project_name, "testproject")
    end

    it "deletes the github repo" do
      expect(Bard::Github).to receive(:new).with("testproject").and_return(github)
      expect(github).to receive(:delete_repo)

      cli.send(:destroy_github)
    end

    it "surfaces a clear error and re-raises when deletion fails" do
      allow(Bard::Github).to receive(:new).with("testproject").and_return(github)
      allow(github).to receive(:delete_repo).and_raise("403 Forbidden")

      expect(cli).to receive(:puts).with(/delete_repo/)
      expect { cli.send(:destroy_github) }.to raise_error(/403/)
    end
  end

  describe "#destroy_local" do
    let(:local_target) { double("local", key: :local) }
    let(:dconfig) { double("config") }

    before do
      cli.instance_variable_set(:@destroy_project_name, "testproject")
      allow(cli).to receive(:destroy_config).and_return(dconfig)
      allow(dconfig).to receive(:[]).with(:local).and_return(local_target)
    end

    it "stops services, drops the db, removes the nginx site and gemset, and the project directory locally" do
      expect(local_target).to receive(:run!).with(
        "systemctl --user stop testproject.target 2>/dev/null || true; systemctl --user disable testproject.target 2>/dev/null || true; rm -f ~/.config/systemd/user/testproject*.service ~/.config/systemd/user/testproject.target; rm -rf ~/.config/systemd/user/testproject.target.wants; systemctl --user daemon-reload 2>/dev/null || true",
        home: true, quiet: true)
      expect(local_target).to receive(:run!).with(
        "bash -lc #{Shellwords.escape("cd ../testproject && bin/rake db:drop")} >/dev/null 2>&1 || true",
        home: true, quiet: true)
      expect(local_target).to receive(:run!).with(
        "sudo rm -f /etc/nginx/sites-available/testproject /etc/nginx/sites-enabled/testproject; sudo service nginx reload || true",
        home: true, quiet: true)
      expect(local_target).to receive(:run!).with(
        "env -i bash -lc 'source ~/.rvm/scripts/rvm && rvm --force gemset delete \"$(cat ../testproject/.ruby-version 2>/dev/null)@testproject\" || true'",
        home: true, quiet: true)
      expect(local_target).to receive(:run!).with("rm -rf ../testproject", home: true, quiet: true)

      cli.send(:destroy_local)
    end
  end
end
