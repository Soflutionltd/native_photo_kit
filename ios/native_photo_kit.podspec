Pod::Spec.new do |s|
  s.name             = 'native_photo_kit'
  s.version          = '0.1.0'
  s.summary          = 'Fast native photo pipeline for Flutter.'
  s.description      = <<-DESC
JPEG encoding from raw RGBA, EXIF-aware decoding at target size, cover crop and
blurred-background feed format, on ImageIO and Core Image.
                       DESC
  s.homepage         = 'https://github.com/Soflutionltd/native_photo_kit'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'Soflution Ltd'
  s.source           = { :path => '.' }
  s.source_files = 'native_photo_kit/Sources/native_photo_kit/**/*.swift'
  s.resource_bundles = { 'native_photo_kit_privacy' => ['native_photo_kit/Sources/native_photo_kit/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
