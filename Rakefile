require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
end

task :default => :test

task :bump do
  require_relative "lib/mournmail/version"
  version = Mournmail::VERSION.to_i + 1
  tag_name = "v#{version}"
  puts "Bump version to #{version}"
  sh "git checkout main"
  sh "git pull"
  File.write("lib/mournmail/version.rb", <<~EOF)
    module Mournmail
      VERSION = "#{version}"
    end
  EOF
  sh "git commit -a -m 'Bump version to #{version}'"
  sh "git push"
  sh "git tag #{tag_name}"
  sh "git push origin #{tag_name}"
end
