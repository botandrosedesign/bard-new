require "spec_helper"

describe "bard reap" do
  let(:target) { double("staging", key: :staging, require_capability!: nil, run!: "") }
  let(:config) { double("config") }
  let(:cli) { Bard::CLI.new }

  before do
    allow(cli).to receive(:puts)
    allow(cli).to receive(:config).and_return(config)
    allow(config).to receive(:[]).with(:staging).and_return(target)
  end

  it "requires ssh on the staging target" do
    expect(target).to receive(:require_capability!).with(:ssh)
    cli.reap
  end

  describe "installing the reaper" do
    it "writes the script and units, enables linger, and enables the timer" do
      expect(target).to receive(:run!).with(/mkdir -p ~\/\.local\/state\/bard/, home: true)
      expect(target).to receive(:run!).with(%r{cat > ~/\.local/state/bard/bard-reap\.sh}m, home: true)
      expect(target).to receive(:run!).with(%r{cat > ~/\.config/systemd/user/bard-reap\.service}m, home: true)
      expect(target).to receive(:run!).with(%r{cat > ~/\.config/systemd/user/bard-reap\.timer}m, home: true)
      expect(target).to receive(:run!).with(/chmod \+x/, home: true)
      expect(target).to receive(:run!).with(/loginctl enable-linger/, home: true)
      expect(target).to receive(:run!).with(/systemctl --user enable --now bard-reap\.timer/, home: true)
      allow(target).to receive(:run!).with(anything, hash_including(capture: true))

      cli.reap
    end

    it "installs no gem on the staging box" do
      allow(target).to receive(:run!) { |cmd, **| expect(cmd).not_to match(/gem install|rvm use/); "" }
      cli.reap
    end
  end

  describe "sweeping" do
    it "runs the installed script and prints its report" do
      allow(target).to receive(:run!).and_return("")
      expect(target).to receive(:run!)
        .with("$HOME/.local/state/bard/bard-reap.sh", home: true, capture: true)
        .and_return("Reaped (1)\n  acme  idle 9d\n")
      expect(cli).to receive(:puts).with(/Reaped \(1\)/)

      cli.reap
    end

    it "passes --dry-run through to the script" do
      cli = Bard::CLI.new([], "dry-run": true)
      allow(cli).to receive(:puts)
      allow(cli).to receive(:config).and_return(config)
      allow(target).to receive(:run!).and_return("")
      expect(target).to receive(:run!)
        .with("$HOME/.local/state/bard/bard-reap.sh --dry-run", home: true, capture: true)

      cli.reap
    end

    it "skips the sweep with --install-only" do
      cli = Bard::CLI.new([], install_only: true)
      allow(cli).to receive(:puts)
      allow(cli).to receive(:config).and_return(config)
      allow(target).to receive(:run!).and_return("")
      expect(target).not_to receive(:run!).with(anything, hash_including(capture: true))

      cli.reap
    end
  end
end

describe Bard::StagingReaper do
  subject(:reaper) { described_class.new }

  it "refuses to run outside staging" do
    expect(reaper.script).to include('if [ "${RAILS_ENV:-}" != "staging" ]; then')
  end

  # The staging box has no bard/bard-cli install, so the script must not reach for one.
  # (It does shell out to rvm to drop a site's gemset -- rvm is present on staging.)
  it "installs no gems and never invokes bard" do
    expect(reaper.script).not_to match(/gem install|bundle exec|^\s*bard\s/)
  end

  it "keys idleness off git activity and the bard data sync marker" do
    expect(reaper.script).to include('"$dir/.git/logs/HEAD"')
    expect(reaper.script).to include('"$STATE/$name.synced"')
  end

  it "classifies from origin/master, not the local checkout" do
    expect(reaper.script).to include("git -C \"$dir\" show origin/master:bard.rb")
  end

  it "reports all four sections" do
    %w[Reaped Left Unknown Issues].each do |section|
      expect(reaper.script).to include(%(print_section "#{section}"))
    end
  end

  it "embeds the shared SiteRemoval teardown steps against shell placeholders" do
    Bard::SiteRemoval.new('"$dir"', name: '"$name"').steps.each do |_, cmd|
      expect(reaper.script).to include(cmd)
    end
  end

  it "honours a custom ttl" do
    expect(described_class.new(ttl_days: 30).script).to include("TTL_DAYS=30")
  end

  it "runs the script from a systemd timer with a staging environment" do
    expect(reaper.service_unit).to include("Environment=RAILS_ENV=staging")
    expect(reaper.service_unit).to include("ExecStart=%h/.local/state/bard/bard-reap.sh")
    expect(reaper.timer_unit).to include("OnCalendar=daily")
  end
end
