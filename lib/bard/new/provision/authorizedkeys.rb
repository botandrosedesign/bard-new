# enforce the canonical public key set

class Bard::Provision::AuthorizedKeys < Bard::Provision
  def call
    print "Authorized Keys:"

    provision_server.run! [
      %(echo "#{KEYS.join("\n")}" > ~/.ssh/authorized_keys),
      "chmod 600 ~/.ssh/authorized_keys",
    ].join(" && "), home: true

    puts " ✓"
  end

  KEYS = [
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIMS+4KCxF7/C04+tav+sIqqkVEwccCLpwH2dNUDema8eAAAABHNzaDo= micah@mehve yubikey_orange_35807892",
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAINUX8b45hsRsEcuAtg9l29Z/Gmo/oyYOUZKzYbFUTeJXAAAABHNzaDo= micah@mehve yubikey_green_26948019",
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIDklqyJWgq05rBTn4vvnj3GlDOJzSp9CSVXeIHZmMlv9AAAABHNzaDo= gubito@mac yubikey_yellow_37816401",
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAICDKD8ecjlh7YrjJLjEhvSa1sPuIh0GHENXuplJUaKU8AAAABHNzaDo= gubito@mac yubikey_red_37816400",
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIJILcE/2DRSbSlJuveWa4UzSdzj9fLkpE65+0zriKN/ZAAAABHNzaDo= micah@mehve yubikey_nano_38200779",
  ]
end
