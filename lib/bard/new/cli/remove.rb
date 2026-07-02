require "bard/new/site_removal"

class Bard::CLI
  desc "remove", "removes the deployed site in the current directory: stops services, drops the database, removes the nginx site and rvm gemset, and deletes the directory"
  method_option :yes, type: :boolean, default: false, desc: "skip the confirmation prompt"
  def remove
    name = File.basename(Dir.pwd)
    unless options[:yes]
      print "This will stop services, drop the database, remove the nginx site and rvm gemset, and delete #{Dir.pwd}.\nType #{yellow(name)} to confirm: "
      if $stdin.gets&.chomp != name
        puts red("!!! ") + "Aborted."
        exit 1
      end
    end
    print "Removing #{name}:"
    Bard::SiteRemoval.new(Dir.pwd).call
    puts " ✓"
  end
end
