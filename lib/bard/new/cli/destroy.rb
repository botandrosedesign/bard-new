require "bard/config"
require "bard/plugins/github"

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
      name = @destroy_project_name
      print "#{target.key.to_s.capitalize}:"
      print " stopping services,"
      target.run! destroy_stop_services_script(name), home: true, quiet: true
      print " removing nginx site,"
      target.run! destroy_remove_nginx_script(name), home: true, quiet: true
      print " removing rvm gemset,"
      target.run! destroy_remove_gemset_script(name), home: true, quiet: true
      print " removing project directory,"
      target.run! "rm -rf #{project_dir}", home: true, quiet: true
      puts " ✓"
    end

    def destroy_stop_services_script(name)
      [
        "systemctl --user stop #{name}.target 2>/dev/null || true",
        "systemctl --user disable #{name}.target 2>/dev/null || true",
        "rm -f ~/.config/systemd/user/#{name}*.service ~/.config/systemd/user/#{name}.target",
        "rm -rf ~/.config/systemd/user/#{name}.target.wants",
        "systemctl --user daemon-reload 2>/dev/null || true",
      ].join("; ")
    end

    def destroy_remove_nginx_script(name)
      "sudo rm -f /etc/nginx/sites-available/#{name} /etc/nginx/sites-enabled/#{name}; sudo service nginx reload || true"
    end

    def destroy_remove_gemset_script(name)
      "env -i bash -lc 'source ~/.rvm/scripts/rvm && rvm --force gemset delete #{new_ruby_version}@#{name} || true'"
    end
  end
end
