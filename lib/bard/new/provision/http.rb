require "uri"

# test for existence

class Bard::Provision::HTTP < Bard::Provision
  RETRIES = 15

  def call
    print "HTTP:"
    target_host = URI.parse(target.url).host
    if serving?(target_host)
      puts " ✓"
    else
      puts " !!! not serving a rails app from #{provision_server.ssh_uri.host}"
    end
  end

  private

  # the app server may still be booting right after deploy; give it a moment.
  def serving?(host)
    RETRIES.times do |n|
      return true if system "curl -sf --resolve #{host}:80:#{provision_server.ssh_uri.host} http://#{host} -o /dev/null"
      sleep 2 unless n == RETRIES - 1
    end
    false
  end
end
