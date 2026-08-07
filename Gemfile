source "http://rubygems.org"

gemspec

# The CLI host this plugin reopens, needed to run the specs. Private (GitHub Packages),
# so it stays out of the gemspec: a public gem must not declare a private dependency.
source "https://rubygems.pkg.github.com/botandrosedesign" do
  gem "bard-cli"
end

group :test do
  gem "simplecov", require: false
  gem "webmock", require: false
end
