require "spec_helper"

describe Bard::StagingAutodestruct do
  let(:target) { double("staging", path: "acme", run!: "") }

  describe ".arm" do
    it "does nothing when the target has not opted in" do
      allow(target).to receive(:expires_after).and_return(nil)
      expect(target).not_to receive(:run!)
      expect(described_class.arm(target, "acme")).to be_nil
    end

    it "arms when the target declares expires_after" do
      allow(target).to receive(:expires_after).and_return(7.days)
      expect(described_class.arm(target, "acme")).to be_a(described_class)
    end

    it "is inert on a target with no expires_after DSL at all" do
      plain = double("target")
      expect(described_class.arm(plain, "acme")).to be_nil
    end
  end

  describe "#arm" do
    subject(:autodestruct) { described_class.new(target, "acme", 7.days) }

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
    subject(:script) { described_class.new(target, "acme", 7.days).script }

    it "needs no bard install on the box" do
      expect(script).not_to match(/gem install|bundle exec|^\s*bard\s/)
    end

    it "keys idleness off git activity and the bard data sync marker" do
      expect(script).to include('"$DIR/.git/logs/HEAD"')
      expect(script).to include('"$STATE/$NAME.synced"')
    end

    it "converts the duration into an idle window in minutes" do
      expect(script).to include("IDLE_MIN=10080")
      expect(described_class.new(target, "acme", 30.days).script).to include("IDLE_MIN=43200")
      expect(described_class.new(target, "acme", 36.hours).script).to include("IDLE_MIN=2160")
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
    subject(:autodestruct) { described_class.new(target, "acme", 7.days) }

    it "runs the script daily in a staging environment" do
      expect(autodestruct.service_unit).to include("Environment=RAILS_ENV=staging")
      expect(autodestruct.service_unit).to include("ExecStart=%h/.local/state/bard/bard-autodestruct-acme.sh")
      expect(autodestruct.timer_unit).to include("OnCalendar=daily")
    end
  end
end

describe "expires_after target DSL" do
  let(:config) { Bard::Config.new("acme", source: source) }

  context "when declared" do
    let(:source) { "target :staging do\n  expires_after 7.days\nend\n" }

    it "reads back the configured duration" do
      expect(config[:staging].expires_after).to eq(7.days)
    end
  end

  # `expires_after 7` would be seven seconds, wiping the site on the next timer run.
  context "when given a bare number instead of a duration" do
    let(:source) { "target :staging do\n  expires_after 7\nend\n" }

    it "refuses, naming the correct form" do
      expect { config }.to raise_error(ArgumentError, /expires_after 7\.days/)
    end
  end

  context "when omitted" do
    let(:source) { "target :staging do\nend\n" }

    it "is nil, so nothing is armed" do
      expect(config[:staging].expires_after).to be_nil
    end
  end
end
