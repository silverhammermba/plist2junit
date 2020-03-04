require 'xcodeproj'
require 'pathname'
require 'set'

$errors = false

def warning text
  puts "warning: #{text}"
end

def error text
  $errors = true
  puts "error: #{text}"
end

# get the topmost dir that a build file is in
class Xcodeproj::Project::Object::PBXBuildFile
  def top_dir
    Pathname(file_ref.full_path).each_filename.first
  end

  # only makes sense for a header
  def visibility
    (settings || {}).dig("ATTRIBUTES", 0) || 'Project'
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

def headers_with_likely_wrong_membership project
  project.targets.each do |target|
    next unless target.is_a? Xcodeproj::Project::Object::PBXNativeTarget

    headers = target.headers_build_phase.files

    top_dirs = Hash.new(0)

    headers.each do |header|
      top_dirs[header.top_dir] += 1
    end

    sorted_dirs = top_dirs.sort_by(&:last)[0..-1].map(&:first)
    other_dirs = Set.new sorted_dirs[0...-1]

    unless other_dirs.empty?
      headers.each do |header|
        dir = header.top_dir
        if other_dirs.include? dir
          error "#{target.name} includes non-framework header `#{header.file_ref.full_path}'"
        end
      end
    end
  end
end

def importing_outside_framework project
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
      File.open(header.file_ref.full_path) do |file|
        file.each_line do |line|
          next unless line =~ /^#import "([^"]*)"/

          import = $1
          headers = headers_by_name[import]
          if headers
            targets = headers.map(&:targets).reduce(:+)
            if targets.include? target
              # OK
            elsif targets.any? { |t| t.sdkroot != target.sdkroot } # some imports might be missing because they are for a different platform (user needs to manually check preprocessor guards)
              warning "`#{header.file_ref.full_path}' possibly imports non-framework header #{import} (member of #{targets.map(&:name).join(', ')}, not #{target.name})"
            else
              error "`#{header.file_ref.full_path}' imports non-framework header #{import} (member of #{targets.map(&:name).join(', ')})"
            end

            if header.visibility == 'Public'
              nonpublic = headers.select { |h| h.visibility != 'Public' }
              if nonpublic.length == headers.length
                error "Public header `#{header.file_ref.full_path}' imports non-public header #{import} (appears in #{targets.map(&:name).join(', ')})"
              elsif nonpublic.length > 0
                warning "Public header `#{header.file_ref.full_path}' possibly imports non-public header #{import} (appears in #{targets.map(&:name).join(', ')})"
              end
            end
          else
            error "`#{header.file_ref.full_path}' imports missing file #{import}"
          end
        end
      end
    end

    # open all m files to check if they are importing something outside their framework
    target.source_build_phase.files.each do |mfile|
      next unless mfile.file_ref.is_a? Xcodeproj::Project::Object::PBXFileReference
      next unless File.extname(mfile.file_ref.full_path) == '.m'

      File.open(mfile.file_ref.full_path) do |file|
        file.each_line do |line|
          next unless line =~ /^#import "([^"]*)"/

          import = $1
          headers = headers_by_name[import]

          if headers
            targets = headers.map(&:targets).reduce(:+)
            if !targets.include? target
              error "`#{mfile.file_ref.full_path}' imports non-target header #{import} (member of #{targets.map(&:name).join(', ')} not #{target.name})"
            end
          end
        end
      end
    end
  end
end

project = Xcodeproj::Project.open(ARGV[0])

#headers_with_likely_wrong_membership project
importing_outside_framework project

if $errors
  exit 1
end

# finished
# 1. header has membership in wrong target (guess from path name?)
# 2. header imports non-umbrella framework outside target (show correct umbrella header)
# 3. public header imports non-public header
# 4. .m file imports header from other app/framework

# FIXME: problems to identify
# 4. app header imports header from other app/framework (show correct umbrella header)
