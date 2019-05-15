#!/usr/bin/env ruby
require 'json'
require 'stringio'

# a better version of SonarQube's xccov-to-sonarqube-generic.sh

if ARGV.length != 1
  warn "usage: #$0 whatever.xccovarchive"
  exit 1
end

coverage_pattern = /\A\s*(\d+):\s*(\d+)/

paths = nil
IO.popen(%w{xcrun xccov view --file-list} << ARGV[0]) do |list|
  paths = list.read.split("\n")
end

threads = paths.map do |path|
  Thread.new do
    io = StringIO.new
    # TODO: this is absolute. want path relative to cwd
    io.puts "<file path=#{path.encode xml: :attr}>"
    begin
      IO.popen(%w{xcrun xccov view --file} << path << ARGV[0]) do |coverage|
        coverage.each_line do |metrics|
          if metrics =~ coverage_pattern
            io.puts "<lineToCover lineNumber=\"#$1\" covered=\"#{$2 != ?0}\"/>"
          end
        end
      end
    # too many files open, just wait
    rescue Errno::EMFILE, Errno::ENFILE
      sleep 1
      retry
    end
    io.puts '</file>'
    io.string
  end
end

puts '<coverage version="1">'
threads.each do |thread|
  puts thread.value
end
puts '</coverage>'
