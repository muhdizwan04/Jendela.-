require 'xcodeproj'
require 'fileutils'

ROOT      = File.expand_path('..', __dir__)
TEAM      = 'FRWW9Y9Y94'
APP_ID    = 'com.widgetmac.desktop'
EXT_ID    = "#{APP_ID}.widgets"
DEPLOY    = '15.0'

path = File.join(ROOT, 'WidgetMac.xcodeproj')
FileUtils.rm_rf(path)
project = Xcodeproj::Project.new(path)

common = {
  'PRODUCT_NAME'                        => '$(TARGET_NAME)',
  'MACOSX_DEPLOYMENT_TARGET'            => DEPLOY,
  'SDKROOT'                             => 'macosx',
  'SWIFT_VERSION'                       => '5.0',
  'DEVELOPMENT_TEAM'                    => TEAM,
  'CODE_SIGN_STYLE'                     => 'Automatic',
  'ALWAYS_SEARCH_USER_PATHS'            => 'NO',
  'CLANG_ENABLE_OBJC_ARC'               => 'YES',
  'ENABLE_HARDENED_RUNTIME'             => 'YES',
  'SWIFT_EMIT_LOC_STRINGS'              => 'YES',
  'GENERATE_INFOPLIST_FILE'             => 'NO',
  'COMBINE_HIDPI_IMAGES'                => 'YES'
}

project.build_configurations.each do |config|
  common.each { |k, v| config.build_settings[k] = v }
  config.build_settings['ONLY_ACTIVE_ARCH'] = config.name == 'Debug' ? 'YES' : 'NO'
  config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = config.name == 'Debug' ? '-Onone' : '-O'
  config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG' if config.name == 'Debug'
end

# ---------------- groups ----------------
app_group = project.new_group('WidgetMac',        'Sources/WidgetMac')
ext_group = project.new_group('WidgetMacWidgets', 'WidgetMacWidgets')
support   = project.new_group('Support',          'Support')

# `WidgetSnapshot.swift` lives with the app but is compiled into both
# processes, so the widget can decode what the app writes.
SHARED = 'Sources/WidgetMac/WidgetSnapshot.swift'
app_sources = Dir[File.join(ROOT, 'Sources/WidgetMac/*.swift')].sort
ext_sources = Dir[File.join(ROOT, 'WidgetMacWidgets/*.swift')].sort

# ---------------- app target ----------------
app = project.new_target(:application, 'WidgetMac', :osx, DEPLOY)
app.build_configurations.each do |c|
  c.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => APP_ID,
    'INFOPLIST_FILE'            => 'Support/WidgetMac-Info.plist',
    'MARKETING_VERSION'         => '0.2.0',
    'CURRENT_PROJECT_VERSION'   => '2',
    'CODE_SIGN_ENTITLEMENTS'    => 'Support/WidgetMac.entitlements',
    'ENABLE_APP_SANDBOX'        => 'NO'
  )
end
shared_ref = nil
app_sources.each do |f|
  ref = app_group.new_file(f)
  shared_ref = ref if f.end_with?('WidgetSnapshot.swift')
  app.add_file_references([ref])
end

# ---------------- widget extension target ----------------
ext = project.new_target(:app_extension, 'WidgetMacWidgets', :osx, DEPLOY)
ext.build_configurations.each do |c|
  c.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => EXT_ID,
    'INFOPLIST_FILE'            => 'WidgetMacWidgets/Info.plist',
    'MARKETING_VERSION'         => '0.2.0',
    'CURRENT_PROJECT_VERSION'   => '2',
    'CODE_SIGN_ENTITLEMENTS'    => 'Support/WidgetMacWidgets.entitlements',
    'ENABLE_APP_SANDBOX'        => 'YES',
    'SKIP_INSTALL'              => 'YES'
  )
end
ext_sources.each { |f| ext.add_file_references([ext_group.new_file(f)]) }
ext.add_file_references([shared_ref]) if shared_ref

ext.add_system_framework('WidgetKit')
ext.add_system_framework('SwiftUI')

# ---------------- embed the appex ----------------
app.add_dependency(ext)
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.add_file_reference(ext.product_reference, true)

# The icon is a generated .icns (see Support/make_icon.sh), copied in as a
# resource and named by CFBundleIconFile.
icon = support.new_file(File.join(ROOT, 'Support/AppIcon.icns'))
app.add_resources([icon])

support.new_file(File.join(ROOT, 'Support/WidgetMac-Info.plist'))
support.new_file(File.join(ROOT, 'WidgetMacWidgets/Info.plist'))

project.save
puts "generated #{path}"
puts "  app target sources:    #{app_sources.size}"
puts "  widget target sources: #{ext_sources.size + 1}"
