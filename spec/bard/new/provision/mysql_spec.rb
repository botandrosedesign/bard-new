require "spec_helper"
require "bard/new/provision/base"
require "bard/new/provision/mysql"

describe Bard::Provision::MySQL do
  let(:config) { { production: double("production") } }
  let(:ssh_url) { "user@example.com" }
  let(:provision_server) { double("provision_server", ssh_uri: double("ssh_uri", user: "www")) }
  let(:mysql) { Bard::Provision::MySQL.new(config, ssh_url) }

  before do
    allow(mysql).to receive(:provision_server).and_return(provision_server)
    allow(mysql).to receive(:print)
    allow(mysql).to receive(:puts)
    allow(provision_server).to receive(:run!)
  end

  describe "#call" do
    context "when MySQL is not responding" do
      it "installs MySQL" do
        allow(mysql).to receive(:mysql_responding?).and_return(false)

        expect(provision_server).to receive(:run!).with(/DEBIAN_FRONTEND=noninteractive.*apt-get .*install -y mysql-server/, home: true)

        mysql.call
      end
    end

    context "when MySQL is already responding" do
      it "skips installation" do
        allow(mysql).to receive(:mysql_responding?).and_return(true)

        expect(provision_server).not_to receive(:run!).with(/apt-get install/, home: true)

        mysql.call
      end
    end

    it "grants the deploy user passwordless socket auth and retires empty-password root" do
      allow(mysql).to receive(:mysql_responding?).and_return(true)

      expect(provision_server).to receive(:run!).with(
        a_string_matching(/CREATE USER IF NOT EXISTS 'www'@'localhost' IDENTIFIED WITH auth_socket/)
          .and(a_string_matching(/GRANT ALL PRIVILEGES ON \*\.\* TO 'www'@'localhost'/))
          .and(a_string_matching(/ALTER USER 'root'@'localhost' IDENTIFIED WITH auth_socket/)),
        home: true,
      )

      mysql.call
    end

    it "chains the statements with && and omits the vestigial FLUSH PRIVILEGES" do
      allow(mysql).to receive(:mysql_responding?).and_return(true)

      expect(provision_server).to receive(:run!).with(
        a_string_matching(/auth_socket" && sudo mysql/)
          .and(satisfy("not chain with ;") { |command| !command.include?(";") })
          .and(satisfy("not flush privileges") { |command| !command.include?("FLUSH PRIVILEGES") }),
        home: true,
      )

      mysql.call
    end

    it "prints status messages" do
      allow(mysql).to receive(:mysql_responding?).and_return(true)

      expect(mysql).to receive(:print).with("MySQL:")
      expect(mysql).to receive(:puts).with(" ✓")

      mysql.call
    end
  end

  describe "#mysql_responding?" do
    it "checks if MySQL service is active" do
      expect(provision_server).to receive(:run).with("sudo systemctl is-active --quiet mysql", home: true, quiet: true)

      mysql.mysql_responding?
    end
  end
end
