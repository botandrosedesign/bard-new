require "bard/copy"

# copy data from production

class Bard::Provision::Data < Bard::Provision
  def call
    print "Data:"

    print " Dumping #{target.key} database to file,"
    target.run! "bin/rake db:dump"

    print " Transfering file from #{target.key},"
    Bard::Copy.file "db/data.sql.gz", from: target, to: provision_server, verbose: false

    print " Loading file into database,"
    provision_server.run! "bin/rake db:load"

    Array(config.data).each do |path|
      print " Synchronizing files in #{path},"
      Bard::Copy.dir path, from: target, to: provision_server, verbose: false
    end

    puts " ✓"
  end
end
