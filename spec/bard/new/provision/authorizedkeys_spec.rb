require "spec_helper"
require "bard/new/provision/base"
require "bard/new/provision/authorizedkeys"

describe Bard::Provision::AuthorizedKeys do
  let(:config) { { production: double("production") } }
  let(:ssh_url) { "user@example.com" }
  let(:provision_server) { double("provision_server") }
  let(:authorized_keys) { Bard::Provision::AuthorizedKeys.new(config, ssh_url) }

  before do
    allow(authorized_keys).to receive(:provision_server).and_return(provision_server)
    allow(authorized_keys).to receive(:print)
    allow(authorized_keys).to receive(:puts)
  end

  describe "#call" do
    it "overwrites authorized_keys with exactly the canonical key set" do
      expect(provision_server).to receive(:run!).with(
        a_string_matching(/echo ".*" > ~\/.ssh\/authorized_keys/m)
          .and(a_string_matching(/chmod 600 ~\/.ssh\/authorized_keys/)),
        home: true,
      )

      authorized_keys.call
    end

    it "prints status messages" do
      allow(provision_server).to receive(:run!)
      expect(authorized_keys).to receive(:print).with("Authorized Keys:")
      expect(authorized_keys).to receive(:puts).with(" ✓")

      authorized_keys.call
    end
  end

  describe "KEYS constant" do
    it "contains only current hardware-backed keys" do
      expect(Bard::Provision::AuthorizedKeys::KEYS).to be_an(Array)
      expect(Bard::Provision::AuthorizedKeys::KEYS).not_to be_empty
      Bard::Provision::AuthorizedKeys::KEYS.each do |key|
        expect(key).to start_with("sk-ssh-ed25519@openssh.com ")
      end
    end
  end
end
