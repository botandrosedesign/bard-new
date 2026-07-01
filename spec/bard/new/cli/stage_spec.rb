require "spec_helper"

describe "bard-new after_stage hook" do
  let(:target) { double("staging") }
  let(:cli) { Bard::CLI.new }

  before do
    allow(cli).to receive(:puts)
    allow(cli).to receive(:yellow) { |s| s }
    allow(cli).to receive(:project_name).and_return("acme")
    allow(target).to receive(:run!)
  end

  it "defines after_stage so core's stage can arm the autodestruct" do
    expect(cli).to respond_to(:after_stage)
  end

  describe "#arm_autodestruct" do
    it "touches restart.txt and installs the reaper timer" do
      expect(target).to receive(:run!).with("mkdir -p tmp && touch tmp/restart.txt")
      expect(target).to receive(:run!).with(a_string_matching(/bard-reap\.timer/), home: true)
      cli.send(:arm_autodestruct, target)
    end
  end

  describe "#reaper_install_script" do
    it "renders enable-linger and an enabled user timer" do
      script = cli.send(:reaper_install_script)
      expect(script).to include("loginctl enable-linger")
      expect(script).to include("ExecStart=/bin/bash -lc 'bard reap'")
      expect(script).to include("systemctl --user enable --now bard-reap.timer")
    end
  end

  describe "#after_stage" do
    before { allow(cli).to receive(:arm_autodestruct) }

    it "arms the autodestruct on every stage" do
      allow($stdin).to receive(:tty?).and_return(false)
      expect(cli).to receive(:arm_autodestruct).with(target)
      cli.after_stage(target, restored: false)
    end

    context "when the site was rebuilt from scratch" do
      it "offers to restore data from production and runs it on yes" do
        allow($stdin).to receive(:tty?).and_return(true)
        allow(cli).to receive(:yes?).and_return(true)
        expect(cli).to receive(:invoke).with(:data, [], from: "production", to: "staging")
        cli.after_stage(target, restored: true)
      end

      it "prints the restore instructions when declined" do
        allow($stdin).to receive(:tty?).and_return(false)
        expect(cli).to receive(:puts).with(/bard data --from production --to staging/)
        cli.after_stage(target, restored: true)
      end
    end
  end
end
