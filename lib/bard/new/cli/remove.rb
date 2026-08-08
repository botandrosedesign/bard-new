require "bard/new/site_removal"

class Bard::CLI
  desc "remove", "removes this project's deployed site: stops services, drops the database, removes the nginx site and rvm gemset, and deletes the directory"
  method_option :yes, type: :boolean, default: false, desc: "skip the confirmation prompt"
  method_option :target, type: :string, desc: "remove the site on this target (e.g. staging) instead of the local checkout"
  def remove
    target = options[:target] && config[options[:target].to_sym]
    target&.require_capability!(:ssh)

    dir = target ? "~/#{target.path}" : Dir.pwd
    name = File.basename(dir)
    where = target ? "on #{target.key}" : "at #{dir}"

    unless options[:yes]
      print "This will stop services, drop the database, remove the nginx site and rvm gemset, and delete #{name} #{where}.\nType #{yellow(name)} to confirm: "
      if $stdin.gets&.chomp != name
        puts red("!!! ") + "Aborted."
        exit 1
      end
    end

    print "Removing #{name} #{where}:"
    removal = Bard::SiteRemoval.new(dir)
    if target
      # The server has no bard install, so send the steps over ssh as plain shell.
      removal.steps.each do |label, script|
        print " #{label},"
        target.run! script, home: true, quiet: true
      end
    else
      removal.call
    end
    puts " ✓"
  end
end
