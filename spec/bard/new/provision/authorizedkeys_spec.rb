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

    # Overwriting with only the canonical set revokes the key this very run is
    # connected with, so every later provision step gets "Permission denied".
    context "when provisioning with a key outside the canonical set" do
      let(:key_path) { File.expand_path("../../../acceptance/docker/test_key", __dir__) }

      before { allow(provision_server).to receive(:ssh_key).and_return(key_path) }

      it "keeps that key authorized alongside the canonical set" do
        pubkey = File.read("#{key_path}.pub").strip
        expect(provision_server).to receive(:run!).with(a_string_including(pubkey), home: true)

        authorized_keys.call
      end

      it "still writes every canonical key" do
        expect(provision_server).to receive(:run!) do |script, **|
          described_class::KEYS.each { |k| expect(script).to include(k) }
        end

        authorized_keys.call
      end
    end

    context "when provisioning with a canonical key" do
      before { allow(provision_server).to receive(:ssh_key).and_return(nil) }

      it "writes the canonical set unchanged" do
        expect(provision_server).to receive(:run!) do |script, **|
          expect(script.scan(/sk-ssh-ed25519/).size).to eq(described_class::KEYS.size)
        end

        authorized_keys.call
      end
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
