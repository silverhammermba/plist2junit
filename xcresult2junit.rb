#!/usr/bin/env ruby
require 'json'

if ARGV.length != 1
  warn "usage: #$0 Foobar.xcresult"
  exit 1
end

$xcresult = ARGV[0]

def get_object id
  result = nil
  IO.popen(%w{xcrun xcresulttool get --format json --path} << $xcresult << '--id' << id) do |object|
    result = JSON.load object
  end
  result
end

# get test result id from xcresults
results = nil
IO.popen(%w{xcrun xcresulttool get --format json --path} << $xcresult) do |result_summary|
  results = JSON.load result_summary
end

# load test results by id
testsRef = results['actions']['_values'][0]['actionResult']['testsRef']['id']['_value']
tests = get_object testsRef

# transform to a dictionary that mimics the output structure

test_suites = []

tests['summaries']['_values'][0]['testableSummaries']['_values'].each do |target|
  target_name = target['targetName']['_value']

  # if the test target failed to launch at all, get first failure message
  unless target['tests']
    failure_summary = target['failureSummaries']['_values'][0]
    test_suites << {name: target_name, error: failure_summary['message']['_value']}
    next
  end

  test_classes = target['tests']['_values']

  # else process the test classes in each target
  # first two levels are just summaries, so skip those
  test_classes[0]['subtests']['_values'][0]['subtests']['_values'].each do |test_class|
    suite = {name: "#{target_name}.#{test_class['name']['_value']}", cases: []}

    # process the tests in each test class
    tests = test_class.dig('subtests', '_values')

    if tests
      tests.each do |test|
        duration = 0
        if test['duration']
          duration = test['duration']['_value']
        end

        testcase = {name: test['name']['_value'], time: duration}

        if test['testStatus']['_value'] == 'Failure'
          failures = get_object(test['summaryRef']['id']['_value'])['failureSummaries']['_values']

          message = failures.map { |failure| failure['message']['_value'] }.join("\n")
          location = failures.select { |failure| failure['fileName']['_value'] != '<unknown>' }.first

          if location
            testcase[:failure] = message
            testcase[:failure_location] = "#{location['fileName']['_value']}:#{location['lineNumber']['_value']}"
          else
            testcase[:error] = message
          end
        end

        suite[:cases] << testcase
      end
    else
      # consider a test class without tests to be an error
      # there's no good reason to have an empty test class, and it can occur as an error
      suite[:cases] << {name: 'Missing tests', time: 0, error: 'No test results found'}
    end

    suite[:count] = suite[:cases].size
    suite[:failures] = suite[:cases].count { |testcase| testcase[:failure] }
    suite[:errors] = suite[:cases].count { |testcase| testcase[:error] }
    test_suites << suite
  end
end

# format the data

puts '<?xml version="1.0" encoding="UTF-8"?>'
puts "<testsuites>"
test_suites.each do |suite|
  if suite[:error]
    puts "<testsuite name=#{suite[:name].encode xml: :attr} errors='1'>"
    puts "<error>#{suite[:error].encode xml: :text}</error>"
    puts '</testsuite>'
  else
    puts "<testsuite name=#{suite[:name].encode xml: :attr} tests='#{suite[:count]}' failures='#{suite[:failures]}' errors='#{suite[:errors]}'>"

    suite[:cases].each do |testcase|
      print "<testcase classname=#{suite[:name].encode xml: :attr} name=#{testcase[:name].encode xml: :attr} time='#{testcase[:time]}'"
      if testcase[:failure]
        puts '>'
        puts "<failure message=#{testcase[:failure].encode xml: :attr}>#{testcase[:failure_location].encode xml: :text}</failure>"
        puts '</testcase>'
      elsif testcase[:error]
        puts '>'
        puts "<error>#{testcase[:error].encode xml: :text}</error>"
        puts '</testcase>'
      else
        puts '/>'
      end
    end

    puts '</testsuite>'
  end
end
puts '</testsuites>'
