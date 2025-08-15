Pod::Spec.new do |ijk|

  ijk.name         = "IJKPlayerKitFull"
  ijk.version      = "1.0.0"
  ijk.summary      = "基于IJKPlayer编译封装的直播播放器(也可作为视屏播放器)，支持RTMP/RTMPS/RTMPT/RTMPE/RTSP/HLS/HTTP(S)-FLV/KMP 等直播协议与MP4、FLV等格式， 支持录屏功能"
  ijk.description  = <<-DESC
                          集成注意事项：
                          使用cocoapods官方源
                          source 'https://github.com/CocoaPods/Specs.git'
                          pod 'IJKPlayerKitFull'
                   DESC

  ijk.author       = { "官人" => "aiguanren@icloud.com" }
  ijk.homepage     = "https://github.com/aiguanren/WYBasisKit-swift"
  ijk.license      = { :type => "MIT", :file => "IJKPlayerKit/License.md" }
  ijk.resource_bundles = {"IJKPlayerKit" => [
    "IJKPlayerKit/PrivacyInfo.xcprivacy"
  ]}

  # iOS 最低版本
  ijk.ios.deployment_target = "13.0"      

  ijk.source       = { :http => "https://github.com/aiguanren/IJKPlayerKit/releases/download/1.0.0/IJKPlayerKit.zip" }
  ijk.swift_versions = "5.0"
  ijk.requires_arc = true
  ijk.static_framework = true
  ijk.vendored_frameworks = "IJKPlayerKit/arm64&x86_64/IJKMediaPlayer.xcframework"

  # 系统库
  ijk.libraries = "c++", "z", "bz2"

  # 系统框架
  ijk.frameworks = "UIKit", "AudioToolbox", "CoreGraphics", "AVFoundation", "CoreMedia", "CoreVideo", "MediaPlayer", "CoreServices", "Metal", "QuartzCore", "VideoToolbox"
  
end