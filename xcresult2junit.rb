#!/usr/bin/env ruby
require 'json'

if ARGV.length != 1
  warn "usage: #$0 Foobar.xcresult"
  exit 1
end

xcresult = ARGV[0]

# get test results from xcresults
results = nil
IO.popen(%w{xcrun xcresulttool get test-results tests --path} << xcresult) do |result_summary|
  results = JSON.load result_summary
end

# transform test suites to dictionaries that mimic the output structure

all_test_suites = []
empty_test_suite_counts = Hash.new(0) # default value 0 to allow incrementing before a value is initialized

results['testNodes'].each do |test_plan|
  test_plan['children'].each do |test_bundle|
    bundle_name = test_bundle['name']

    test_suites = test_bundle['children']

    # consider a bundle without test suites to be an error
    unless test_suites && test_suites.length > 0
      test_suites << {name: bundle_name, error: 'no test results found'}
      next
    end

    # else process the test suites in each test bundle
    test_bundle['children'].each do |test_suite|
      suite = {name: "#{bundle_name}.#{test_suite['name']}", cases: []}

      # process the tests in each test suite
      test_cases = test_suite['children']

      unless test_cases && test_cases.length > 0
        # consider a test suite without tests to be an error
        # there's no good reason to have an empty test suite, and it can occur as an error
        empty_test_suite_counts[suite[:name]] += 1
        next
      end

      test_cases.each do |test|
        duration = 0
        if test['duration']
          # strip trailing 's'
          duration = test['duration'][0...-1]
        end

        testcase = {name: test['name'], time: duration}

        if test['result'] == 'Skipped'
          testcase[:skipped] = (test['children'] || []).map { |child| child['name'] }.join("\n")
        elsif test['result'] == 'Failed'
          failure_messages = test['children']

          message = nil
          location = nil

          failure_messages.each do |failure_message|
            text = failure_message['name']
            if text =~ /^([^:]+):((\d+):)? (.*)/
              file_name = $1
              line_number = $3
              text = $4

              unless location
                location = "#{file_name}:#{line_number}"
              end
            end

            if message
              message += "\n#{text}"
            else
              message = text
            end
          end

          if location
            testcase[:failure] = message
            testcase[:failure_location] = location
          else
            testcase[:error] = message
          end
        end

        suite[:cases] << testcase
      end

      suite[:count] = suite[:cases].size
      suite[:failures] = suite[:cases].count { |testcase| testcase[:failure] }
      suite[:errors] = suite[:cases].count { |testcase| testcase[:error] }
      suite[:skipped] = suite[:cases].count { |testcase| testcase[:skipped] }
      all_test_suites << suite
    end
  end
end

# collect empty test suite instances into combined error messages

empty_test_suite_info = {
  # Empty test suites for which at least one test completed in another test result entry.
  # This seems to happen sometimes when a test crashes and unrelated test suites show additional empty results alongside their normal test results.
  repeated: {label: 'with some', count: 0, messages: []},
  # Empty test suites for which no tests completed at all.
  only_empty: {label: 'without any', count: 0, messages: []}
}

empty_test_suite_counts.each do |name, count|
  if count > 0
    # Get the sum of all completed tests with the same test suites name
    completed_count = all_test_suites.sum { |suite| (suite[:name] == name) ? suite[:count] : 0 }
    message = "#{name}: #{count} empty test suite results, #{completed_count} completed test results"
    if completed_count > 0
      empty_test_suite_info[:repeated][:messages] << message
      empty_test_suite_info[:repeated][:count] += count
    else
      empty_test_suite_info[:only_empty][:messages] << message
      empty_test_suite_info[:only_empty][:count] += count
    end
  end
end
empty_test_suite_info.values.each do |info|
  unless info[:messages].empty?
    all_test_suites << {
      name: "#{info[:count]} empty test suite results #{info[:label]} associated completed tests",
      error: "XCode test result output includes some empty test suites (may indicate an error occurred while running tests):\n#{info[:messages].join("\n")}"
    }
  end
end

# format the data

puts '<?xml version="1.0" encoding="UTF-8"?>'
puts "<testsuites>"
all_test_suites.each do |suite|
  if suite[:error]
    puts "<testsuite name=#{suite[:name].encode xml: :attr} errors='1'>"
    puts "<error>#{suite[:error].encode xml: :text}</error>"
    puts '</testsuite>'
  else
    puts "<testsuite name=#{suite[:name].encode xml: :attr} tests='#{suite[:count]}' failures='#{suite[:failures]}' errors='#{suite[:errors]}' skipped='#{suite[:skipped]}'>"

    suite[:cases].each do |testcase|
      print "<testcase classname=#{suite[:name].encode xml: :attr} name=#{testcase[:name].encode xml: :attr} time=\"#{testcase[:time]}\""
      if testcase[:failure]
        puts '>'
        puts "<failure message=#{testcase[:failure].encode xml: :attr}>#{testcase[:failure_location].encode xml: :text}</failure>"
        puts '</testcase>'
      elsif testcase[:error]
        puts '>'
        puts "<error>#{testcase[:error].encode xml: :text}</error>"
        puts '</testcase>'
      elsif testcase[:skipped]
        puts '>'
        puts "<skipped message=#{testcase[:skipped].encode xml: :attr}/>"
        puts '</testcase>'
      else
        puts '/>'
      end
    end

    puts '</testsuite>'
  end
end
puts '</testsuites>'
