#!/usr/bin/env ruby
require 'fileutils'
require 'json'
require 'tmpdir'

if ARGV.length != 2
  warn "usage: #$0 INPUT.xcresult OUTPUT.xccovarchive"
  exit 1
end

xcresult = ARGV[0]
xccovarchive = ARGV[1]

Dir.mktmpdir do |tmp_dir|
  # export coverage archive and report
  cmd = %w{xcrun xcresulttool export coverage --type directory --path} << xcresult << '--output-path' << tmp_dir
  system *cmd, out: File::NULL
  # find archive
  archives = Dir.glob(File.join(tmp_dir, '*_CoverageArchive'))
  raise "no coverage archive in export" if archives.empty?
  raise "multiple coverage archives in export" if archives.length > 1
  # move to desired output path
  FileUtils.mv(archives[0], xccovarchive)
end
