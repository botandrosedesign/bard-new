require "spec_helper"

describe "bard reap" do
  let(:cli) { Bard::CLI.new }

  around do |example|
    original = ENV["RAILS_ENV"]
    ENV["RAILS_ENV"] = "staging"
    example.run
    ENV["RAILS_ENV"] = original
  end

  before do
    allow(cli).to receive(:puts)
    allow(cli).to receive(:green) { |s| s }
    allow(cli).to receive(:red) { |s| s }
  end

  describe "guard" do
    it "refuses to run when RAILS_ENV is not staging" do
      ENV["RAILS_ENV"] = "development"
      expect { cli.reap }.to raise_error(Thor::Error, /refuses to run outside a staging environment/)
    end

    it "runs anyway with --force" do
      ENV["RAILS_ENV"] = "development"
      cli = Bard::CLI.new([], force: true)
      allow(cli).to receive(:puts)
      allow(cli).to receive(:green) { |s| s }
      allow(cli).to receive(:red) { |s| s }
      allow(cli).to receive(:reap_candidates).and_return([])
      expect { cli.reap }.not_to raise_error
    end
  end

  describe "#reap_classify" do
    it "is ephemeral when origin/master declares a distinct production" do
      allow(cli).to receive(:reap_origin_bard_rb).and_return(<<~RUBY)
        target :production do
          ssh "deploy@prod.example.com:22022"
        end
      RUBY
      expect(cli.send(:reap_classify, "/home/www/acme", "acme")).to eq([:ephemeral, nil])
    end

    it "is unknown when origin/master:bard.rb is empty or unreadable" do
      allow(cli).to receive(:reap_origin_bard_rb).and_return("")
      expect(cli.send(:reap_classify, "/home/www/acme", "acme").first).to eq(:unknown)
    end

    it "is permanent when the config defines no distinct production" do
      allow(cli).to receive(:reap_origin_bard_rb).and_return("# a permanent resident, no production target\n")
      expect(cli.send(:reap_classify, "/home/www/acme", "acme")).to eq([:permanent, nil])
    end

    it "is unknown when the config cannot be evaluated" do
      allow(cli).to receive(:reap_origin_bard_rb).and_return("this is not valid ruby <<<")
      status, reason = cli.send(:reap_classify, "/home/www/acme", "acme")
      expect(status).to eq(:unknown)
      expect(reason).to match(/error reading config/)
    end
  end

  describe "sweep" do
    before do
      allow(cli).to receive(:reap_candidates).and_return(%w[ripe fresh perm broken])
      allow(cli).to receive(:reap_missing_files) do |dir|
        dir.end_with?("broken") ? %w[.git] : []
      end
      allow(cli).to receive(:reap_classify) do |dir, name|
        case name
        when "ripe", "fresh" then [:ephemeral, nil]
        when "perm" then [:permanent, nil]
        end
      end
      allow(cli).to receive(:reap_idle_days) do |dir|
        dir.end_with?("ripe") ? 9.0 : 2.0
      end
    end

    it "reaps ripe ephemeral sites, keeps fresh ones, and flags issues" do
      removal = instance_double(Bard::SiteRemoval, call: nil)
      expect(Bard::SiteRemoval).to receive(:new).with(File.join(Dir.home, "ripe")).and_return(removal)
      expect(Bard::SiteRemoval).not_to receive(:new).with(File.join(Dir.home, "fresh"))
      allow(cli).to receive(:exit)

      cli.reap

      expect(cli).to have_received(:exit).with(1) # broken -> issues -> nonzero
    end

    it "does not reap anything on a dry run" do
      cli = Bard::CLI.new([], "dry-run": true)
      allow(cli).to receive(:puts)
      allow(cli).to receive(:green) { |s| s }
      allow(cli).to receive(:red) { |s| s }
      allow(cli).to receive(:reap_candidates).and_return(%w[ripe])
      allow(cli).to receive(:reap_missing_files).and_return([])
      allow(cli).to receive(:reap_classify).and_return([:ephemeral, nil])
      allow(cli).to receive(:reap_idle_days).and_return(30.0)

      expect(Bard::SiteRemoval).not_to receive(:new)
      cli.reap
    end
  end

  describe "#reap_candidates" do
    it "ignores dotfiles and non-directories" do
      allow(Dir).to receive(:children).with(Dir.home).and_return(%w[.config acme notes.txt beta])
      allow(File).to receive(:directory?).and_return(true)
      allow(File).to receive(:directory?).with(File.join(Dir.home, "notes.txt")).and_return(false)
      expect(cli.send(:reap_candidates)).to eq(%w[acme beta])
    end
  end
end
