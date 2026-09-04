<div align="center">
<!--   <img alt="fsplayer" src="./primary-wide.png"> -->
  <h1>IJKPlayer</h1>
  <img src="https://github.com/debugly/fsplayer/actions/workflows/apple.yml/badge.svg">
  <img src="https://img.shields.io/badge/Platform-%20iOS%20macOS%20tvOS%20-blue.svg">
</div>

### 编译脚本

- [x] IJKPlayerKit自编译使用说明.md

  脚本使用说明

- [x] BuildIJKPlayerKit.sh

  远程下载并基于FSPlayer进行二次自定义编译，最终生成IJKPlayerKit.xcframework



### 下载脚本

- [x] IJKPlayerKit.sh

  从 https://github.com/aiguanren/IJKPlayerKit/releases/download/#[{ijk.version}/IJKPlayerKit.zip]() 下载已经编译好了的{ijk.version}版本的IJKPlayerKit.xcframework



### IJKPlayerKit

- [x] 原始工程

  - [x] 预编译依赖库

    每次使用BuildIJKPlayerKit.sh编译成功后自动生成，值得注意的是每次生成后需要用新生成的预编译依赖库替换现有的预编译依赖库

  - [x] FSPlayer

    每次使用BuildIJKPlayerKit.sh编译成功后自动生成，值得注意的是每次生成后需要用新生成的FSPlayer替换现有的FSPlayer

  - [x] Xcode工程

    每次使用BuildIJKPlayerKit.sh编译成功后自动生成，值得注意的是每次生成后需要用新生成的Xcode工程替换现有的Xcode工程

- [x] Frameworks

  - [x] IJKPlayerKit.xcframework

    每次使用BuildIJKPlayerKit.sh编译成功后自动生成，值得注意的是每次生成后需要用新生成的IJKPlayerKit.xcframework替换现有的IJKPlayerKit.xcframework

  - [x] 构建信息.txt

    每次使用BuildIJKPlayerKit.sh编译成功后自动生成，值得注意的是每次生成后需要用新生成的构建信息.txt替换现有的构建信息.txt

  - [x] PrivacyInfo.xcprivacy

    IJKPlayerKit.podspec所需要的隐私清单信息，视情况可编辑修改

  - [x] License.md

    IJKPlayerKit.podspec所需要的开源协议

  - [x] README.md

    IJKPlayerKit.podspec所需要的README文件，视情况可编辑修改



### Podspec

- [x] IJKPlayerKit.podspec

  目前正在使用的基于FSPlayer编译而来的IJKPlayerKit.xcframework的发布文件，支持真机与arm64、X86_64模拟器

- [x] IJKPlayerKitFull.podspec

  自己基于IJKPlayer修改后编译而来的IJKMediaPlayer.xcframework的发布文件，支持真机与X86_64模拟器

- [x] IJKPlayerKitLite.podspec

  自己基于IJKPlayer修改后编译而来的IJKMediaPlayer.xcframework的发布文件，仅支持真机



### 发布Release包

- [x] 1、将IJKPlayer提交至https://github.com/aiguanren/IJKPlayerKit.git

- [x] 2、将IJKPlayerKit下面的Frameworks压缩成.zip包

- [x] 3、打开https://github.com/aiguanren/IJKPlayerKit 然后点击 [Create a new release](https://github.com/aiguanren/IJKPlayerKit/releases/new)

- [x] 4、创建{ijk.version}对应版本的Tag

- [x] 5、Release title 写 IJKPlayerKit，Release notes 写 基于IJKPlayer编译封装的直播播放器(也可作为视屏播放器)，支持RTMP/RTMPS/RTMPT/RTMPE/RTSP/HLS/HTTP(S)-FLV/KMP 等直播协议与MP4、FLV等格式， 支持录屏功能

- [x] 6、点击 Attach binaries by dropping them here or selecting them. ，然后将步骤2的压缩包上传并等待上传成功

- [x] 7、Release label 这里选择 Pre-release

- [x] 8、点击 Publish release 发布

- [x] 9、利用 IJKPlayerKit.podspec 发布至Cocoapods

