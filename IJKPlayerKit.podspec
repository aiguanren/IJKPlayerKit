Pod::Spec.new do |ijk|

  ijk.name         = "IJKPlayerKit"
  ijk.version      = "1.0.2"
  ijk.summary      = "基于IJKPlayer编译封装的直播播放器(也可作为视屏播放器)，支持RTMP/RTMPS/RTMPT/RTMPE/RTSP/HLS/HTTP(S)-FLV/KMP 等直播协议与MP4、FLV等格式， 支持录屏功能"
  ijk.description  = <<-DESC
                          集成注意事项：
                          使用cocoapods官方源
                          source 'https://github.com/CocoaPods/Specs.git'
                          pod 'IJKPlayerKit'
                   DESC

  ijk.author       = { "官人" => "aiguanren@icloud.com" }
  ijk.homepage     = "https://github.com/aiguanren/WYBasisKit-swift"
  ijk.license      = { :type => "MIT", :file => "IJKPlayerKit/License.md" }
  ijk.resource_bundles = {"IJKPlayerKit" => [
    "IJKPlayerKit/PrivacyInfo.xcprivacy"
  ]}

  # iOS 最低版本
  ijk.ios.deployment_target = "11.0"
  # tvOS 最低版本
  ijk.tvos.deployment_target = "12.0"
  # macOS 最低版本      
  ijk.osx.deployment_target = "10.11"        

  ijk.source       = { :http => "https://github.com/aiguanren/IJKPlayerKit/releases/download/1.0.0/IJKPlayerKit.zip" }
  ijk.swift_versions = "5.0"
  ijk.requires_arc = true
  ijk.static_framework = true
  ijk.vendored_frameworks = "IJKPlayerKit/fs/FSPlayer.xcframework"

  # 共有的系统库
  ijk.libraries = "c++", "z", "bz2", "iconv", "xml2", "lzma"

  # 共有的框架
  ijk.frameworks = "AVFoundation", "AudioToolbox", "CoreMedia", "CoreVideo", "VideoToolbox", "Metal"

  # iOS 专属框架
  ijk.ios.frameworks = "UIKit", "OpenGLES"

  # tvOS 专属框架
  ijk.tvos.frameworks = "UIKit", "OpenGLES"

  # macOS 专属框架
  ijk.osx.frameworks = "Cocoa", "AudioUnit", "OpenGL", "GLKit", "CoreImage"

  # 设置编译环境
  ijk.pod_target_xcconfig = {
    "GCC_PREPROCESSOR_DEFINITIONS" => "$(inherited) WYBasisKit_Supports_MediaPlayer_FS=1",  # 用于 Objective-C 的 #if 判断
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS" => "$(inherited) WYBasisKit_Supports_MediaPlayer_FS", # 用于 Swift 的 #if 判断（注意不带 =1，就是直接使用宏名即可）
  }
  
end