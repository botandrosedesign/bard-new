require "simplecov"
SimpleCov.start do
  command_name "Cucumber"
  cover "lib/**/*.rb"
end

$LOAD_PATH.unshift(File.dirname(__FILE__) + '/../../lib')
require "bard/cli"
require 'rspec/expectations'
require 'fileutils'

ENV["PATH"] = "#{File.dirname(File.expand_path(__FILE__))}:#{ENV['PATH']}"
ENV["GIT_DIR"] = nil
ENV["GIT_WORK_TREE"] = nil
ENV["GIT_INDEX_FILE"] = nil

ROOT = File.expand_path(File.dirname(__FILE__) + '/../..')

# Ensure tmp directory exists
FileUtils.mkdir_p(File.join(ROOT, "tmp"))
