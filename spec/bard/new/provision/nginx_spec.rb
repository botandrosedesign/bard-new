require "spec_helper"
require "bard/new/provision/base"
require "bard/new/provision/nginx"

describe Bard::Provision::Nginx do
  let(:target) { double("target", project_name: "test_app", ping: ["https://test.example.com"]) }
  let(:config) { double("config", project_name: "test_app", :[] => target) }
  let(:ssh_url) { "www@example.com" }
  let(:provision_server) { double("provision_server", ssh_uri: double("ssh_uri", user: "www")) }
  let(:nginx) { Bard::Provision::Nginx.new(config, ssh_url) }

  before do
    allow(nginx).to receive(:target).and_return(target)
    allow(nginx).to receive(:provision_server).and_return(provision_server)
    allow(nginx).to receive(:print)
    allow(nginx).to receive(:puts)
    allow(provision_server).to receive(:run!)
    allow(provision_server).to receive(:run!).with("pwd", capture: true).and_return("/home/www/test_app\r\n")
  end

  describe "#call" do
    context "when HTTP is not responding" do
      it "installs nginx" do
        allow(nginx).to receive(:http_responding?).and_return(false)
        allow(nginx).to receive(:app_config_current?).and_return(true)

        expect(provision_server).to receive(:run!).with(/apt-get .*install -y nginx/, home: true)

        nginx.call
      end
    end

    context "when the deployed config is missing or stale" do
      before do
        allow(nginx).to receive(:http_responding?).and_return(true)
        allow(nginx).to receive(:app_config_current?).and_return(false)
      end

      it "writes the nginx site config itself, without bard-cli on the server" do
        expect(provision_server).to receive(:run!).with(
          a_string_matching(%r{sudo tee /etc/nginx/sites-available/test_app})
            .and(a_string_matching(%r{server_name \*\.test\.example\.com _;}))
            .and(a_string_matching(%r{root /home/www/test_app/public;}))
            .and(a_string_matching(%r{proxy_pass http://puma;}))
            .and(a_string_matching(%r{ln -sf /etc/nginx/sites-available/test_app /etc/nginx/sites-enabled/test_app}))
            .and(a_string_matching(/service nginx restart/)),
          home: true,
        )

        nginx.call
      end

      it "quotes the fingerprinted-asset regex so nginx treats {64} as a quantifier" do
        expect(provision_server).to receive(:run!).with(
          a_string_including("location ~* \"-[0-9a-f]{64}\\.(ico|css|js|gif|jpe?g|png|webp)$\" {"),
          home: true,
        )

        nginx.call
      end

      it "does not interpolate shell variables into the config" do
        expect(provision_server).to receive(:run!).with(
          a_string_matching(/<<-'EOF'/).and(a_string_matching(/try_files \$uri @app;/)),
          home: true,
        )

        nginx.call
      end
    end

    it "enables lingering so procsd user units survive reboot" do
      allow(nginx).to receive(:http_responding?).and_return(true)
      allow(nginx).to receive(:app_config_current?).and_return(true)

      expect(provision_server).to receive(:run!).with("sudo loginctl enable-linger www", home: true)

      nginx.call
    end

    context "when the deployed config matches the generated config" do
      it "skips installation and leaves the config untouched" do
        allow(nginx).to receive(:http_responding?).and_return(true)
        allow(nginx).to receive(:app_config_current?).and_return(true)

        expect(provision_server).not_to receive(:run!).with(a_string_matching(/apt-get|sudo tee/), anything)

        nginx.call
      end
    end

    it "prints status messages" do
      allow(nginx).to receive(:http_responding?).and_return(true)
      allow(nginx).to receive(:app_config_current?).and_return(true)

      expect(nginx).to receive(:print).with("Nginx:")
      expect(nginx).to receive(:puts).with(" ✓")

      nginx.call
    end
  end

  describe "#http_responding?" do
    it "checks if port 80 is responding on the remote" do
      expect(provision_server).to receive(:run).with("nc -zv localhost 80 2>/dev/null", home: true, quiet: true)

      nginx.http_responding?
    end
  end

  describe "#app_config_current?" do
    it "checks the enabled site and compares the deployed config checksum against the generated config" do
      checksum = Digest::SHA256.hexdigest(nginx.send(:nginx_config))

      expect(provision_server).to receive(:run).with(
        a_string_including("[ -f /etc/nginx/sites-enabled/test_app ]")
          .and(a_string_including("#{checksum}  /etc/nginx/sites-available/test_app"))
          .and(a_string_including("sha256sum -c --status")),
        quiet: true,
      )

      nginx.app_config_current?
    end
  end
end
