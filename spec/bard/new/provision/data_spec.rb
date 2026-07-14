require "spec_helper"
require "bard/new/provision/base"
require "bard/new/provision/data"

describe Bard::Provision::Data do
  let(:target) { double("target", key: :production) }
  let(:config) { double("config", data: ["uploads", "assets"]) }
  let(:ssh_url) { "user@example.com" }
  let(:provision_server) { double("provision_server") }
  let(:data_provisioner) { Bard::Provision::Data.new(config, ssh_url) }

  before do
    allow(data_provisioner).to receive(:target).and_return(target)
    allow(data_provisioner).to receive(:config).and_return(config)
    allow(data_provisioner).to receive(:provision_server).and_return(provision_server)
    allow(data_provisioner).to receive(:print)
    allow(data_provisioner).to receive(:puts)
  end

  describe "#call" do
    it "dumps, transfers, and loads database data" do
      expect(target).to receive(:run!).with("bin/rake db:dump")
      expect(Bard::Copy).to receive(:file).with("db/data.sql.gz", from: target, to: provision_server, verbose: false)
      expect(provision_server).to receive(:run!).with("bin/rake db:load")

      allow(Bard::Copy).to receive(:dir)

      data_provisioner.call
    end

    it "synchronizes configured data directories" do
      allow(target).to receive(:run!)
      allow(Bard::Copy).to receive(:file)
      allow(provision_server).to receive(:run!)

      expect(Bard::Copy).to receive(:dir).with("uploads", from: target, to: provision_server, verbose: false)
      expect(Bard::Copy).to receive(:dir).with("assets", from: target, to: provision_server, verbose: false)

      data_provisioner.call
    end

    it "prints status messages" do
      allow(target).to receive(:run!)
      allow(Bard::Copy).to receive(:file)
      allow(Bard::Copy).to receive(:dir)
      allow(provision_server).to receive(:run!)

      expect(data_provisioner).to receive(:print).with("Data:")
      expect(data_provisioner).to receive(:puts).with(" ✓")

      data_provisioner.call
    end
  end
end
