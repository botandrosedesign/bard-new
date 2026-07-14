# install mysql

class Bard::Provision::MySQL < Bard::Provision
  def call
    print "MySQL:"
    if !mysql_responding?
      print " Installing,"
      provision_server.run! "sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 install -y mysql-server", home: true
    end

    print " Granting #{deploy_user} peer auth,"
    provision_server.run! [
      # Passwordless: MySQL maps the OS user to this account over the unix socket.
      %{sudo mysql -e "CREATE USER IF NOT EXISTS '#{deploy_user}'@'localhost' IDENTIFIED WITH auth_socket"},
      %{sudo mysql -e "ALTER USER '#{deploy_user}'@'localhost' IDENTIFIED WITH auth_socket"},
      %{sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO '#{deploy_user}'@'localhost'"},
      # Retire the empty-password root: only the OS root user is MySQL root now.
      %{sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH auth_socket"},
      %{sudo mysql -e "FLUSH PRIVILEGES"},
    ].join("; "), home: true

    puts " ✓"
  end

  def deploy_user
    provision_server.ssh_uri.user
  end

  def mysql_responding?
    provision_server.run "sudo systemctl is-active --quiet mysql", home: true, quiet: true
  end
end
