require "bard/copy"

# copy data from the previous production server

class Bard::Provision::Data < Bard::Provision
  def call
    print "Data:"

    if source.ssh&.to_s == ssh_url
      puts " no previous production to pull from, skipping. Seed with: bard data --from=local --to=production ✓"
      return
    end

    print " Dumping #{source.key} database to file,"
    source.run! "bin/rake db:dump"

    print " Transfering file from #{source.key},"
    Bard::Copy.file "db/data.sql.gz", from: source, to: provision_server, verbose: false

    print " Loading file into database,"
    provision_server.run! "bin/rake db:load"

    Array(config.data).each do |path|
      print " Synchronizing files in #{path},"
      Bard::Copy.dir path, from: source, to: provision_server, verbose: false
    end

    puts " ✓"
  end

  private

  # mid-migration, bard.rb holds the previous production as :old_production
  # while :production already describes the box being provisioned.
  def source
    config[:old_production] || target
  end
end
