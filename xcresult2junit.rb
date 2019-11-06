#!/usr/bin/env ruby
require 'json'

if ARGV.length != 1
  warn "usage: #$0 [PATH_TO_RESULT_BUNDLE].xcresult"
  exit 1
end

module Key
  ACTION_RESULT = 'actionResult'
  ACTIONS = 'actions'
  DURATION = 'duration'
  FAILURE_SUMMARIES = 'failureSummaries'
  FILE_NAME = 'fileName'
  ID = 'id'
  LINE_NUMBER = 'lineNumber'
  MESSAGE = 'message'
  NAME = 'name'
  SUBTESTS = 'subtests'
  SUMMARY_REF = 'summaryRef'
  SUMMARIES = 'summaries'
  TARGET_NAME = 'targetName'
  TESTABLE_SUMMARIES = 'testableSummaries'
  TESTS = 'tests'
  TESTS_REF = 'testsRef'
  TEST_STATUS = 'testStatus'
  VALUE = '_value'
  VALUES = '_values'
end

$xcresult = ARGV[0]
$xcresulttool_cmd = %w{xcrun xcresulttool get --format json --path} << $xcresult

def get_object id
  result = nil
  IO.popen($xcresulttool_cmd << '--id' << id) do |object|
    result = JSON.load object
  end
  result
end

# get test result id from xcresults
results = nil
IO.popen($xcresulttool_cmd) do |result_summary|
  results = JSON.load result_summary
end

# load test results by id
testsRefId = nil
results[Key::ACTIONS][Key::VALUES].each { |value|
  testsRef = value[Key::ACTION_RESULT][Key::TESTS_REF]
  testsRefId = testsRef[Key::ID][Key::VALUE] unless testsRef.nil?
}

tests = get_object testsRefId

# transform to a dictionary that mimics the output structure

test_suites = []

tests[Key::SUMMARIES][Key::VALUES][0][Key::TESTABLE_SUMMARIES][Key::VALUES].each do |target|
  target_name = target[Key::TARGET_NAME][Key::VALUE]

  # if the test target failed to launch at all, get first failure message
  unless target[Key::TESTS]
    failure_summary = target[Key::FAILURE_SUMMARIES][Key::VALUES][0]
    test_suites << {name: target_name, error: failure_summary[Key::MESSAGE][Key::VALUE]}
    next
  end

  test_classes = target[Key::TESTS][Key::VALUES]

  # else process the test classes in each target
  # first two levels are just summaries, so skip those
  test_classes[0][Key::SUBTESTS][Key::VALUES][0][Key::SUBTESTS][Key::VALUES].each do |test_class|
    suite = {name: "#{target_name}.#{test_class[Key::NAME][Key::VALUE]}", cases: []}

    # process the tests in each test class
    test_class[Key::SUBTESTS][Key::VALUES].each do |test|
      duration = 0
      if test[Key::DURATION]
        duration = test[Key::DURATION][Key::VALUE]
      end

      testcase = {name: test[Key::NAME][Key::VALUE], time: duration}

      if test[Key::TEST_STATUS][Key::VALUE] == 'Failure'
        failure = get_object(test[Key::SUMMARY_REF][Key::ID][Key::VALUE])[Key::FAILURE_SUMMARIES][Key::VALUES][0]

        filename = failure[Key::FILE_NAME][Key::VALUE]
        message = failure[Key::MESSAGE][Key::VALUE]

        if filename == '<unknown>'
          testcase[:error] = message
        else
          testcase[:failure] = message
          testcase[:failure_location] = "#{filename}:#{failure[Key::LINE_NUMBER][Key::VALUE]}"
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

puts '<?xml version="1.0" encoding="UTF-8"?>'
puts '<testsuites>'
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
