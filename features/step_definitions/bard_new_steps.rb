Then /^the output should contain "([^\"]+)"$/ do |expected|
  expect(@stdout).to include(expected)
end

# bard new steps
Given /^a bard new server is running$/ do
  raise "New server failed to start" unless @new_container && @new_ssh_port
end

When /^I run bard new for real$/ do
  run_bard_remote("new #{@project_name}")
  raise "bard new failed with status: #{@status}\nOutput: #{@stdout}" unless @status.success?
end

Then /^the project isolates parallel test databases$/ do
  stdout, status = run_new_ssh("cat /tmp/bardwork/#{@project_name}/config/database.yml")
  expect(status).to be_success, "could not read database.yml:\n#{stdout}"
  expect(stdout).to include("TEST_ENV_NUMBER")
end

Then /^the project is served by Passenger at its dev url$/ do
  body = nil
  10.times do
    body, status = run_new_ssh("curl -sf -H 'Host: #{@project_name}.localhost' http://localhost/")
    break if status.success? && body.include?(@project_name)
    sleep 3
  end
  expect(body).to include(@project_name), "dev site (Passenger) did not serve the app:\n#{body}"
end

Then /^the project's CI suite passed on GitHub Actions$/ do
  # bard new only succeeds if `bard deploy` gated on a green CI run, but assert it
  # explicitly against the GitHub Actions API. (bard's run! swallows the CI output
  # on success, so we can't scrape it from @stdout.)
  out = nil
  3.times do
    out, st = run_new_ssh("cd /tmp/bardwork/#{@project_name} && bard ci --status")
    break if st.success? && out =~ /succeeded/i
    sleep 3
  end
  expect(out).to match(/succeeded/i), "bard ci --status did not report success:\n#{out}"
end

Then /^the project responds on staging$/ do
  body = nil
  10.times do
    body, status = run_new_ssh("curl -sf https://#{@project_name}.botandrose.com/")
    break if status.success? && body.include?(@project_name)
    sleep 3
  end
  expect(body).to include(@project_name), "staging site did not serve the app:\n#{body}"
end

Then /^the project has its own rvm gemset$/ do
  stdout, _ = run_new_ssh("rvm gemset list")
  expect(stdout).to include(@project_name), "expected an rvm gemset named #{@project_name}:\n#{stdout}"
end

# bard destroy steps
When /^I destroy the project$/ do
  stdout, status = run_new_ssh("cd /tmp/bardwork/current && bard destroy #{@project_name} --yes")
  raise "bard destroy failed:\n#{stdout}" unless status.success?
  @destroyed = true
end

Then /^the local rvm gemset is removed$/ do
  stdout, _ = run_new_ssh("rvm gemset list")
  expect(stdout).not_to include(@project_name), "rvm gemset #{@project_name} still present:\n#{stdout}"
end

Then /^the staging deploy is removed$/ do
  stdout, _ = staging_ssh("ls -d ~/#{@project_name} 2>&1")
  expect(stdout).to match(/No such file|cannot access/), "staging app dir still present:\n#{stdout}"
end

Then /^the GitHub repo no longer exists$/ do
  expect(github_repo_status(@project_name)).to eq("404"), "GitHub repo botandrosedesign/#{@project_name} still exists"
end

# bard provision steps
Given /^a provision server is running$/ do
  raise "Provision server failed to start" unless @container && @ssh_port
end

When /^I provision the system$/ do
  run_provision_phase1
  unless @status.success?
    raise "Provision phase 1 failed:\n#{@stdout}"
  end
end

When /^I set up the test project$/ do
  setup_test_project
end

When /^I provision the app$/ do
  run_provision_phase2
  unless @status.success?
    raise "Provision phase 2 failed:\n#{@stdout}"
  end
end

Then /^the site should be running$/ do
  stdout, status = Open3.capture2e("curl -sf http://127.0.0.1:#{@http_port}/")
  expect(status).to be_success, "Site not responding on port #{@http_port}"
  expect(stdout).to include("hello from testproject")
end
