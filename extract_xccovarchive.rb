#!/usr/bin/env ruby
require 'json'
require 'shellwords'

# extract xccovarchive from xcresult so that xccov-to-sonarqube-generic.sh doesn't take a million years to process it

if ARGV.length != 2
  warn "usage: #$0 INPUT.xcresult OUTPUT.xccovarchive"
  exit 1
end

xcresult = ARGV[0]
xccovarchive = ARGV[1]

# get test results from xcresults
results = nil
IO.popen(%w{xcrun xcresulttool get --format json --path} << xcresult) do |result_summary|
  results = JSON.load result_summary
end

# get coverage archive id
archive_id = results['actions']['_values'][0]['actionResult']['coverage']['archiveRef']['id']['_value']

# export the xccovarchive directory
exec "xcrun xcresulttool export --type directory --path #{xcresult.shellescape} --id #{archive_id.shellescape} --output-path #{xccovarchive.shellescape}"
