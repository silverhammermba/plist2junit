#!/usr/bin/env ruby
require 'json'
require 'time'

def get_object id=nil
  args = %w{xcrun xcresulttool get --format json --path} << $xcresult
  if id
    args << '--id' << id
  end
  IO.popen(args) do |object|
    return dict2obj(JSON.load object)
  end
end

module XCResult
  class Reference
    def deref
      get_object @id
    end
  end
end

# create a new class in the XCResult module using a dictionary
def dynamicobj dict
  klass = nil
  typename = dict['_type']['_name']
  begin
    klass = XCResult.const_get(typename)
  rescue NameError
    warn "creating new type: #{typename}"
    klass = Class.new
    XCResult.const_set(typename, klass)

    klass.define_method :method_missing do |*args|
      nil
    end
  end

  obj = klass.new

  dict.each do |key, val|
    next if key.start_with? ?_
    obj.instance_variable_set "@#{key}", dict2obj(val)
    unless obj.methods.include? key.to_sym
      klass.define_method key do
        instance_variable_get "@#{key}"
      end
    end
  end

  obj
end

def dict2obj dict
  type = dict['_type']
  case type['_name']
  when 'Array'
    dict['_values'].map { |d| dict2obj d }
  when 'Bool'
    dict['_value'] == 'true'
  when 'Date'
    Time.parse dict['_value']
  when 'Double'
    Float(dict['_value'])
  when 'Int'
    Integer(dict['_value'])
  when 'String'
    dict['_value']
  else
    dynamicobj dict
  end
end

if ARGV.length != 1
  warn "usage: #$0 Foobar.xcresult"
  exit 1
end

$xcresult = ARGV[0]

# get test result id from xcresults
results = get_object

# load test results by id
tests = results.actions[0].actionResult.testsRef.deref

# transform to a dictionary that mimics the output structure

test_suites = []

tests.summaries[0].testableSummaries.each do |target|
  target_name = target.targetName

  # if the test target failed to launch at all, get first failure message
  unless target.tests
    failure_summary = target.failureSummaries[0]
    test_suites << {name: target_name, error: failure_summary.message}
    next
  end

  test_classes = target.tests

  # else process the test classes in each target
  # first two levels are just summaries, so skip those
  test_classes[0].subtests[0].subtests.each do |test_class|
    suite = {name: "#{target_name}.#{test_class.name}", cases: []}

    # process the tests in each test class
    test_class.subtests.each do |test|
      duration = test.duration || 0

      testcase = {name: test.name, time: duration}

      if test.testStatus == 'Failure'
        failures = test.summaryRef.deref.failureSummaries

        message = failures.map { |failure| failure.message }.join("\n")
        location = failures.select { |failure| failure.fileName != '<unknown>' }.first

        if location
          testcase[:failure] = message
          testcase[:failure_location] = "#{location.fileName}:#{location.lineNumber}"
        else
          testcase[:error] = message
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
