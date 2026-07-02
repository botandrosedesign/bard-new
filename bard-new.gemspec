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

  spec.add_dependency "bard", ">= 2.1.0"

  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "debug"
  spec.add_development_dependency "cucumber"
  spec.add_development_dependency "testcontainers"
end
