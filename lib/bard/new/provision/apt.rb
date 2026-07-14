# apt sanity

class Bard::Provision::Apt < Bard::Provision
  def call
    print "Apt:"
    provision_server.run! [
      %(echo "\\$nrconf{restart} = \\"a\\";" | sudo tee /etc/needrestart/conf.d/90-autorestart.conf),
      "sudo apt-get -o DPkg::Lock::Timeout=600 update -y",
      "sudo apt-get -o DPkg::Lock::Timeout=600 upgrade -y",
      "sudo apt-get -o DPkg::Lock::Timeout=600 install -y curl build-essential libsodium-dev",
    ].join("; "), home: true

    puts " ✓"
  end
end
