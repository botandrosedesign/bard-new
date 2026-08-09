source "http://rubygems.org"

gemspec

# The CLI host this plugin reopens, needed to run the specs. Private (GitHub Packages),
# so it stays out of the gemspec: a public gem must not declare a private dependency.
bard_cli_path = File.expand_path("../bard-cli", __dir__)
if File.directory?(bard_cli_path)
  gem "bard-cli", path: bard_cli_path
else
  source "https://rubygems.pkg.github.com/botandrosedesign" do
    gem "bard-cli"
  end
end

group :test do
  gem "simplecov", require: false
  gem "webmock", require: false
end
