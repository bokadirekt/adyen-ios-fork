#!/usr/bin/env ruby

require 'xcodeproj'

def your_changes(path, key, value)
  puts path
  begin
    project = Xcodeproj::Project.open(path)
    project.targets.each do |target|
      if target.name.end_with?('Tests') || target.name.end_with?('TestApp') || target.name.end_with?('UITests')
        puts target.name
      else
        target.build_configurations.each do |config|
          config.build_settings[key] = value
        end
      end
    end
    project.save()
  rescue StandardError => msg
    puts "#{msg} A"
  end
end

def process_dir(path, key, value)
  main_dir = Dir.new(path)
  children = main_dir.children
  for name in children
    if name.end_with?('.xcodeproj')
      your_changes("#{main_dir.path}/#{name}", key, value)
    else
      if File.directory?("#{main_dir.path}/#{name}")
        process_dir("#{main_dir.path}/#{name}", key, value)
      end
    end
  end
end

process_dir('Pods', 'DEVELOPMENT_TEAM', 'B2NYSS5932')