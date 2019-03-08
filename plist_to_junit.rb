#!/usr/bin/env ruby
require 'json'

if ARGV.length != 1
  warn "usage: #$0 TestSummaries.plist"
  exit 1
end

# convert plist to a dictionary

plist = nil
IO.popen(%w{plutil -convert json -o -} << ARGV[0]) do |plutil|
  plist = JSON.load plutil
end

# transform to a dictionary that mimics the output structure

test_suites = []

plist['TestableSummaries'].each do |target|
  test_classes = target["Tests"]

  # if the test target failed to launch at all
  if test_classes.empty? && target['FailureSummaries']
    test_suites << {name: target['TestName'], error: target['FailureSummaries'][0]['Message']}
    next
  end

  # else process the test classes in each target
  # first two levels are just summaries, so skip those
  test_classes[0]["Subtests"][0]["Subtests"].each do |test_class|
    suite = {name: "#{target['TestName']}.#{test_class['TestName']}", cases: []}

    # process the tests in each test class
    test_class["Subtests"].each do |test|
      testcase = {name: test['TestName'], time: test['Duration']}

      if test['FailureSummaries']
        failure = test['FailureSummaries'][0]

        filename = failure['FileName']

        if filename == '<unknown>'
          testcase[:error] = failure['Message']
        else
          testcase[:failure] = failure['Message']
          testcase[:failure_location] = "#{filename}:#{failure['LineNumber']}"
        end
      end

      suite[:cases] << testcase
    end

    suite[:count] = suite[:cases].size
    suite[:failures] = suite[:cases].count { |testcase| testcase[:failure] }
    suite[:errors] = suite[:cases].count { |testcase| testcase[:error] }
    test_suites << suite
  end
end

# format the data

def attr str
  str.gsub ?', '&apos;'
end

puts '<?xml version="1.0" encoding="UTF-8"?>'
puts "<testsuites>"
test_suites.each do |suite|
  if suite[:error]
    puts "<testsuite name='#{attr suite[:name]}' errors='1'>"
    puts "<error>#{suite[:error]}</error>"
    puts '</testsuite>'
  else
    puts "<testsuite name='#{attr suite[:name]}' tests='#{suite[:count]}' failures='#{suite[:failures]}' errors='#{suite[:errors]}'>"

    suite[:cases].each do |testcase|
      print "<testcase classname='#{attr suite[:name]}' name='#{attr testcase[:name]}' time='#{testcase[:time]}'"
      if testcase[:failure]
        puts '>'
        puts "<failure message='#{attr testcase[:failure]}'>#{testcase[:failure_location]}</failure>"
        puts '</testcase>'
      elsif testcase[:error]
        puts '>'
        puts "<error>#{testcase[:error]}</error>"
        puts '</testcase>'
      else
        puts '/>'
      end
    end

    puts '</testsuite>'
  end
end
puts '</testsuites>'
