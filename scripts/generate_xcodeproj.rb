#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'xcodeproj'

ROOT = Pathname.new(__dir__).join('..').realpath
PROJECT_PATH = ROOT.join('CodexAudioMonitor.xcodeproj')

APP_TARGET_NAME = 'CodexAudioMonitorApp'
APP_PRODUCT_NAME = 'CodexAudioMonitor'
BRIDGE_TARGET_NAME = 'CodexAudioBridge'

APP_GLOB_PATTERNS = [
  'Sources/CodexAudioMonitor/App/**/*.swift',
  'Sources/CodexAudioMonitor/Infrastructure/**/*.swift',
  'Sources/CodexAudioMonitor/UI/**/*.swift',
  'Sources/CodexAudioMonitor/Core/Audio/**/*.swift',
  'Sources/CodexAudioMonitor/Core/Codex/**/*.swift',
  'Sources/CodexAudioMonitor/Core/Bridge/**/*.swift'
].freeze

BRIDGE_GLOB_PATTERNS = [
  'Sources/CodexAudioMonitor/Core/Audio/**/*.swift',
  'Sources/CodexAudioMonitor/Core/Bridge/**/*.swift',
  'Sources/CodexAudioBridge/**/*.swift'
].freeze

def collect_files(patterns)
  patterns.flat_map { |pattern| Dir.glob(pattern) }
          .select { |path| File.file?(path) }
          .uniq
          .sort
end

def ensure_group(root_group, directory)
  return root_group if directory.nil? || directory == '.'

  current = root_group
  directory.split('/').each do |component|
    next if component.nil? || component.empty?

    next_group = current.groups.find { |group| group.display_name == component || group.path == component }
    current = next_group || current.new_group(component, component)
  end

  current
end

def add_sources(project, target, relative_paths)
  file_refs = {}

  relative_paths.each do |relative_path|
    directory = File.dirname(relative_path)
    basename = File.basename(relative_path)
    group = ensure_group(project.main_group, directory)

    ref = file_refs[relative_path]
    unless ref
      ref = group.files.find { |file| file.path == basename }
      ref ||= group.new_file(basename)
      file_refs[relative_path] = ref
    end

    already_added = target.source_build_phase.files_references.any? { |existing| existing.path == ref.path && existing.real_path.to_s == ref.real_path.to_s }
    target.source_build_phase.add_file_reference(ref, true) unless already_added
  end
end

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH.to_s)
project.root_object.attributes['LastSwiftUpdateCheck'] = '2600'
project.root_object.attributes['LastUpgradeCheck'] = '2600'

app_target = project.new_target(:application, APP_TARGET_NAME, :osx, '15.0')
bridge_target = project.new_target(:command_line_tool, BRIDGE_TARGET_NAME, :osx, '15.0')

app_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = APP_PRODUCT_NAME
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.zickox.codexaudiomonitor'
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '15.0'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['INFOPLIST_KEY_LSUIElement'] = 'YES'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
  config.build_settings['MARKETING_VERSION'] = '0.2.0'
  config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'YES'
end

bridge_target.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '15.0'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
  config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'YES'
end

add_sources(project, app_target, collect_files(APP_GLOB_PATTERNS))
add_sources(project, bridge_target, collect_files(BRIDGE_GLOB_PATTERNS))

project.save
puts "Generated #{PROJECT_PATH}"
