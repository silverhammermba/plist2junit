#!/usr/bin/env ruby
require 'pathname'

def parse_dict file
  dictionary = {}
  loop do
    line = file.gets.strip
    case line
    when /^<\/dict>$/
      return dictionary
    when /^<key>(.*)<\/key>$/
      key = $1
      dictionary[key] = parse_value file
    else
      raise "expected key or end of dict: #{line}"
    end
  end
end

def parse_array file
  array = []
  loop do
    line = file.gets.strip
    case line
    when /^<\/array>$/
      return array
    else
      array << parse_value_line(file, line)
    end
  end
end

def parse_value_line file, line
  return case line
  when /^<dict>$/
    parse_dict file
  when /^<array>$/
    parse_array file
  when /^<string>(.*)<\/string>$/
    $1
  when /^<real>(.*)<\/real>$/
    Float($1)
  when /^<integer>(.*)<\/integer>$/
    Integer($1, 10)
  when /^<true\/>$/
    true
  when /^<false\/>$/
    false
  when /^<array\/>$/
    []
  else
    raise "unknown type: #{line}"
  end
end

def parse_value file
  parse_value_line file, file.gets.strip
end

plist = nil

File.open(ARGV[0]) do |file|
  loop do
    break if file.gets =~ /^<plist/
  end
  plist = parse_value file
end

# transform data
root = Pathname.new Dir.pwd
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
          filename = Pathname.new failure['FileName']
          result[:failure_location] = "#{filename.relative_path_from root}:#{failure['LineNumber']}"
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
