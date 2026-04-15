require "bard/plugins/ssh/copy"

# copy master key if missing

class Bard::Provision::MasterKey < Bard::Provision
  def call
    print "Master Key:"
    if File.exist?("config/master.key")
      if !provision_server.run "[ -f config/master.key ]", quiet: true
        print " Uploading config/master.key,"
        Bard::Copy.file "config/master.key", from: config[:local], to: provision_server
      end
    end

    puts " ✓"
  end
end
