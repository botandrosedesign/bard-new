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

Then /^the project "([^"]+)" should respond to http:\/\/(.+)$/ do |project_name, hostname|
  # Configure Passenger to use the project's gemset-specific Ruby wrapper
  run_new_ssh("sudo sed -i '/passenger_enabled/a\\    passenger_ruby /home/deploy/.rvm/wrappers/ruby-4.0.2@#{project_name}/ruby;' /etc/nginx/snippets/common.conf")
  run_new_ssh("sudo nginx -s reload")
  sleep 3
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
