require "spec_helper"
require "bard/new/provision/base"
require "bard/new/provision/data"

describe Bard::Provision::Data do
  let(:target) { double("target", key: :production, ssh: double(to_s: "www@example.com:22022")) }
  let(:config) { double("config", data: ["uploads", "assets"]) }
  let(:ssh_url) { "www@203.0.113.5:22022" }
  let(:provision_server) { double("provision_server") }
  let(:data_provisioner) { Bard::Provision::Data.new(config, ssh_url) }

  before do
    allow(data_provisioner).to receive(:target).and_return(target)
    allow(data_provisioner).to receive(:config).and_return(config)
    allow(data_provisioner).to receive(:provision_server).and_return(provision_server)
    allow(data_provisioner).to receive(:print)
    allow(data_provisioner).to receive(:puts)
    allow(config).to receive(:[]).with(:old_production).and_return(nil)
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

    context "when bard.rb defines :old_production" do
      let(:old_production) { double("old_production", key: :old_production, ssh: double(to_s: "ubuntu@example.com:22")) }

      before do
        allow(config).to receive(:[]).with(:old_production).and_return(old_production)
      end

      it "pulls from the previous production instead of the :production target" do
        expect(old_production).to receive(:run!).with("bin/rake db:dump")
        expect(target).not_to receive(:run!)
        expect(Bard::Copy).to receive(:file).with("db/data.sql.gz", from: old_production, to: provision_server, verbose: false)
        expect(provision_server).to receive(:run!).with("bin/rake db:load")
        allow(Bard::Copy).to receive(:dir)

        data_provisioner.call
      end
    end

    context "when the data source is the box being provisioned" do
      let(:ssh_url) { "www@example.com:22022" }

      it "skips instead of dumping the box into itself" do
        expect(target).not_to receive(:run!)
        expect(Bard::Copy).not_to receive(:file)
        expect(data_provisioner).to receive(:puts).with(a_string_matching(/skipping/))

        data_provisioner.call
      end
    end
  end
end
