lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "bard/new/version"

Gem::Specification.new do |spec|
  spec.name          = "bard-new"
  spec.version       = Bard::New::VERSION
  spec.authors       = ["Micah Geisel"]
  spec.email         = ["micah@botandrose.com"]
  spec.summary       = "Project creation and server provisioning for bard."
  spec.homepage      = "http://github.com/botandrose/bard-new"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  # bard (config core) is public and is a real runtime dependency: Bard::Config parses
  # each site's bard.rb. Bard::CLI itself comes from the private bard-cli gem, which
  # loads this plugin — a public gem must not declare a private dependency, so bard-cli
  # is a dev/test-only dependency in the Gemfile.
  spec.add_dependency "bard", "~> 3.0"

  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "debug"
  spec.add_development_dependency "cucumber"
  spec.add_development_dependency "testcontainers"
end
