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

  it "installs the audit script so it can also be run by hand over ssh" do
    expect(target).to receive(:run!).with(%r{cat > ~/\.local/state/bard/bard-audit\.sh}m, home: true)
    expect(target).to receive(:run!).with(/chmod \+x/, home: true)
    allow(target).to receive(:run!)
    cli.reap
  end

  it "runs the audit and prints its report" do
    allow(target).to receive(:run!).and_return("")
    expect(target).to receive(:run!)
      .with("$HOME/.local/state/bard/bard-audit.sh", home: true, capture: true)
      .and_return("Armed (1)\n  acme  idle 2d, autodestruct armed\n")
    expect(cli).to receive(:puts).with(/Armed \(1\)/)

    cli.reap
  end

  # The audit is advisory: removal is each site's own opt-in autodestruct timer.
  it "never installs a timer or tears anything down" do
    allow(target).to receive(:run!) do |cmd, **|
      expect(cmd).not_to match(/systemctl --user enable|rm -rf|db:drop|loginctl/)
      ""
    end
    cli.reap
  end
end

describe Bard::StagingReaper do
  subject(:script) { described_class.new.script }

  it "needs no bard install on the box" do
    expect(script).not_to match(/gem install|bundle exec|^\s*bard\s/)
  end

  it "reports every category" do
    %w[Armed Candidates Active Permanent Issues].each do |section|
      expect(script).to include(%(print_section "#{section}"))
    end
  end

  it "detects armed sites by their autodestruct timer" do
    expect(script).to include('"$HOME/.config/systemd/user/bard-autodestruct-$name.timer"')
  end

  it "never destroys anything" do
    expect(script).not_to match(/rm -rf|db:drop|systemctl --user (stop|disable)/)
  end

  it "tells the reader how to make a site ephemeral" do
    expect(script).to match(/autodestruct <days>/)
  end

  it "honours a custom ttl" do
    expect(described_class.new(ttl_days: 30).script).to include("TTL_DAYS=30")
  end
end
