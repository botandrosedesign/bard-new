require "bard/config"
require "bard/plugins/github"
require "bard/new/site_removal"

class Bard::CLI
  desc "destroy [PROJECT]", "tears down a project: every deployed site, its GitHub repo, and the local checkout"
  method_option :yes, type: :boolean, default: false, desc: "skip the confirmation prompt"
  method_option :target, type: :string, desc: "tear down only this target's site, leaving the repo and checkout alone"
  def destroy(project_name = nil)
    @destroy_project_name = project_name || Bard::Config.detect_project_name
    @destroy_from_parent = !project_name.nil?
    destroy_resolve_project_dir

    if options[:target]
      destroy_validate_target
      destroy_confirm unless options[:yes]
      destroy_site destroy_config[options[:target].to_sym]
      puts green("#{@destroy_project_name} removed from #{options[:target]}.")
      return
    end

    unless @destroy_from_parent
      puts red("!!! ") + "A full destroy deletes this checkout, so it cannot run from inside it."
      puts "    Run #{yellow("cd .. && bard destroy #{@destroy_project_name}")}, or pass #{yellow("--target")} to remove a single site."
      exit 1
    end

    destroy_confirm unless options[:yes]
    destroy_remote
    destroy_github
    destroy_local
    puts green("Project #{@destroy_project_name} destroyed.")
  end

  no_commands do
    # `bard destroy foo` works from foo's parent or from a sibling checkout. A missing
    # bard.rb must abort: Bard::Config silently falls back to a defaults-only config,
    # which would skip any non-default targets and leave their sites behind.
    def destroy_resolve_project_dir
      candidates = @destroy_from_parent ? [@destroy_project_name, "../#{@destroy_project_name}"] : ["."]
      @destroy_project_dir = candidates.find { |dir| File.exist?("#{dir}/bard.rb") }
      return if @destroy_project_dir
      puts red("!!! ") + "Cannot find #{candidates.map { |dir| yellow("#{dir}/bard.rb") }.join(" or ")}."
      puts "    Refusing to destroy without the project's bard.rb — its non-default targets would survive."
      exit 1
    end

    def destroy_validate_target
      return if destroy_config[options[:target].to_sym]
      puts red("!!! ") + "Unknown target #{yellow(options[:target])}. Available targets: #{destroy_config.targets.keys.join(", ")}."
      exit 1
    end

    def destroy_config
      @destroy_config ||= Bard::Config.new(@destroy_project_name, path: "#{@destroy_project_dir}/bard.rb")
    end

    def destroy_confirm
      if options[:target]
        puts "This will remove #{yellow(@destroy_project_name)} from #{yellow(options[:target])}: its services, database, nginx site, rvm gemset, and directory."
      else
        puts "This will permanently delete GitHub repo #{yellow("botandrosedesign/#{@destroy_project_name}")}, every deployed site, and the local project."
      end
      print "Type the project name to confirm: "
      if $stdin.gets&.chomp != @destroy_project_name
        puts red("!!! ") + "Aborted."
        exit 1
      end
    end

    # Every deployed site, not just production: a staging checkout left behind still
    # carries this project's master key on a host shared with every other project.
    def destroy_remote
      destroy_targets.each { |target| destroy_site(target) }
    end

    # Deduped, because with no distinct production :staging and :production are the same
    # target and would otherwise be torn down twice.
    def destroy_targets
      destroy_config.targets.values.select { |t| t.has_capability?(:ssh) }.uniq
    end

    def destroy_site(target)
      dir = "~/#{target.path}"
      unless target.run("test -e #{dir}", home: true, quiet: true)
        puts "#{target.key.to_s.capitalize}: nothing deployed ✓"
        return
      end
      destroy_teardown(target, dir)
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
      destroy_teardown(destroy_config[:local], @destroy_project_dir)
    end

    # The servers have no bard install, so the teardown is sent over as plain shell.
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
