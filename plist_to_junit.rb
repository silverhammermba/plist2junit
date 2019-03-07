#!/usr/bin/env ruby
require 'json'

if ARGV.length != 1
  warn "usage: #$0 TestSummaries.plist"
  exit 1
end

plist = nil

IO.popen(%w{plutil -convert json -o -} << ARGV[0]) do |plutil|
  plist = JSON.load plutil
end

# transform data
tests = {suites: []}

plist['TestableSummaries'].each do |testsuite|
  suitetests = testsuite["Tests"]

  # TODO this is for a suite error, but what if a single test case has an error?
  if suitetests.empty? && testsuite['FailureSummaries']
    tests[:suites] << {name: testsuite['TestName'], error: testsuite['FailureSummaries'][0]['Message']}
  else
    test_classes = suitetests[0]["Subtests"][0]["Subtests"]
    test_classes.each do |test_class|
      klass = "#{testsuite['TestName']}.#{test_class['TestName']}"
      suite = {name: klass, cases: []}

      test_class["Subtests"].each do |testcase|
        result = {name: testcase['TestName'], time: testcase['Duration']}

        if testcase['FailureSummaries']
          failure = testcase['FailureSummaries'][0]
          result[:failure] = failure['Message']
          result[:failure_location] = "#{failure['FileName']}:#{failure['LineNumber']}"
        end

        suite[:cases] << result
      end

      suite[:count] = suite[:cases].size
      suite[:failures] = suite[:cases].count { |testcase| testcase[:failure] }
      tests[:suites] << suite
    end
  end
end

# print data

puts '<?xml version="1.0" encoding="UTF-8"?>'
puts "<testsuites>"
tests[:suites].each do |suite|
  if suite[:error]
    puts "<testsuite name='#{suite[:name]}' errors='1'>"
    puts "<error>#{suite[:error]}</error>"
    puts '</testsuite>'
  else
    puts "<testsuite name='#{suite[:name]}' tests='#{suite[:count]}' failures='#{suite[:failures]}'>"

    suite[:cases].each do |testcase|
      print "<testcase classname='#{suite[:name]}' name='#{testcase[:name]}' time='#{testcase[:time]}'"
      if testcase[:failure]
        puts '>'
        puts "<failure message='#{testcase[:failure]}'>#{testcase[:failure_location]}</failure>"
        puts '</testcase>'
      else
        puts '/>'
      end
    end

    puts '</testsuite>'
  end
end
puts '</testsuites>'
