# FSPlayer 自定义命名编译脚本使用说明

配套脚本：`BuildIJKPlayerKit.sh`（**放在哪里、叫什么都行**，位置不影响任何路径，调用时写对路径即可）。工作区位置由 `-o` 参数决定（不传则运行中会询问，直接回车用默认 `~/Desktop`），工作区完整路径 = `<输出根目录>/<名称>/`。

---

## 一、它能做什么

基于开源库 [debugly/FSPlayer](https://github.com/debugly/fsplayer) 的源码，**一条命令编译出你自己命名的 framework / xcframework**：

- 自定义命名（决定 `.framework` 文件名和 Swift `import` 的模块名）
- 深度改名：类名/协议/枚举/通知名/文件名/注释的 `FS` 前缀统一改为自定义前缀（大小写保形，`FSPlayer→IJKPlayer`、`fs_hls→ijk_hls`），也可关闭只换框架名
- 交互问答式确认每一项配置（提示自带答案说明与 `[当前:值]` 展示），也支持 `-y` 非交互自动化
- 自选输出类型：`framework`（各平台散包）或 `xcframework`（多切片合包，推荐）
- 自选平台组合：iOS / tvOS / macOS 任意组合或全要
- 可选是否包含模拟器切片（模拟器含 arm64 + x86_64 双架构）
- FFmpeg 版本自动跟随 FSPlayer 仓库内置配置（如仓库当前内置 FFmpeg 8.1.2），无需手工指定
- 依赖库（FFmpeg/ass 等）使用上游官方**预编译包**直接下载，不需要本地编译 FFmpeg
- 每次 FSPlayer 更新后，重跑一遍脚本即可得到新版本的同名产物

## 二、快速开始

```bash
cd ~/Desktop/官人/IJKPlayerKit/构建脚本

# 最常用：IJKPlayerKit 命名的全平台 xcframework（真机+模拟器）
./BuildIJKPlayerKit.sh -y

# 或者不带 -y，逐项问答式确认（直接回车用默认值）
./BuildIJKPlayerKit.sh
```

不带参数运行时的问答示例：

```
▶ 产物工作区输出位置(工作区=<输入>/<名称>/，直接回车用当前:~/Desktop):

==================== 构建配置确认 ====================
  编译命名/模块名(字母开头，仅字母数字下划线，如 IJKPlayerKit) [当前:IJKPlayerKit]:
  输出类型(二选一：xcframework=多平台合包[推荐] / framework=散包) [当前:xcframework]:
  支持平台(输入: all=全要，或逗号分隔组合如 ios,macos；可选项 ios/tvos/macos) [当前:all]:
  包含模拟器切片(输入: 1=真机+模拟器[模拟器为arm64+x86_64双架构] / 0=仅真机[包更小]；macOS无模拟器不受影响) [当前:1]:
  深度改名(输入: 1=把FS前缀类名/文件名/注释也改为自定义前缀，如FSPlayer→IJKPlayer / 0=类名保持FSPlayer不动) [当前:1]:
  符号前缀(输入如 IJK/MR，大小写保形：FSPlayer→IJKPlayer、fs_hls→ijk_hls) [当前:IJK]:
  FSPlayer 版本(直接回空=远端默认分支最新；或填 tag 如 1.0.8 / 分支名 / commit号) [当前:]:
  源码仓库(直接回空=官方仓库；或填你的fork地址/本地路径如 ~/Desktop/xxx) [当前:官方仓库]:
=======================================================
```

## 二·五、工作区目录结构（重要）

每次构建按「**一个名字一个工作区**」组织（工作区 = `<输出根目录>/<名称>/`，输出根目录默认 `~/Desktop`、可在脚本配置区改、运行时也会询问；下面以默认值示例）：

```
~/Desktop/IJKPlayerKit/
├── FSPlayer/            ← 源码仓库(git)。想改播放器内核代码在这里改
│   ├── ijkmedia/          (播放器/渲染/字幕等 C 源码，内核逻辑在此)
│   ├── FFToolChain/       (构建工具链；build/product/ 下是下载好的预编译库)
│   ├── FSPlayer.yml       (xcodegen 工程定义，构建时会被自动改名为你的目标名)
│   └── examples/          (各平台构建脚本与产物中转目录)
├── Xcode工程/            ← 编译工程入口(IJKPlayerKit.xcodeproj，软链到源码仓内自动生成的工程)，
│                            双击即可在 Xcode 里浏览代码、修改、直接 IDE 构建
├── IJKPlayerKit/          ← 编译产物：IJKPlayerKit.xcframework(或散包) + 构建信息.txt + README.md(自动采集上游)
├── 预编译依赖库/         ← 软链 → FSPlayer/FFToolChain/build/product（ffmpeg/ass 等官方预编译包的实际位置）
└── README.md            ← 工作区自带说明（改代码重编译流程）
```

**改代码后重新编译**：

```bash
# 1. 在 IJKPlayerKit/FSPlayer/ 里改源码（如 ijkmedia/ 下的内核代码）
# 2. 重跑脚本——会自动检测到你的修改并保留（跳过版本更新），直接基于修改后的代码构建：
bash ~/Desktop/官人/IJKPlayerKit/构建脚本/BuildIJKPlayerKit.sh -y
# 3. 新产物仍输出在 IJKPlayerKit/IJKPlayerKit/（xcframework + 构建信息.txt）
```

> 脚本会自动区分「你的修改」和「脚本自己的改名改动」：你的修改永远不被还原；
> 想放弃修改回到上游状态：`cd IJKPlayerKit/FSPlayer && git checkout -- . && git clean -fd`（之后**务必重跑一次脚本**，让源码改名与 Xcode 工程重新对齐，否则 IDE 编不过）

> 首次运行新脚本时，若检测到旧版脚本的源码位置（~/Desktop/官人/FSPlayer）会**自动迁移**到新工作区，已下载的依赖库缓存一并保留，不会重新下载。

## 三、参数一览

| 参数 | 说明 | 默认 |
|---|---|---|
| `-n, --name <名称>` | 命名（模块名）。字母开头，仅字母/数字/下划线 | `IJKPlayerKit` |
| `-t, --type <类型>` | `framework` 或 `xcframework` | `xcframework` |
| `-p, --platforms <平台>` | `ios,tvos,macos` 逗号组合或 `all` | `all` |
| `-s, --simulator <0\|1>` | 是否含模拟器切片（macOS 不适用） | `1` |
| `-d, --rename-symbols <0\|1>` | **深度改名**：FS 前缀符号/文件名/注释 → 自定义前缀（由 `-x` 指定，默认 IJK）；关掉则类名保持 FS 前缀 | `1` |
| `-x, --symbol-prefix <前缀>` | 深度改名的目标前缀，如 `IJK`/`MR`/`XYZ` → `FSPlayer` 变 `IJKPlayer`/`MRPlayer`/`XYZPlayer`（字母开头，仅字母/数字/下划线） | `IJK` |
| `-v, --version <版本>` | FSPlayer 的 tag / 分支 / commit，留空=跟随远端默认分支最新 | 空（跟随默认分支） |
| `-r, --repo <地址>` | 源码仓库：https 地址 / **本地目录路径**(如 `~/Desktop/xxx`，从本地克隆，离线可用) / 你的 fork 地址 | debugly/fsplayer |
| `-o, --output <目录>` | **工作区输出根目录**，工作区为 `<目录>/<名称>/`（源码+产物+依赖库都在里面）。**不传时脚本一定会询问输出位置（即使带 `-y`，直接回车用默认）**——输出位置永远由你确认 | `~/Desktop` |
| `-l, --libs <库集>` | 预编译库集；`auto`=按仓库 ffmpeg.sh 软链自动探测 FFmpeg 大版本（上游升级自动跟随），也可手动如 `'ass ffmpeg8'` | `auto` |
| `-y, --yes` | 非交互模式，未指定项全用默认值 | — |
| `--no-update` | 跳过源码 git 更新（已手动更新过时用） | — |
| `--skip-metal-check` | 跳过 Metal 工具链检查 | — |
| `-h, --help` | 帮助 | — |

## 四、常用场景示例

```bash
# 1. 全家桶：全平台、含模拟器、xcframework（与历史 IJKPlayerKit 1.0.4 切片一致）
./BuildIJKPlayerKit.sh -y

# 2. 只出 iOS 真机包（体积最小，给 App Store 包瘦身用）
./BuildIJKPlayerKit.sh -p ios -s 0 -t framework -y

# 3. 锁定 FSPlayer 1.0.8 版本 + 仅 iOS/macOS
./BuildIJKPlayerKit.sh -v 1.0.8 -p ios,macos -y

# 4. 换个名字（比如给第二个 App 用不同的模块名避免冲突）
./BuildIJKPlayerKit.sh -n MyPlayerKit -y

# 5. 上游刚发了 1.0.9，升级重编（默认就会 fetch 最新 tag/分支）
./BuildIJKPlayerKit.sh -v 1.0.9 -y

# 6. 你自己 fork 了 FSPlayer 改了东西
./BuildIJKPlayerKit.sh -r https://github.com/你的账号/fsplayer.git -v 你的分支 -y
```

## 五、产物说明

### xcframework 模式

输出 `<工作区>/IJKPlayerKit/IJKPlayerKit.xcframework`，结尾会打印切片清单，例如：

```
arm64 ios
arm64 x86_64 ios simulator
arm64 tvos
arm64 x86_64 tvos simulator
arm64 x86_64 macos
```

### framework 模式

输出 `<工作区>/IJKPlayerKit/IJKPlayerKit-Frameworks/` 下按切片分目录：

```
IJKPlayerKit/
└── IJKPlayerKit/
    ├── IJKPlayerKit.xcframework         (xcframework 模式时)
    └── IJKPlayerKit-Frameworks/         (framework 模式时)
        ├── ios-device/IJKPlayerKit.framework
        ├── ios-simulator/IJKPlayerKit.framework
        ├── tvos-device/IJKPlayerKit.framework
        ├── tvos-simulator/IJKPlayerKit.framework
        └── macos/IJKPlayerKit.framework
```

`IJKPlayerKit/构建信息.txt` 记录本次构建的时间、FSPlayer 版本(commit)、参数与切片清单，方便追溯。

`IJKPlayerKit/README.md` 每次构建自动采集上游 README 生成（会覆盖上次的）：标题替换为 `前缀+Player`（默认 `IJKPlayer`）；保留徽章、功能清单、最新支持、构建环境+平台表；裁掉 star 名单横幅、调研中、迁移指南、更新记录、集成、编译步骤、FSPlayer-Pro 等上游专属章节。采集来源优先用本地源码仓里的 README（与编译版本精确对应），本地缺失时按 commit 号回源 GitHub 抓取。

### 命名机制（重要认知）

- **模块名**（Swift `import` 用的）＝ 你配置的名称，来自 `module-*.modulemap` 的 `framework module <名称>`
- **framework 文件名** ＝ 同样来自配置，来自 yml 的 `PRODUCT_NAME`
- **深度改名（默认开启，`-d 0` 关闭）**：源码内所有 FS 前缀符号/文件名/注释统一改为 IJK 前缀——
  `FSPlayer`→`IJKPlayer`、`FSOptions`→`IJKOptions`、`FSPlayerKit.h`→`IJKPlayerKit.h`、
  `FSPlayerDidFinishNotification`→`IJKPlayerDidFinishNotification`、import 形如 `<IJKPlayerKit/IJKMediaPlayback.h>`（框架前缀=命名配置）
  ⚠️ 开启后**业务代码里所有 FS 前缀的类型/协议/通知名也要改用 IJK 前缀**（封装层同步更新即可）
- 关闭深度改名(`-d 0`)时：类名保持 `FSPlayer` 等 FS 前缀（与上游一致），只有框架名/模块名变化，Swift 侧仅 `import` 行受影响

## 五·五、自己修改代码（完整步骤）

### 1. 打开工程

双击工作区的 `Xcode工程/IJKPlayerKit.xcodeproj`（它是软链，实际指向源码仓内自动生成的工程）。

> 前提：工作区是"刚跑完脚本"的状态（工程与源码文件名已对齐）。若你手动 `git checkout` 还原过源码，请先重跑一次脚本再打开 IDE，否则会编译报错（文件名错位）。

### 2. 选哪个 target？——只选一个，不用三个都选

三个 target（`IJKPlayerKit-iOS` / `IJKPlayerKit-macOS` / `IJKPlayerKit-tvOS`）**编译的是同一份源码文件**（都在 `FSPlayer/ijkmedia/` 下），它们之间只有平台差异（SDK、部署目标、各平台排除的少量专属文件）。因此：

- **改的是公共代码**（绝大多数情况）：选你最关心的一个 target 验证即可，通常选 `IJKPlayerKit-iOS`，右上角 destination 选任意 iPhone 模拟器
- **改的是平台专属文件**（如 `ijksdl_gpu_opengl_*macos*` 只有 macOS target 编译、`ijksdl_vout_ios_gles2` 只有 iOS）：切到对应平台 target 验证
- **不需要"三个依次编译"**——除非你想确认三个平台都过，可以依次切 target 按 Cmd+B（很快，增量编译）

### 3. 改哪里？——就是工程里看到的那些文件，直接改

在 Xcode 左侧文件树里看到的 `ijkmedia/...` 文件，**就是磁盘上 `FSPlayer/ijkmedia/` 里的同一份文件**（工程引用而非拷贝）。在 Xcode 里改 = 直接改源文件；用其他编辑器改磁盘上的文件，Xcode 也会自动刷新。两边等价，不会出现"改了两份"的问题。

快速定位（改哪类东西去哪）：

| 想改什么 | 位置 |
|---|---|
| 对外 API 层（`IJKPlayer`/`IJKOptions`/通知等 ObjC 类） | `ijkmedia/wrapper/apple/` |
| 播放器内核（ffplay 移植、解码调度、选项解析） | `ijkmedia/ijkplayer/`（核心是 `ff_ffplay.c`） |
| 音视频输出/渲染（Metal、AudioQueue 等） | `ijkmedia/ijksdl/`（渲染在 `ijksdl/metal/`） |
| 字幕 | `ijkmedia/ijkplayer/ff_subtitle*.c` |

### 4. 改完怎么编译？

**路线 A：IDE 快速验证（看能不能编过 / 断点调试）**

直接 Cmd+B。产物落在 DerivedData，只用于验证与调试，**不是交付物**。

**路线 B：出正式产物（交付用）**

```bash
bash ~/Desktop/官人/IJKPlayerKit/构建脚本/BuildIJKPlayerKit.sh -y
```

脚本会自动检测到你的修改并保留（跳过版本更新），在修改后的代码上重新编译所有配置的平台，产物输出到 `IJKPlayerKit/`（xcframework 模式）或 `IJKPlayerKit-Frameworks/`（散包模式）。若 Xcode 正开着工程，脚本跑完后关掉重开一次（工程文件被重新生成了）。

### 5. 另外两个 target 要不要同步修改？

**不需要，也没有"同步"这个概念。** 三个 target 共享同一份源码，你改一处，三个平台下一次构建自然都带上。它们不是三份代码，只是同一份代码的三个平台出口。

### 6. 注意事项

- **别在改完代码后手动 `git checkout`/`git clean` 还原源码**——会把改名对齐打破（IDE 编不过），要还原就还原后重跑脚本
- **想长期保留修改**：工作区随时可删（删了修改就没了），建议 fork 上游仓库、把修改提交进去，之后用 `-r 你的fork地址` 构建；或至少把 `FSPlayer/` 里的改动定期备份
- 每次脚本运行都会**重新生成 Xcode 工程**（源码改名后文件名变了，工程必须跟着重建），这是正常行为

## 六、脚本做了什么（原理速览）

1. **环境检查**：xcodegen / nasm 缺失自动 brew 安装；检测 Xcode 26 的独立 Metal 工具链组件，缺失自动下载
2. **源码准备**：首次克隆仓库与 FFToolChain 子模块；之后自动 `git fetch` + 切到指定版本
3. **还原 + 改名**：先把源码 `git checkout` 还原为上游原始状态（保证脚本可重复执行、换名重跑不残留），再把 7 处命名点统一替换为你的目标名：
   - `FSPlayer*.yml`（工程名 / target 名 / PRODUCT_NAME / Metal 输出路径）
   - `module-*.modulemap`（模块名）
   - `make-xcframework.sh`（打包框架名）
   - 头文件里的 `<FSPlayer/` 前缀 import
   - examples 里指向根工程的软链
4. **下载依赖**：`FFToolChain main.sh install` 下载官方预编译库（ass 全家桶 + ffmpeg8 全家桶，含 openssl/webp/smb2 等），并校验产物落位（下载 404 会显式报错，不会静默继续）
5. **生成工程 + 编译**：根目录 `generate-proj.sh` 生成工程，按平台/切片逐个 `xcodebuild`（日志落 `/tmp/FSPlayer-build-*.log`，失败即停）
6. **合包输出**：xcframework 用上游 `make-xcframework.sh`（自动跳过未构建的切片），拷贝到输出目录并打印切片清单与验证命令；随后生成构建信息.txt，并采集上游 README 生成产物 README.md

## 七、常见问题（FAQ）

**Q1：依赖库下载 404？（为什么 LIBS 默认是 auto、不能写 ffmpeg？）**
预编译包从 MRFFToolChainBuildShell 的 GitHub Releases 下载，**下载地址由"库配置文件名"拼出**。FFToolChain 里有多套 FFmpeg 配置（ffmpeg4/5/6/7/8.sh...），`ffmpeg.sh` 只是指向当前版本的软链。名字传错，拼出来的地址服务器上就没有：
- 传 `ffmpeg8` → `ffmpeg8-ios-universal-8.1.2.zip` ✅ 存在
- 传 `ffmpeg` → `ffmpeg-ios-universal-ffmpeg8-8.1.2.zip` ❌ 404（上游 README 的过时写法）

脚本默认 `auto`：直接读仓库里 `ffmpeg.sh` 软链指向谁就用谁——FSPlayer 以后升到 FFmpeg 9（软链改指 ffmpeg9.sh），脚本自动跟随，**你什么都不用改**。

**Q2：报 `cannot execute tool 'metal' due to missing Metal Toolchain`？**
Xcode 26 起 Metal 编译器是独立可下载组件。脚本会自动检测并下载（约 1~2GB，一次性的）。也可手动：`xcodebuild -downloadComponent MetalToolchain`。

**Q3：我改的代码会被脚本还原吗？——不会，有双重保护**
- **上游原始名文件**（如 `ijkplayer/ff_ffplay.c`、`ijksdl/` 内核代码）：脚本检测到修改即进入保留模式，直接在修改后的代码上构建
- **改名后的文件**（如 `wrapper/apple/IJKPlayer.h`）**和 yml/modulemap**：每次构建会记录"改名指纹清单"（`.ijk-build-manifest`，文件+内容哈希），下次运行逐个比对，发现你改过其中任何一个同样进入保留模式
- 只有**脚本自己上次做的改名**会被还原重做（保证可重复执行），与你的修改无关
- 注意：保留的修改只存在于工作区里，**工作区删除即丢失**；要长期保存请 fork 仓库提交修改，用 `-r` 构建

**Q4：想带 dSYM 调试符号？**
当前默认 Release 不产 dSYM。需要时在 `FSPlayer.yml` 各 target 的 `settings:` 里加 `DEBUG_INFORMATION_FORMAT: dwarf-with-dsym`（构建产物目录会出现 .dSYM，`make-xcframework.sh` 会自动带上）。该 yml 修改受指纹清单保护、重跑脚本不会被还原；但 yml 属上游文件，FSPlayer 升级后需在新版本上重加，建议同时记进自己的 fork。

**Q5：watchOS / visionOS 能支持吗？**
上游只提供 iOS / macOS / tvOS 三个 target。watchOS/visionOS 需要自行移植（FFmpeg 交叉编译 + 渲染层适配），不是改配置能解决的。

**Q6：升级 FSPlayer 后类名/接口变了导致我工程编译不过？**
看上游 CHANGELOG（如 1.0.7 移除了 `checkIfFFmpegVersionMatch` 等方法）。封装层（WYMediaPlayer）用的都是稳定接口，一般无感；若有变化，更新封装层即可。

**Q7：能重复跑吗？中途失败重跑会怎样？**
可以。改名基于"还原→重新替换"，重复执行结果一致；失败的切片重跑即可，已下载的依赖库会复用（下载有本地缓存目录）。

**Q8：构建完成后 `git status` 显示一大堆改动，正常吗？**
正常且有意为之：构建后的源码保持"改名状态"（IJK* 文件 + yml/modulemap 修改），与生成的 Xcode 工程对齐，供 IDE 直接 Cmd+B。下次运行脚本会先自动还原这些改动再重新改名，无需手动清理。**不要**手动 `git checkout` 还原后再用 IDE 编译（会文件名错位编不过）。

**Q9：`--no-update` 什么时候用？**
你已经自己 `git pull` / `git checkout` 好源码，不想让脚本再动版本时。注意脚本仍会执行"还原+改名"。

## 八、更新流程（FSPlayer 发新版后）

```bash
# 1. 看一眼上游更新了什么（可选）
#    https://github.com/debugly/fsplayer/releases

# 2. 一条命令出包（例如锁 1.0.9）
./BuildIJKPlayerKit.sh -v 1.0.9 -y

# 3. 产物在 <工作区>/IJKPlayerKit/，替换你 pod 仓库里的 xcframework，发新版即可
```

---

*适配说明：本脚本按 FSPlayer 1.0.8 的目录结构编写（根目录 generate-proj.sh + examples 工程软链方案）。若上游重构了目录/脚本结构，需同步调整脚本"改名"与"构建"两节。*
