require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "FaceLiveness"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/vishalsgithub/face-liveness-react-native.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm}", "cpp/core/**/*.{h,cpp}"
  s.private_header_files = "ios/**/*.h", "cpp/**/*.h"

  # Prebuilt ncnn + OpenMP (static-library xcframeworks) and the bundled models.
  s.vendored_frameworks = "ios/Frameworks/ncnn.xcframework", "ios/Frameworks/openmp.xcframework"
  s.resource_bundles = {
    "FaceAntiSpoofingModels" => ["models/face_liveness/detection", "models/face_liveness/live"]
  }
  s.frameworks = "AVFoundation", "CoreMedia", "CoreVideo", "QuartzCore", "UIKit"
  s.library = "c++"

  s.pod_target_xcconfig = {
    # Only CPU feature flags differ between the ncnn slices, so the device headers serve both.
    "HEADER_SEARCH_PATHS" => "\"$(PODS_TARGET_SRCROOT)/cpp/core/include\" " \
                             "\"$(PODS_TARGET_SRCROOT)/ios/Frameworks/ncnn.xcframework/ios-arm64/Headers\""
  }

  install_modules_dependencies(s)
end
