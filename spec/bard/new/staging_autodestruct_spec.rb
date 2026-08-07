require "spec_helper"

describe Bard::StagingAutodestruct do
  let(:target) { double("staging", path: "acme", run!: "") }

  describe ".arm" do
    it "does nothing when the target has not opted in" do
      allow(target).to receive(:autodestruct).and_return(nil)
      expect(target).not_to receive(:run!)
      expect(described_class.arm(target, "acme")).to be_nil
    end

    it "arms when the target declares autodestruct" do
      allow(target).to receive(:autodestruct).and_return(7)
      expect(described_class.arm(target, "acme")).to be_a(described_class)
    end

    it "is inert on a target with no autodestruct DSL at all" do
      plain = double("target")
      expect(described_class.arm(plain, "acme")).to be_nil
    end
  end

  describe "#arm" do
    subject(:autodestruct) { described_class.new(target, "acme", 7) }

    it "writes the script and units, enables linger, and enables the timer" do
      expect(target).to receive(:run!).with(/mkdir -p ~\/\.local\/state\/bard/, home: true)
      expect(target).to receive(:run!).with(%r{cat > ~/\.local/state/bard/bard-autodestruct-acme\.sh}m, home: true)
      expect(target).to receive(:run!).with(/chmod \+x/, home: true)
      expect(target).to receive(:run!).with(%r{cat > ~/\.config/systemd/user/bard-autodestruct-acme\.service}m, home: true)
      expect(target).to receive(:run!).with(%r{cat > ~/\.config/systemd/user/bard-autodestruct-acme\.timer}m, home: true)
      expect(target).to receive(:run!).with(/loginctl enable-linger/, home: true)
      expect(target).to receive(:run!).with(/systemctl --user enable --now bard-autodestruct-acme\.timer/, home: true)

      autodestruct.arm
    end

    it "installs no gem on the staging box" do
      allow(target).to receive(:run!) { |cmd, **| expect(cmd).not_to match(/gem install|bundle exec/); "" }
      autodestruct.arm
    end
  end

  describe "#script" do
    subject(:script) { described_class.new(target, "acme", 7).script }

    it "needs no bard install on the box" do
      expect(script).not_to match(/gem install|bundle exec|^\s*bard\s/)
    end

    it "keys idleness off git activity and the bard data sync marker" do
      expect(script).to include('"$DIR/.git/logs/HEAD"')
      expect(script).to include('"$STATE/$NAME.synced"')
    end

    it "converts the configured days into an idle window" do
      expect(script).to include("IDLE_MIN=$(( 7 * 1440 ))")
      expect(described_class.new(target, "acme", 30).script).to include("IDLE_MIN=$(( 30 * 1440 ))")
    end

    it "does nothing when there is no activity signal to measure" do
      expect(script).to include('[ -n "$newest" ] || exit 0')
    end

    it "embeds the shared SiteRemoval teardown steps for its own site" do
      Bard::SiteRemoval.new("$HOME/acme", name: "acme").steps.each do |_, cmd|
        expect(script).to include(cmd)
      end
    end
  end

  describe "units" do
    subject(:autodestruct) { described_class.new(target, "acme", 7) }

    it "runs the script daily in a staging environment" do
      expect(autodestruct.service_unit).to include("Environment=RAILS_ENV=staging")
      expect(autodestruct.service_unit).to include("ExecStart=%h/.local/state/bard/bard-autodestruct-acme.sh")
      expect(autodestruct.timer_unit).to include("OnCalendar=daily")
    end
  end
end

describe "autodestruct target DSL" do
  let(:config) { Bard::Config.new("acme", source: source) }

  context "when declared" do
    let(:source) { "target :staging do\n  autodestruct 7\nend\n" }

    it "reads back the configured days" do
      expect(config[:staging].autodestruct).to eq(7)
    end
  end

  context "when omitted" do
    let(:source) { "target :staging do\nend\n" }

    it "is nil, so nothing is armed" do
      expect(config[:staging].autodestruct).to be_nil
    end
  end
end
