require 'xcodeproj'
require 'set'
require 'tempfile'
require 'fileutils'

# get the topmost dir that a build file is in
class Xcodeproj::Project::Object::PBXBuildFile
  def top_dir
    Pathname(file_ref.full_path).each_filename.first
  end

  def targets
    @targets || Set.new
  end

  def add_target target
    @targets ||= Set.new
    @targets << target
  end
end

class Xcodeproj::Project::Object::PBXNativeTarget
  def sdkroot
    build_configurations.first.build_settings['SDKROOT']
  end
end

def replace_imports path, headers_by_name
  added = Set.new

  edit_file(path) do |line|
    if line =~ /^#import "([^"]*)"/
      import = $1

      headers = headers_by_name[import]

      next unless headers

      new_import = yield headers

      if new_import
        if added.include? new_import.downcase
          next ""
        else
          added << new_import.downcase
          next "#import <#{new_import}>"
        end
      else
        next
      end
    elsif line =~ /^#import <([^>]*)>/
      import = $1
      if added.include? import.downcase
        next ""
      else
        added << import.downcase
        next
      end
    else
      next
    end
  end
end

def edit_file path
  new_file = Tempfile.new('replacer')

  begin
    changed = false
    File.open(path) do |file|
      file.each_line do |line|
        replacement = yield(line)

        if replacement
          changed = true
          # empty string means remove the line
          if replacement == ""
            next
          end
        else
          replacement = line
        end

        if line.end_with? ?\n
          new_file.puts replacement
        else
          new_file.print replacement
        end
      end
    end
    new_file.close
    if changed
      FileUtils.cp(new_file.path, path)
    end
  ensure
    new_file.close
    new_file.unlink
  end
end

def fix_imports project
  headers_by_name = {}

  # build up a map from header names to all headers with that name, also hook up each header to its targets
  project.targets.each do |target|
    next unless target.is_a? Xcodeproj::Project::Object::PBXNativeTarget
    headers = target.headers_build_phase.files

    headers.each do |header|
      header.add_target target
      basename = File.basename(header.file_ref.full_path)
      headers_by_name[basename] ||= []
      headers_by_name[basename] << header
    end
  end

  # open all headers to check if they are importing something outside their framework
  project.targets.each do |target|
    next unless target.is_a? Xcodeproj::Project::Object::PBXNativeTarget

    target.headers_build_phase.files.each do |header|
      replace_imports(header.file_ref.full_path, headers_by_name) do |headers|
        targets = headers.map(&:targets).reduce(:+)
        correct = targets.map(&:name).sort_by(&:length)[0]
        next if correct == header.top_dir

        new_import = "#{correct}/#{correct}.h"

        if targets.include? target
          # OK
        elsif targets.any? { |t| t.sdkroot != target.sdkroot } # some imports might be missing because they are for a different platform (user needs to manually check preprocessor guards)
          # if length == 1 we probably only have a different arch of the same framework
          if targets.length > 1
            next new_import
          end
        else
          next new_import
        end
        next
      end
    end

    # open all m files to check if they are importing something outside their framework
    target.source_build_phase.files.each do |mfile|
      next unless mfile.file_ref.is_a? Xcodeproj::Project::Object::PBXFileReference
      next unless File.extname(mfile.file_ref.full_path) == '.m'

      replace_imports(mfile.file_ref.full_path, headers_by_name) do |headers|
        targets = headers.map(&:targets).reduce(:+)
        correct = targets.map(&:name).sort_by(&:length)[0]
        next if correct == mfile.top_dir

        new_import = "#{correct}/#{correct}.h"

        if !targets.include? target
          next new_import
        end

        next
      end
    end
  end
end

project = Xcodeproj::Project.open(ARGV[0])
fix_imports project
