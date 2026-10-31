#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint video_compress_next.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'video_compress_next'
  s.version          = '0.1.0'
  s.summary          = 'Drop-in replacement for video_compress: hardware video compression with AndroidX Media3 Transformer and AVFoundation, no FFmpeg.'
  s.description      = <<-DESC
Drop-in replacement for video_compress: hardware video compression with AndroidX Media3 Transformer and AVFoundation, no FFmpeg.
                       DESC
  s.homepage         = 'https://github.com/Zalexei/video_compress_next'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Alexei Zalogin' => '9594147+Zalexei@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.frameworks = 'AVFoundation', 'CoreMedia'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  s.resource_bundles = {'video_compress_next_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
