require "bard/config"
require "bard/plugins/github"
require "bard/new/site_removal"

class Bard::CLI
  desc "destroy <project-name>", "tears down everything `bard new` created: remote deploy, GitHub repo, and local project"
  method_option :yes, type: :boolean, default: false, desc: "skip the confirmation prompt"
  def destroy(project_name)
    @destroy_project_name = project_name
    destroy_confirm unless options[:yes]
    destroy_remote
    destroy_github
    destroy_local
    puts green("Project #{project_name} destroyed.")
  end

  no_commands do
    def destroy_config
      @destroy_config ||= Bard::Config.new(@destroy_project_name, path: "../#{@destroy_project_name}/bard.rb")
    end

    def destroy_confirm
      puts "This will permanently delete GitHub repo #{yellow("botandrosedesign/#{@destroy_project_name}")}, its remote deployment, and the local project."
      print "Type the project name to confirm: "
      if $stdin.gets&.chomp != @destroy_project_name
        puts red("!!! ") + "Aborted."
        exit 1
      end
    end

    def destroy_remote
      target = destroy_config[:production]
      return unless target&.has_capability?(:ssh)
      destroy_teardown(target, "~/#{@destroy_project_name}")
    end

    def destroy_github
      print "GitHub:"
      Bard::Github.new(@destroy_project_name).delete_repo
      puts " ✓"
    rescue => e
      puts " !!!"
      puts red("!!! ") + "Failed to delete GitHub repo #{yellow("botandrosedesign/#{@destroy_project_name}")}."
      puts "    Does the github-apikey token have the `delete_repo` scope? (`repo` scope alone cannot delete repos.)"
      puts "    #{e.message.to_s[0, 300]}"
      raise
    end

    def destroy_local
      destroy_teardown(destroy_config[:local], "../#{@destroy_project_name}")
    end

    def destroy_teardown(target, project_dir)
      print "#{target.key.to_s.capitalize}:"
      Bard::SiteRemoval.new(project_dir).steps.each do |label, script|
        print " #{label},"
        target.run! script, home: true, quiet: true
      end
      puts " ✓"
    end
  end
end
