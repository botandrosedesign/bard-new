Then /^the output should contain "([^\"]+)"$/ do |expected|
  expect(@stdout).to include(expected)
end

# bard new steps
Given /^a bard new server is running$/ do
  raise "New server failed to start" unless @new_container && @new_ssh_port
end

When /^I run bard new "([^"]+)"$/ do |project_name|
  run_bard_remote("new #{project_name} --skip-github --skip-stage")
  unless @status.success?
    raise "bard new failed with status: #{@status}\nOutput: #{@stdout}"
  end
end

Then /^the project "([^"]+)" should run successfully$/ do |project_name|
  stdout, status = run_new_ssh("cd /tmp/bardwork/#{project_name} && bin/rails runner 'puts :bard_test_ok'")
  expect(status).to be_success, "rails runner failed:\n#{stdout}"
  expect(stdout).to include("bard_test_ok")
end

Then /^the project "([^"]+)" isolates parallel test databases$/ do |project_name|
  stdout, status = run_new_ssh("cat /tmp/bardwork/#{project_name}/config/database.yml")
  expect(status).to be_success, "could not read database.yml:\n#{stdout}"
  expect(stdout).to include("TEST_ENV_NUMBER")
end

Then /^the project "([^"]+)" passes its CI suite$/ do |project_name|
  stdout, status = run_new_ssh("cd /tmp/bardwork/#{project_name} && CI=1 bundle exec rake")
  expect(status).to be_success, "CI suite failed for #{project_name}:\n#{stdout}"
end

Then /^the project "([^"]+)" should respond to http:\/\/(.+)$/ do |project_name, hostname|
  Open3.capture2e(
    "timeout", "3",
    "ssh", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
    "-p", @new_ssh_port.to_s, "-i", new_ssh_key_path,
    "deploy@localhost",
    "bash -lc 'cd /tmp/bardwork/#{project_name} && setsid -f bundle exec puma -p 3000 </dev/null >/tmp/puma.log 2>&1'"
  )
  sleep 5
  stdout, status = run_new_ssh("curl -sf -H 'Host: #{hostname}' http://localhost/")
  expect(status).to be_success, "HTTP request to #{hostname} failed:\n#{stdout}"
  expect(stdout).to include(project_name)
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
