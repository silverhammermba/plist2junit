#!/usr/bin/env ruby
require 'json'

# a better version of SonarQube's xccov-to-sonarqube-generic.sh

if ARGV.length != 1
  warn "usage: #$0 action.xccovarchive"
  exit 1
end

coverage_pattern = /\A\s*(\d+):\s*(\d+)/

puts '<coverage version="1">'
IO.popen(%w{xcrun xccov view --file-list} << ARGV[0]) do |paths|
  paths.each_line do |path|
    # TODO: this is absolute. want path relative to cwd
    path.strip!
    puts "<file path=#{path.encode xml: :attr}>"
    IO.popen(%w{xcrun xccov view --file} << path << ARGV[0]) do |coverage|
      open = false

      coverage.each_line do |metrics|
        if metrics =~ coverage_pattern
          puts "<lineToCover lineNumber=\"#$1\" covered=\"#{$2 != ?0}\"/>"
        end
      end
    end
    puts '</file>'
  end
end
