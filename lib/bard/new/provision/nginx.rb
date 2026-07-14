require "uri"

# install nginx and configure the app site

class Bard::Provision::Nginx < Bard::Provision
  def call
    print "Nginx:"
    if !http_responding?
      print " Installing nginx,"
      provision_server.run! [
        %(grep -qxF "RAILS_ENV=production" /etc/environment || echo "RAILS_ENV=production" | sudo tee -a /etc/environment),
        %(grep -qxF "EDITOR=vim" /etc/environment || echo "EDITOR=vim" | sudo tee -a /etc/environment),
        "sudo apt-get install -y nginx",
        "sudo rm -f /etc/nginx/sites-enabled/default",
      ].join("; "), home: true
    end

    if !app_configured?
      print " Creating nginx config for app,"
      install_app_config!
    end

    # procsd's systemd --user units need a persistent user manager to survive reboot.
    provision_server.run! "sudo loginctl enable-linger #{provision_server.ssh_uri.user}", home: true

    puts " ✓"
  end

  def http_responding?
    provision_server.run "nc -zv localhost 80 2>/dev/null", home: true, quiet: true
  end

  def app_configured?
    provision_server.run "[ -f /etc/nginx/sites-enabled/#{config.project_name} ]", quiet: true
  end

  private

  def install_app_config!
    path = "/etc/nginx/sites-available/#{config.project_name}"
    provision_server.run! [
      %(sudo tee #{path} >/dev/null <<-'EOF'\n#{nginx_config}EOF),
      "sudo ln -sf #{path} #{path.sub("sites-available", "sites-enabled")}",
      "sudo service nginx restart",
    ].join("\n"), home: true
  end

  def nginx_config
    <<~EOF
      upstream puma {
          server 127.0.0.1:3000 fail_timeout=5;
      }

      server {
          listen 80;
          server_name #{server_name};
          root #{app_root}/public;

          try_files $uri @app;

          location @app {
              proxy_pass http://puma;
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
          }

          location ~* \\-[0-9a-f]\\{64\\}\\.(ico|css|js|gif|jpe?g|png|webp)$ {
              access_log off;
              expires max;
              add_header Cache-Control public;
          }

          gzip_static on;
      }
    EOF
  end

  def server_name
    # prefer the public ping host: `ssh` auto-derives `url` to the origin, not the proxied site.
    host = URI.parse(target.ping.first || target.url).host
    "*.#{host} _"
  end

  def app_root
    provision_server.run!("pwd", capture: true).strip
  end
end
