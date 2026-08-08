require "spec_helper"

describe "bard destroy" do
  let(:cli) { Bard::CLI.new([], yes: true) }
  let(:dconfig) { double("config") }

  # Default config: staging and production are the same target until a distinct
  # production is declared.
  let(:staging) { double("staging", key: :staging, path: "testproject", has_capability?: true) }
  let(:production) { staging }
  let(:local) { double("local", key: :local, has_capability?: false) }

  before do
    allow(cli).to receive(:puts)
    allow(cli).to receive(:print)
    allow(cli).to receive(:green).and_return("")
    allow(cli).to receive(:red).and_return("")
    allow(cli).to receive(:yellow).and_return("")
    allow(cli).to receive(:destroy_config).and_return(dconfig)
    allow(dconfig).to receive(:targets).and_return(staging: staging, production: production, local: local)
    allow(dconfig).to receive(:[]).with(:local).and_return(local)
    allow(dconfig).to receive(:[]).with(:staging).and_return(staging)
  end

  describe "full destroy" do
    before do
      allow(cli).to receive(:destroy_remote)
      allow(cli).to receive(:destroy_github)
      allow(cli).to receive(:destroy_local)
    end

    it "tears down every site, then github, then the local checkout, in order" do
      expect(cli).to receive(:destroy_remote).ordered
      expect(cli).to receive(:destroy_github).ordered
      expect(cli).to receive(:destroy_local).ordered
      cli.destroy("testproject")
    end

    # A full destroy deletes the checkout, so it cannot be the cwd.
    it "refuses to run from inside the project" do
      allow(cli).to receive(:exit).with(1).and_raise(SystemExit)
      allow(Bard::Config).to receive(:detect_project_name).and_return("testproject")
      expect(cli).not_to receive(:destroy_github)
      expect { cli.destroy }.to raise_error(SystemExit)
    end

    context "without --yes" do
      let(:cli) { Bard::CLI.new }

      it "prompts for confirmation" do
        allow(cli).to receive(:puts)
        allow(cli).to receive(:print)
        allow(cli).to receive(:green).and_return("")
        allow(cli).to receive(:yellow).and_return("")
        allow(cli).to receive(:destroy_remote)
        allow(cli).to receive(:destroy_github)
        allow(cli).to receive(:destroy_local)
        expect(cli).to receive(:destroy_confirm)
        cli.destroy("testproject")
      end
    end
  end

  describe "#destroy_remote" do
    before { cli.instance_variable_set(:@destroy_project_name, "testproject") }

    it "tears down every ssh-capable target" do
      other = double("gubs", key: :gubs, path: "Sites/testproject", has_capability?: true)
      allow(dconfig).to receive(:targets).and_return(staging: staging, local: local, gubs: other)
      [staging, other].each do |t|
        allow(t).to receive(:run).and_return("")
        expect(cli).to receive(:destroy_teardown).with(t, "~/#{t.path}")
      end

      cli.send(:destroy_remote)
    end

    # Without a distinct production these are the same target; tearing it down twice
    # would run the whole teardown against an already-deleted directory.
    it "tears the same target down only once when staging and production are identical" do
      expect(staging).to receive(:run).once.and_return("")
      expect(cli).to receive(:destroy_teardown).once

      cli.send(:destroy_remote)
    end

    it "skips targets that have nothing deployed" do
      allow(staging).to receive(:run).and_return(false)
      expect(cli).not_to receive(:destroy_teardown)

      cli.send(:destroy_remote)
    end

    it "ignores targets without ssh" do
      expect(cli.send(:destroy_targets)).not_to include(local)
    end
  end

  describe "--target" do
    let(:cli) { Bard::CLI.new([], yes: true, target: "staging") }

    it "tears down only that target, leaving github and the checkout alone" do
      allow(staging).to receive(:run).and_return("")
      expect(cli).to receive(:destroy_teardown).with(staging, "~/testproject")
      expect(cli).not_to receive(:destroy_github)
      expect(cli).not_to receive(:destroy_local)

      cli.destroy("testproject")
    end

    it "works from inside the project" do
      allow(Bard::Config).to receive(:detect_project_name).and_return("testproject")
      allow(staging).to receive(:run).and_return("")
      allow(cli).to receive(:destroy_teardown)
      expect(cli).not_to receive(:exit)

      cli.destroy
    end
  end

  describe "#destroy_teardown" do
    before { cli.instance_variable_set(:@destroy_project_name, "testproject") }

    it "sends every SiteRemoval step over the target as plain shell" do
      Bard::SiteRemoval.new("~/testproject").steps.each do |_, script|
        expect(staging).to receive(:run!).with(script, home: true, quiet: true)
      end

      cli.send(:destroy_teardown, staging, "~/testproject")
    end
  end

  describe "#destroy_github" do
    let(:github) { double("github") }

    before { cli.instance_variable_set(:@destroy_project_name, "testproject") }

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
    before { cli.instance_variable_set(:@destroy_project_name, "testproject") }

    it "tears down the local checkout in the parent directory" do
      expect(cli).to receive(:destroy_teardown).with(local, "../testproject")
      cli.send(:destroy_local)
    end
  end
end
