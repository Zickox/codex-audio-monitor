#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'xcodeproj'

ROOT = Pathname.new(__dir__).join('..').realpath
PROJECT_PATH = ROOT.join('CodexAudioMonitor.xcodeproj')

APP_TARGET_NAME = 'CodexAudioMonitorApp'
APP_PRODUCT_NAME = 'CodexAudioMonitor'
TEST_TARGET_NAME = 'CodexAudioMonitorTests'

APP_GLOB_PATTERNS = [
  'Sources/CodexAudioMonitor/App/**/*.swift',
  'Sources/CodexAudioMonitor/Infrastructure/**/*.swift',
  'Sources/CodexAudioMonitor/UI/**/*.swift',
  'Sources/CodexAudioMonitor/Core/Audio/**/*.swift',
  'Sources/CodexAudioMonitor/Core/Codex/**/*.swift'
].freeze

TEST_GLOB_PATTERNS = [
  'Tests/CodexAudioMonitorTests/**/*.swift'
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

app_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = APP_PRODUCT_NAME
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.zickox.codexaudiomonitor'
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '15.0'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['INFOPLIST_FILE'] = 'Sources/CodexAudioMonitor/App/Info.plist'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
  config.build_settings['MARKETING_VERSION'] = '0.2.0'
  config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'YES'
end

add_sources(project, app_target, collect_files(APP_GLOB_PATTERNS))

test_target = project.new_target(:unit_test_bundle, TEST_TARGET_NAME, :osx, '15.0')
test_target.add_dependency(app_target)

test_target.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '15.0'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.zickox.codexaudiomonitor.tests'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/CodexAudioMonitor.app/Contents/MacOS/CodexAudioMonitor'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end

add_sources(project, test_target, collect_files(TEST_GLOB_PATTERNS))

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app_target, test_target)
scheme.set_launch_target(app_target)
test_env = scheme.test_action.environment_variables
test_env.assign_variable(
  :key => 'CODEX_LIVE_TESTS',
  :value => '$(CODEX_LIVE_TESTS)',
  :enabled => true
)
test_env.assign_variable(
  :key => 'CODEX_LIVE_TESTS_REQUIRED',
  :value => '$(CODEX_LIVE_TESTS_REQUIRED)',
  :enabled => true
)
scheme.test_action.environment_variables = test_env
scheme.save_as(PROJECT_PATH, APP_TARGET_NAME, true)

project.save
puts "Generated #{PROJECT_PATH}"
