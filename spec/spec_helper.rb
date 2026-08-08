require "simplecov"
SimpleCov.start do
  command_name "RSpec"
  cover "lib/**/*.rb"
end

require "webmock/rspec"

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "debug/prelude"
require "bard/cli"
require "bard/plugins/new"

RSpec.configure do |config|
  config.filter_run focus: true
  config.run_all_when_everything_filtered = true
end
