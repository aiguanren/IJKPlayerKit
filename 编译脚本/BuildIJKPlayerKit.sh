#!/bin/bash
#
#  BuildIJKPlayerKit.sh
#  基于 debugly/FSPlayer 源码，自定义命名编译 framework / xcframework 的一键脚本
#
#  工作区布局(<输出根目录>/<名称>/)：
#    ├── FSPlayer/        源码仓库(git)，改代码在这里，改完重跑本脚本即重编译(脏树自动保留修改)
#    ├── Frameworks/      编译产物 + 构建信息.txt
#    └── 预编译依赖库/     软链 → FSPlayer/FFToolChain/build/product(ffmpeg/ass等预编译包实际位置)
#
#  工作流程：准备源码(克隆或更新+切版本+子模块) → 还原源码为上游原始状态(有本地修改时跳过，保留修改直接构建)
#  → 按目标名执行全套改名(yml/modulemap/打包脚本/头文件前缀/工程软链) → 下载预编译依赖库
#  → 生成Xcode工程 → 按平台/架构逐切片编译 → 合包输出到 Frameworks/
#
set -euo pipefail

# ==================== 自检：变量紧邻中文(bash 陷阱防护) ====================
# bash 解析 "$VAR中文" 这类写法时，会把紧跟变量的中文字符并入变量名去找
# "VAR中文" 这个不存在的变量 → unbound variable 崩溃(本脚本含大量中文提示文案，属高发区)。
# 正确写法是给变量加花括号："${VAR}中文"。本自检在启动时扫描脚本自身，
# 发现该模式即列出精确行号并退出，把问题拦截在运行之前。
# 说明：整行注释已被排除；若报告的是单引号字符串或行尾注释里的内容(不会执行)，
#       同样给该变量加上花括号即可消除告警。
self_lint_cjk_vars() {
    local report
    report=$(perl -ne 'print "$.:$_" if /\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]/ && !/^\s*#/' "$0" 2>/dev/null || true)
    if [[ -n "$report" ]]; then
        echo "❌ 自检发现 变量紧邻中文 的危险写法(运行时会 unbound variable)，请给以下变量加花括号："
        echo "$report"
        echo "修复方法：给该行的变量名包上花括号(变量与中文字符之间)，示例见上方自检注释"
        exit 1
    fi
}
self_lint_cjk_vars

# ==================== 默认配置(命令行参数可覆盖，命令行参数优先级更高) ====================
#
# 提示：下面每个值都是"默认值"。临时改用命令行参数(-n/-t/-p...)；长期固定偏好直接改这里。

# 【命名】framework/模块命名：决定产物文件名与 Swift 的 import 模块名
#   示例： IJKPlayerKit → 产物 IJKPlayerKit.xcframework，业务代码里 import IJKPlayerKit
#   注意： 类名是否跟随改名由下方【符号改名】决定——
#         RENAME_SYMBOLS=1 时类名同步改为前缀形式(FSPlayer→IJKPlayer)，=0 时类名保持 FS 前缀
NAME="IJKPlayerKit"

# 【输出类型】
#   xcframework = 多切片合包(推荐)：一个包内含所选平台的真机+模拟器切片，Xcode 按编译目标自动选用
#   framework   = 散包：每个平台每切片一个独立 .framework，按目录分开存放
TYPE="xcframework"

# 【平台】要支持的平台，逗号分隔自由组合
#   可选值： ios / tvos / macos / all(=三者全要)
#   示例： "all" 全平台；"ios" 只要 iOS；"ios,macos" iOS+macOS
PLATFORMS="all"

# 【模拟器】是否包含模拟器切片
#   1 = 包含：真机+模拟器(模拟器为 arm64 + x86_64 双架构)
#   0 = 不包含：仅真机，产物更小(macOS 没有"模拟器"概念，此开关对 macOS 无效)
SIMULATOR=1

# 【版本】基于 FSPlayer 的哪个版本编译，留空 = 跟随远端默认分支的最新提交
#   可填： tag(如 "1.0.8") / 分支名 / 具体 commit 号
#   示例： ""=跟最新；"1.0.8"=锁定1.0.8；"1.0.4"=回老版本重编
#   (对应命令行参数 -v，两者效果一样)
VERSION=""

# 【仓库】FSPlayer 源码仓库地址，三种写法都支持：
#   1. https 地址(默认)： 克隆 GitHub 上的官方仓库——公共仓库匿名克隆，不需要任何 git 账号/配置
#   2. 本地目录路径：     如 REPO="$HOME/Desktop/官人/FSPlayer"，从本地仓库克隆(速度极快，适合内网/离线，
#                          也适合"本地已有改好的仓库"的场景；更新走该本地仓库的 git pull)
#   3. 你自己 fork 的地址：想长期保留源码修改，fork 后填你的仓库
#   注意：只有"推送到你的 fork"才需要 git 账号；克隆(https/本地)都不需要
REPO="https://github.com/debugly/fsplayer.git"

# 【输出根目录】工作区 = <输出根目录>/<名称>/，源码/Xcode工程/产物/依赖库全在工作区内
#   注意：不通过 -o 显式指定时，脚本运行中一定会询问输出位置(直接回车才用这里的默认值)——
#         输出位置永远由你确认，不会悄悄落到别处
OUTPUT_ROOT="$HOME/Desktop"
# 输出位置是否已通过命令行显式指定(内部标记，勿改)
EXPLICIT_OUTPUT=0

# 【非交互】1 = 不逐项询问，未指定的项直接用默认值(适合脚本调用/自动化)；0 = 逐项问答确认
ASSUME_YES=0

# 【跳过更新】1 = 不做 git 拉取与切版本(已手动更新源码时用)；0 = 正常自动更新到指定版本
NO_UPDATE=0

# 【跳过Metal检查】1 = 跳过 Metal 工具链检查(已装过可跳过提速)；0 = 检查缺失自动下载
#   背景：Xcode 26 起编译 .metal 文件需要独立下载的 Metal Toolchain 组件
SKIP_METAL_CHECK=0

# 【符号改名】是否把源码内所有 FS 前缀的符号/文件名/注释深度改为自定义前缀
#   1 = 深度改名(推荐)：类名/协议/枚举/通知名/函数/文件名/注释全改，前缀由 SYMBOL_PREFIX 决定，如
#         FSPlayer→IJKPlayer、FSOptions→IJKOptions、FSAudioRenderingProtocol→IJKAudioRenderingProtocol、
#         FSPlayerKit.h→IJKPlayerKit.h、FSPlayerDidFinishNotification→IJKPlayerDidFinishNotification
#       import 形如 <IJKPlayerKit/IJKMediaPlayback.h>(框架前缀=命名配置)
#   0 = 只改框架名/模块名(类名等保持 FS 前缀，与上游完全一致)
#   注意：深度改名后，业务代码里所有 FS 前缀类型/通知名也要相应改用此前缀
RENAME_SYMBOLS=1

# 【符号前缀】深度改名使用的目标前缀(仅 RENAME_SYMBOLS=1 时生效)，大小写保形：
#   大写 FS→前缀原样(FSPlayer→IJKPlayer)、小写 fs→前缀小写(fs_hls→ijk_hls、FSPlayer→ijkplayer)
#   示例： "IJK"(默认)；"MR"→MRPlayer/mr_hls；"XYZ"→XYZPlayer/xyz_hls
#   规则： 字母开头，仅字母/数字/下划线
#   安全边界：fsync/fstat/fseek 等 C 库函数与 fsr/fsh 等核心变量不受影响(小写字母跟随不替换)，
#             只改 fs_下划线、fs大写驼峰、FSPlayer/fsrecord/fsmux 整词
SYMBOL_PREFIX="IJK"

# 【库集】FFToolChain 预编译库集
#   auto = 自动探测(推荐)：按仓库内 ffmpeg.sh 软链指向自动选 ffmpeg 大版本，上游升级后无需改这里
#   也可手动指定，如 "ass ffmpeg8"
#   ⚠️ 为什么不能写 'ffmpeg'：预编译包从 MRFFToolChainBuildShell 的 Releases 下载，
#   下载地址由"库配置文件名"拼出来。configs/libs/ 下有 ffmpeg4/5/6/7/8.sh 多套配置，
#   ffmpeg.sh 只是指向当前版本的软链(现为 ffmpeg8.sh)：
#     传 ffmpeg8 → 拼 ffmpeg8-ios-universal-8.1.2.zip            → 服务器上存在 ✓
#     传 ffmpeg  → 拼 ffmpeg-ios-universal-ffmpeg8-8.1.2.zip     → 服务器上没有 ✗ 404
#   auto 直接读软链指向，以后升到 FFmpeg 9(软链改指 ffmpeg9.sh)会自动跟随。
LIBS="auto"

# 由上面两项派生(不让用户直接配，避免源码与产物分家)
WORKDIR="$OUTPUT_ROOT/$NAME/FSPlayer"

# ==================== 帮助 ====================

usage() {
    cat << EOF
用法: $(basename "$0") [选项]

工作区布局: <输出根目录>/<名称>/
  FSPlayer/        源码仓库(改代码在这里，改完重跑本脚本即可重编译)
  Frameworks/      编译产物 + 构建信息.txt
  预编译依赖库/     软链 → 源码内 FFToolChain/build/product (ffmpeg/ass 等预编译包)

选项:
  -n, --name <名称>        framework 名称，即 import 的模块名 (默认: $NAME)
  -t, --type <类型>        输出类型: framework | xcframework (默认: $TYPE)
  -p, --platforms <平台>   逗号分隔组合: ios,tvos,macos 或 all (默认: $PLATFORMS)
  -s, --simulator <0|1>    是否包含模拟器切片 (默认: ${SIMULATOR}，macOS 不适用)
  -d, --rename-symbols <0|1> 是否深度改名：FS前缀符号/文件名/注释→自定义前缀 (默认: ${RENAME_SYMBOLS})
  -x, --symbol-prefix <前缀> 深度改名的目标前缀，如 WY/IJK/XYZ → FSPlayer变IJKPlayer/WYPlayer/XYZPlayer (默认: ${SYMBOL_PREFIX})
  -v, --version <版本>     FSPlayer 的 tag/分支/commit (默认: 跟随远端默认分支)
  -r, --repo <地址>        源码仓库地址 (默认: $REPO)
  -o, --output <目录>      工作区输出根目录，工作区为 <目录>/<名称>/ (不传时运行中会询问，回车用默认)
  -l, --libs <库集>        预编译库集 (默认: auto 自动探测FFmpeg大版本，也可如 'ass ffmpeg8')
  -y, --yes                非交互模式：未指定的项直接用默认值，不逐项询问
      --no-update          跳过源码 git 拉取更新
      --skip-metal-check   跳过 Metal 工具链检查
  -h, --help               显示本帮助

示例:
  $(basename "$0") -y                                             # 全默认: IJKPlayerKit 全平台 xcframework
  $(basename "$0") -n MyPlayer -p ios -s 0 -t framework -y        # 仅 iOS 真机散包
  $(basename "$0") -v 1.0.8 -p ios,macos -y                       # 锁定版本、iOS+macOS
  $(basename "$0") --no-update -y                                 # 改完源码后重编译(保留本地修改)
EOF
    exit 0
}

# ==================== 参数解析 ====================

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--name)         NAME="$2"; shift 2 ;;
        -t|--type)         TYPE="$2"; shift 2 ;;
        -p|--platforms)    PLATFORMS="$2"; shift 2 ;;
        -s|--simulator)    SIMULATOR="$2"; shift 2 ;;
        -d|--rename-symbols) RENAME_SYMBOLS="$2"; shift 2 ;;
        -x|--symbol-prefix) SYMBOL_PREFIX="$2"; shift 2 ;;
        -v|--version)      VERSION="$2"; shift 2 ;;
        -r|--repo)         REPO="$2"; shift 2 ;;
        -o|--output)       OUTPUT_ROOT="$2"; EXPLICIT_OUTPUT=1; shift 2 ;;
        -l|--libs)         LIBS="$2"; shift 2 ;;
        -y|--yes)          ASSUME_YES=1; shift ;;
        --no-update)       NO_UPDATE=1; shift ;;
        --skip-metal-check) SKIP_METAL_CHECK=1; shift ;;
        -h|--help)         usage ;;
        *) echo "未知参数: $1 (用 -h 查看帮助)"; exit 1 ;;
    esac
done

# 名称合法性：只允许字母数字下划线(会进 sed/路径/模块名，防注入)
if ! [[ "$NAME" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
    echo "❌ 名称 '$NAME' 不合法：需以字母开头，仅含字母/数字/下划线"; exit 1
fi
if [[ "$TYPE" != "framework" && "$TYPE" != "xcframework" ]]; then
    echo "❌ 类型必须是 framework 或 xcframework"; exit 1
fi
if ! [[ "$SYMBOL_PREFIX" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
    echo "❌ 符号前缀 '$SYMBOL_PREFIX' 不合法：需以字母开头，仅含字母/数字/下划线"; exit 1
fi
[[ "$PLATFORMS" == "all" ]] && PLATFORMS="ios,tvos,macos"

WORKDIR="$OUTPUT_ROOT/$NAME/FSPlayer"

# ==================== 交互补问(未指定且非 -y 时) ====================

ask() { # ask "提示" 默认值 → 回显用户输入或默认值
    local tip="$1" def="$2" ans
    [[ "$ASSUME_YES" == "1" ]] && { echo "$def"; return; }
    local disp="${def}"
    [[ -z "$disp" ]] && disp="(空)"
    read -r -p "$tip [当前:${disp}]: " ans || ans=""
    echo "${ans:-$def}"
}

# 输出位置必须由使用者确认：未通过 -o 显式指定时一律询问(含 -y 模式，回车即用默认值)
if [[ "$EXPLICIT_OUTPUT" == "0" ]]; then
    read -r -p "▶ 产物工作区输出位置(工作区=<输入>/<名称>/，直接回车用当前:${OUTPUT_ROOT}): " ans || ans=""
    [[ -n "$ans" ]] && OUTPUT_ROOT="$ans"
fi

echo "==================== 构建配置确认 ===================="
NAME=$(ask "  编译命名/模块名(字母开头，仅字母数字下划线，如 IJKPlayerKit)" "$NAME")
TYPE=$(ask "  输出类型(二选一：xcframework=多平台合包[推荐] / framework=散包)" "$TYPE")
PLATFORMS=$(ask "  支持平台(输入: all=全要，或逗号分隔组合如 ios,macos；可选项 ios/tvos/macos)" "$PLATFORMS")
SIMULATOR=$(ask "  包含模拟器切片(输入: 1=真机+模拟器[模拟器为arm64+x86_64双架构] / 0=仅真机[包更小]；macOS无模拟器不受影响)" "$SIMULATOR")
RENAME_SYMBOLS=$(ask "  深度改名(输入: 1=把FS前缀类名/文件名/注释也改为自定义前缀，如FSPlayer→IJKPlayer / 0=类名保持FSPlayer不动)" "$RENAME_SYMBOLS")
if [[ "$RENAME_SYMBOLS" == "1" ]]; then
    SYMBOL_PREFIX=$(ask "  符号前缀(输入如 WY/IJK，大小写保形：FSPlayer→IJKPlayer、fs_hls→ijk_hls)" "$SYMBOL_PREFIX")
fi
VERSION=$(ask "  FSPlayer 版本(直接回空=远端默认分支最新；或填 tag 如 1.0.8 / 分支名 / commit号)" "$VERSION")
REPO=$(ask "  源码仓库(直接回空=官方仓库；或填你的fork地址/本地路径如 ~/Desktop/xxx)" "$REPO")
echo "======================================================="
if [[ "$RENAME_SYMBOLS" == "1" ]]; then
    echo "命名: $NAME | 类型: $TYPE | 平台: $PLATFORMS | 模拟器: $SIMULATOR | 版本: ${VERSION:-远端默认分支}"
    echo "深度改名: 开启 | 符号前缀: $SYMBOL_PREFIX(FS→${SYMBOL_PREFIX}、fs→$(echo "$SYMBOL_PREFIX" | tr '[:upper:]' '[:lower:]'))"
else
    echo "命名: $NAME | 类型: $TYPE | 平台: $PLATFORMS | 模拟器: $SIMULATOR | 版本: ${VERSION:-远端默认分支}"
    echo "深度改名: 关闭(类名保持 FS 前缀)"
fi
echo "工作区: $OUTPUT_ROOT/$NAME"
echo "(高级项不逐项询问：库集LIBS/跳过更新/跳过Metal检查等，如需调整用命令行参数或改脚本配置区)"
echo "======================================================="

WORKDIR="$OUTPUT_ROOT/$NAME/FSPlayer"

# 本地仓库路径支持 ~ 写法(如 ~/Desktop/xxx)——放在询问之后，交互输入的本地路径同样生效
REPO="${REPO/#\~/$HOME}"

# 交互输入的前缀需要再次校验合法性(询问发生在下方，此处已拿到最终值)
if ! [[ "$SYMBOL_PREFIX" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
    echo "❌ 符号前缀 '$SYMBOL_PREFIX' 不合法：需以字母开头，仅含字母/数字/下划线"; exit 1
fi

# 平台列表解析
IFS=',' read -ra PLATS <<< "$PLATFORMS"
for p in "${PLATS[@]}"; do
    [[ "$p" == "ios" || "$p" == "tvos" || "$p" == "macos" ]] || { echo "❌ 未知平台: $p"; exit 1; }
done

# ==================== 环境检查 ====================

echo "▶ [1/7] 环境检查"
for cmd in xcodegen nasm git; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "  缺少 ${cmd}，尝试 brew install $cmd ..."
        brew install "$cmd"
    }
done

# Xcode 26 起 Metal 编译器是独立组件，缺失会报 "cannot execute tool 'metal'"
if [[ "$SKIP_METAL_CHECK" == "0" ]]; then
    if ! xcodebuild -showComponent MetalToolchain 2>/dev/null | grep -q "Status: installed"; then
        echo "  Metal 工具链未安装(约1~2GB)，开始下载 ..."
        xcodebuild -downloadComponent MetalToolchain
    fi
fi

mkdir -p "$OUTPUT_ROOT/$NAME"

# ==================== 源码准备 ====================

echo "▶ [2/7] 准备源码"
if [[ ! -d "$WORKDIR/.git" ]]; then
    if [[ -d "$REPO" ]]; then
        echo "  检测到本地仓库: $REPO (从本地克隆，无需网络拉取上游)"
    fi
    # 迁移：旧版脚本的默认源码位置(避免重复克隆、保留已下载的预编译库缓存)
    OLD_DEFAULT="$HOME/Desktop/官人/FSPlayer"
    if [[ -d "$OLD_DEFAULT/.git" && "$WORKDIR" != "$OLD_DEFAULT" ]]; then
        echo "  迁移旧源码目录: $OLD_DEFAULT → $WORKDIR (保留已下载的依赖库缓存)"
        mv "$OLD_DEFAULT" "$WORKDIR"
    else
        echo "  克隆 $REPO → $WORKDIR"
        mkdir -p "$(dirname "$WORKDIR")"
        git clone "$REPO" "$WORKDIR"
    fi
fi
cd "$WORKDIR"

# 区分"脚本自有的改名改动"与"用户自己的代码修改"：
#   - 未跟踪文件(?? 构建产物/生成工程)不算脏
#   - 脚本改的名字相关文件(yml/modulemap/打包脚本/公开头文件/工程软链)不算用户改动
#   - 其余有改动 = 用户改过代码 → 保留修改模式：跳过版本更新与还原，直接在其上构建
PRESERVE_MODE=0
# 第一道判定(精确)：逐个比对上次构建留下的指纹清单——脚本改过/生成的文件若与记录哈希不符，
# 说明你改过这些文件(如改名后的 IJKPlayer.h、yml、modulemap)，必须保留，不能被还原+clean抹掉
MANIFEST_FILE="$WORKDIR/.ijk-build-manifest"
if [[ -f "$MANIFEST_FILE" ]]; then
    while read -r tag hash path; do
        [[ -z "$tag" ]] && continue
        if [[ "$tag" == "del" ]]; then
            if [[ -e "$path" ]]; then
                PRESERVE_MODE=1
                echo "  ⚠️ 指纹比对：上游被改名删除的文件被恢复了($path)——进入保留模式"
                break
            fi
        else
            cur="$(shasum -a 256 "$path" 2>/dev/null | awk '{print $1}')"
            if [[ -z "$cur" || "$cur" != "$hash" ]]; then
                PRESERVE_MODE=1
                echo "  ⚠️ 指纹比对：检测到你修改过构建生成文件($path)——保留修改，跳过版本更新与还原"
                break
            fi
        fi
    done < "$MANIFEST_FILE"
fi
# 第二道判定(兜底)：上游原始名文件的修改(如 ijkplayer/ff_ffplay.c)不属于脚本管辖，直接视为你的修改
if [[ "$PRESERVE_MODE" == "0" ]]; then
    USER_DIRTY=$(git status --porcelain 2>/dev/null | grep -v '^??' | \
        grep -v -E '(FSPlayer[^/]*\.yml|module-[^/]*\.modulemap|make-xcframework\.sh|wrapper/apple/.*\.h|examples/[^/]+/[^/]*\.xcodeproj)$' || true)
    if [[ -n "$USER_DIRTY" ]]; then
        PRESERVE_MODE=1
        echo "  ⚠️ 检测到源码有你自己的本地修改——保留修改，跳过版本更新，直接在其上构建"
        echo "     (如需回到上游干净状态: cd "$WORKDIR" && git stash 或 git checkout -- . 后重跑)"
    fi
fi
[[ "$PRESERVE_MODE" == "1" ]] && NO_UPDATE=1
# 注意：不做"构建结束后还原源码"——生成的Xcode工程引用的是改名后的文件(IJK*.h等)，
# 若结束后把源码还原成上游FS*文件名，工程与磁盘文件错位，用户在IDE里Cmd+B必然失败；
# 幂等性由下一次运行开始时的"还原+重新改名+重新生成工程"保证，构建完成后保持改名状态供IDE使用

if [[ "$NO_UPDATE" == "0" ]]; then
    echo "  拉取远端并解析目标版本(网络慢时可能需要几分钟，下面会显示 git 进度；卡住超过60秒会自动报错而不是无限等待) ..."
    # GIT_HTTP_LOW_SPEED_*: 传输速度持续低于下限达60秒即中止，避免网络异常时无限静默挂起
    # 不用 -q: 保留 git 自带的进度输出(远端枚举/接收进度)，让等待过程可见
    if ! GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=60 git fetch --all --tags --progress 2>&1; then
        echo "  ⚠️ git 拉取远端失败(网络问题？)——继续使用本地已有的版本构建；如需最新版请检查网络后重试"
    fi
    # 浅克隆时补全历史(否则切任意 tag/分支可能失败)
    if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
        echo "  检测到浅克隆，补全完整历史 ..."
        if ! GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=60 git fetch --unshallow --progress 2>&1; then
            echo "  ⚠️ 补全历史失败(网络问题？)——浅克隆下部分 tag/分支可能切不过去，继续尝试 ..."
        fi
    fi
    # 未指定版本时解析远端默认分支(上游没有 master 分支，不能写死)
    TARGET="$VERSION"
    if [[ -z "$TARGET" ]]; then
        TARGET=$(GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=60 git ls-remote --symref origin HEAD 2>/dev/null | awk '/^ref:/{sub("refs/heads/","",$2); print $2; exit}')
        if [[ -z "$TARGET" ]]; then
            echo "  ⚠️ 查询远端默认分支失败(网络问题？)——改用本地 HEAD 继续"
            TARGET="HEAD"
        else
            echo "  远端默认分支: $TARGET"
        fi
    fi
    git checkout -q "$TARGET" || { echo "❌ 切换版本失败: $TARGET"; exit 1; }
    # 目标是分支(非tag/detached commit)时快进到最新
    if git show-ref --verify --quiet "refs/heads/$TARGET" 2>/dev/null; then
        if ! GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=60 git pull --ff-only origin "$TARGET" 2>&1; then
            echo "  ⚠️ git pull 快进失败(网络问题或本地有分叉？)——继续用当前本地状态"
        fi
    fi
fi

echo "  初始化子模块(FFToolChain)"
git submodule update --init -q

# 还原源码为上游原始状态(丢弃上一次构建的改名等本地改动，保证改名步骤可重复执行)
# 保留模式下绝不还原——那会抹掉用户自己的代码修改
if [[ "$PRESERVE_MODE" == "0" ]]; then
    # checkout 还原被改的跟踪文件；clean 清掉上次崩溃运行残留的未跟踪改名文件(避免新旧并存重复编译)
    git checkout -q -- . || true
    git clean -qfd -e FFToolChain -e build -e .ijk-build-manifest 2>/dev/null || true
fi

COMMIT="$(git rev-parse --short HEAD 2>/dev/null)"
DESCRIBE="$(git describe --tags 2>/dev/null || echo "$COMMIT")"
echo "  源码就绪: $DESCRIBE"

# ==================== 改名(从上游 FSPlayer 基线 → 目标名) ====================

echo "▶ [3/7] 执行改名: FSPlayer → $NAME"

# 1. 工程定义 yml：工程名/target名/PRODUCT_NAME(决定 .framework 名)/Metal库输出路径
sed -i '' \
    -e "s/^name: FSPlayer$/name: $NAME/" \
    -e "s/FSPlayer-macOS:/$NAME-macOS:/" \
    -e "s/FSPlayer-iOS:/$NAME-iOS:/" \
    -e "s/FSPlayer-tvOS:/$NAME-tvOS:/" \
    -e "s/PRODUCT_NAME: FSPlayer/PRODUCT_NAME: $NAME/" \
    -e "s|/FSPlayer.framework|/$NAME.framework|g" \
    FSPlayer.yml FSPlayer-5.yml FSPlayer-6.yml

# 2. 自定义 modulemap：模块名(Swift 的 import 名)定义在这里
#    兼容脏树场景：树可能已被上一轮改成别的名字，统一改写为本次目标名
sed -i '' -E "s/framework module [A-Za-z][A-Za-z0-9_]* \{/framework module $NAME {/" \
    module-ios.modulemap module-macos.modulemap module-tvos.modulemap

# 3. xcframework 打包脚本：框架名变量
sed -i '' -E "s/FMN=\"[A-Za-z][A-Za-z0-9_]*\"/FMN=\"$NAME\"/" examples/xcframewrok/make-xcframework.sh

# 4. 公开头文件里的框架名前缀 import：<FSPlayer/xxx.h> → <目标名/xxx.h>
#    兼容脏树场景：先把任意旧名字的前缀还原成 FSPlayer，再统一替换
grep -rln "#import <[A-Za-z][A-Za-z0-9_]*/" ijkmedia/wrapper/apple/*.h 2>/dev/null | \
    xargs sed -i '' -E "s|#import <[A-Za-z][A-Za-z0-9_]*/FS|#import <FSPlayer/FS|g" 2>/dev/null || true
grep -rln "#import <FSPlayer/" ijkmedia/ | xargs sed -i '' "s|#import <FSPlayer/|#import <$NAME/|g" 2>/dev/null || true

# 5. examples 内的工程软链：使 PROJECT_DIR 停留在 examples/<平台>，yml 相对路径才成立
for p in ios macos tvos; do
    find "examples/$p" -maxdepth 1 -name "*.xcodeproj" -type l -delete 2>/dev/null || true
    rm -rf "examples/$p/FSPlayer.xcodeproj" "examples/$p/$NAME.xcodeproj"
    ln -s "../../$NAME.xcodeproj" "examples/$p/$NAME.xcodeproj"
done

# 6. 符号深度改名(可选)：源码内所有 FS 前缀符号/文件名/注释 → IJK 前缀
#    必须放在框架名替换之后：先把 <FSPlayer/ 前缀 import 换成 <目标名/，再统一 FS→IJK，
#    两步互不干扰(import 的框架前缀=框架名，符号前缀=固定 IJK)
if [[ "$RENAME_SYMBOLS" == "1" ]]; then
    SYMBOL_PREFIX_LOWER="$(echo "$SYMBOL_PREFIX" | tr '[:upper:]' '[:lower:]')"
    echo "  深度改名(大小写保形)：FS→${SYMBOL_PREFIX}、fs→${SYMBOL_PREFIX_LOWER} ..."
    # 6.1 内容替换：ijkmedia 全部源码(含 .sh——version.sh 会在构建期生成版本宏头文件，宏名如 FSPlayer_VERSION 也必须改，否则 ijkplayer.c 里改过的 IJKPLAYER_VERSION 无定义) + 根目录 modulemap，规则按序执行：
    #     R1 大写符号：   FSxxx   → <前缀>xxx        (前缀原样，如 FSPlayer→IJKPlayer)
    #     R1b 下划线tag： _FSXxx  → _<前缀>Xxx       (ObjC枚举tag命名惯例，如 _FSSDLRotateType→_IJKSDLRotateType；
    #                 已核实源码无 XX_FS 结尾的其他命名，此规则零误伤)
    #     R2 下划线小写： fs_xxx  → <前缀小写>_xxx    (项目自有工具函数风格，如 fs_hls→ijk_hls)
    #     R3 驼峰小写：   fsXxx   → <前缀小写>Xxx     (仅当跟大写字母，避开 fsync/fseek/fstat 等 C 库函数)
    #     R4 整词品牌：   FSPlayer/fsrecord/fsmux → <前缀小写>player/record/mux (User-Agent值/日志前缀/线程名)
    #     R5 裸fs标识符： 独立单词 fs → <前缀小写>    (ff_ass_renderer.c/ijkmeta.c 各一个局部变量 char *fs=ptr
    #                 及其全部引用、注释里 "fs buitn-in" 文案；fsync/fseek 等因fs后跟小写字母不构成独立词，不受影响)
    #     不动：小写字母跟随的 fsr/fsh(ffmpeg核心变量)与 fsync 等 C 标准库函数
    find ijkmedia -type f \( -name "*.h" -o -name "*.m" -o -name "*.mm" -o -name "*.c" -o -name "*.cpp" -o -name "*.metal" -o -name "*.sh" \) -print0 |
        xargs -0 sed -i '' -E -e "s/[[:<:]]FS([A-Za-z0-9_]+)/${SYMBOL_PREFIX}\1/g" -e "s/_FS([A-Z][A-Za-z0-9_]+)/_${SYMBOL_PREFIX}\1/g" -e "s/[[:<:]]fs_([A-Za-z0-9_]+)/${SYMBOL_PREFIX_LOWER}_\1/g" -e "s/[[:<:]]fs([A-Z][A-Za-z0-9_]+)/${SYMBOL_PREFIX_LOWER}\1/g" -e "s/[[:<:]]FSPlayer[[:>:]]/${SYMBOL_PREFIX_LOWER}player/g" -e "s/[[:<:]]fsrecord[[:>:]]/${SYMBOL_PREFIX_LOWER}record/g" -e "s/[[:<:]]fsmux[[:>:]]/${SYMBOL_PREFIX_LOWER}mux/g" -e "s/[[:<:]]fs[[:>:]]/${SYMBOL_PREFIX_LOWER}/g"
    sed -i '' -E "s/[[:<:]]FS([A-Za-z0-9_]+)/${SYMBOL_PREFIX}\1/g" module-ios.modulemap module-macos.modulemap module-tvos.modulemap
    # 6.2 文件改名：FS* → <前缀>*、fs* → <前缀小写>*(内容引用已在6.1同步替换)
    find ijkmedia -type f \( -name "FS*" -o -name "fs*" \) | while read -r f; do
        local_base="$(basename "$f")"
        if [[ "$local_base" == FS* ]]; then
            mv "$f" "$(dirname "$f")/${SYMBOL_PREFIX}${local_base#FS}"
        else
            mv "$f" "$(dirname "$f")/${SYMBOL_PREFIX_LOWER}${local_base#fs}"
        fi
    done
    # 6.3 深度改名自检：源码里不允许再残留词首 FS 符号
    #     注意 grep 无匹配时退出码为1，在 set -e 下会静默杀死脚本，必须 || true
    LEFT=$({ grep -rE -l '[[:<:]]FS[A-Za-z0-9_]+' ijkmedia --include='*.h' --include='*.m' --include='*.mm' --include='*.metal' 2>/dev/null || true; } | head -3)
    [[ -z "$LEFT" ]] || echo "  ⚠️ 仍有 FS 前缀残留(可能为合理引用，请人工确认): $LEFT"
    echo "  深度改名完成(前缀 ${SYMBOL_PREFIX}/${SYMBOL_PREFIX_LOWER}：类名如 ${SYMBOL_PREFIX}Player，工具函数如 ${SYMBOL_PREFIX_LOWER}_hls)"
fi

# 记录改名指纹清单：脚本本次改过/生成的文件 + 内容哈希。
# 用途：下次运行时逐个比对，任何一个文件与记录不符 = 用户改过这些文件 → 自动进入保留模式，
# 防止"还原+clean"抹掉用户对改名后文件(如 IJKPlayer.h)或 yml/modulemap 的修改
MANIFEST_FILE="$WORKDIR/.ijk-build-manifest"
: > "$MANIFEST_FILE"
git status --porcelain | while read -r xy path; do
    if [[ "$path" == *" -> "* ]]; then path="${path##* -> }"; fi
    case "$path" in
        ijkmedia/*|FSPlayer*.yml|module-*.modulemap|examples/xcframewrok/make-xcframework.sh)
            if [[ -f "$path" ]]; then
                echo "sha $(shasum -a 256 "$path" | awk '{print $1}') $path" >> "$MANIFEST_FILE"
            else
                echo "del $path" >> "$MANIFEST_FILE"
            fi
            ;;
    esac
done
echo "  已记录改名指纹清单($(wc -l < "$MANIFEST_FILE" | tr -d ' ')个文件)，用于识别你后续对这些文件的修改"

# 改名自检：modulemap 与 PRODUCT_NAME 必须已替换，否则后面必然白跑
grep -q "framework module $NAME" module-ios.modulemap || { echo "❌ 改名自检失败(modulemap)"; exit 1; }
grep -q "PRODUCT_NAME: $NAME" FSPlayer.yml || { echo "❌ 改名自检失败(yml)"; exit 1; }
echo "  改名完成并自检通过"

# ==================== 依赖库 ====================

echo "▶ [4/7] 下载/安装预编译依赖库(FFmpeg 版本随仓库配置)"
# LIBS=auto：ass + 按仓库内 ffmpeg.sh 软链自动探测 ffmpeg 大版本(上游升级后自动跟随)
if [[ "$LIBS" == "auto" ]]; then
    FFMPEG_LIB="$(basename "$(readlink "$WORKDIR/FFToolChain/configs/libs/ffmpeg.sh" 2>/dev/null || echo ffmpeg8.sh)" .sh)"
    LIBS="ass ${FFMPEG_LIB:-ffmpeg8}"
    echo "  自动探测库集(依据仓库 ffmpeg.sh 软链): $LIBS"
fi
for p in "${PLATS[@]}"; do
    echo "  安装 $p 库集: $LIBS (下载中，首次约需几分钟；此阶段无输出属正常，实时日志: tail -f /tmp/FSPlayer-install-$p.log)"
    bash FFToolChain/main.sh install -p "$p" -l "$LIBS" >/tmp/FSPlayer-install-$p.log 2>&1 || {
        echo "❌ $p 库安装失败，详见 /tmp/FSPlayer-install-$p.log"; exit 1; }
    # 校验关键产物确实落位(install 对下载404不总是报错，必须显式验证)
    [[ -d "FFToolChain/build/product/$p/universal/ffmpeg/lib" ]] || {
        echo "❌ $p 的 ffmpeg 库未落位(疑似下载404)，详见 /tmp/FSPlayer-install-$p.log"; exit 1; }
done

# ==================== 生成工程 ====================

echo "▶ [5/7] 生成 Xcode 工程"
./generate-proj.sh >/tmp/FSPlayer-xcodegen.log 2>&1 || { echo "❌ 工程生成失败，详见 /tmp/FSPlayer-xcodegen.log"; exit 1; }
[[ -d "$NAME.xcodeproj" ]] || { echo "❌ 未生成 $NAME.xcodeproj"; exit 1; }

# ==================== 编译 ====================

echo "▶ [6/7] 编译各平台切片"

# build_slice <平台> <target后缀> <sdk> <架构...>  —— 构建一个切片，日志落盘，失败即停
build_slice() {
    local plat="$1" suffix="$2" sdk="$3"; shift 3
    local archs=(); local a
    for a in "$@"; do archs+=(-arch "$a"); done
    echo "    ▶ $plat ($sdk: $*)"
    # BUILD_DIR 必须传绝对路径：xcodebuild 拿到软链工程时会按真实路径切换自身工作目录，
    # 相对路径 BUILD_DIR=. 的产物落点会漂移(实测漂到仓库根目录)，绝对路径则恒定落在 examples/<平台>/ 下
    local absdir="$WORKDIR/examples/$plat"
    ( cd "$absdir" && \
      xcodebuild -project "$NAME.xcodeproj" -target "$NAME-$suffix" \
        -configuration Release -sdk "$sdk" "${archs[@]}" BUILD_DIR="$absdir" \
        clean build > "/tmp/FSPlayer-build-$plat-$sdk.log" 2>&1 ) || {
        echo "❌ 构建失败，详见 /tmp/FSPlayer-build-$plat-$sdk.log"; exit 1; }
}

for p in "${PLATS[@]}"; do
    echo "  —— 平台: $p"
    case "$p" in
        ios)
            build_slice ios  iOS iphoneos        arm64
            [[ "$SIMULATOR" == "1" ]] && build_slice ios iOS iphonesimulator arm64 x86_64
            ;;
        tvos)
            build_slice tvos tvOS appletvos      arm64
            [[ "$SIMULATOR" == "1" ]] && build_slice tvos tvOS appletvsimulator arm64 x86_64
            ;;
        macos)
            build_slice macos macOS macosx       arm64 x86_64
            ;;
    esac
done

# ==================== 输出产物 ====================

echo "▶ [7/7] 输出产物"

FW_DIR="$OUTPUT_ROOT/$NAME/Frameworks"
mkdir -p "$FW_DIR"

# 清理另一输出形态的陈旧产物，保证 Frameworks/ 内容精确对应本次构建
rm -rf "$FW_DIR/$NAME-Frameworks" "$FW_DIR/$NAME.xcframework"

if [[ "$TYPE" == "xcframework" ]]; then
    ( cd examples/xcframewrok && ./make-xcframework.sh > /tmp/FSPlayer-xcframework.log 2>&1 ) || {
        echo "❌ xcframework 合包失败，详见 /tmp/FSPlayer-xcframework.log"; exit 1; }
    rm -rf "$FW_DIR/$NAME.xcframework"
    cp -R "examples/xcframewrok/$NAME.xcframework" "$FW_DIR/"
    echo "  ✔ $FW_DIR/$NAME.xcframework ($(du -sh "$FW_DIR/$NAME.xcframework" | cut -f1))"
    echo ""
    echo "  切片清单:"
    SLICES=$(plutil -extract AvailableLibraries json -o - "$FW_DIR/$NAME.xcframework/Info.plist" | \
    python3 -c "
import json,sys
for lib in json.load(sys.stdin):
    variant = lib.get('SupportedPlatformVariant','')
    print('   ', ' '.join(lib['SupportedArchitectures']), lib['SupportedPlatform'], variant)")
    echo "$SLICES"
else
    copy_framework() { # copy_framework <平台> <源目录> <目标子目录名>  —— 只拷本次指定平台的切片
        local src="examples/$2/$NAME.framework" dst="$FW_DIR/$NAME-Frameworks/$3"
        [[ " ${PLATS[*]} " == *" $1 "* ]] || return 0
        [[ -d "$src" ]] || return 0
        rm -rf "$dst"; mkdir -p "$dst"
        cp -R "$src" "$dst/"
        echo "    ✔ $dst/$NAME.framework  ($(lipo -info "$dst/$NAME.framework/$NAME" | sed 's/.*: //'))"
    }
    # 散包目录整体清空重建，保证内容精确对应本次构建(不残留上次其他平台的陈旧切片)
    rm -rf "$FW_DIR/$NAME-Frameworks"; mkdir -p "$FW_DIR/$NAME-Frameworks"
    copy_framework ios  ios/Release-iphoneos         ios-device
    [[ "$SIMULATOR" == "1" ]] && copy_framework ios  ios/Release-iphonesimulator  ios-simulator
    copy_framework tvos tvos/Release-appletvos       tvos-device
    [[ "$SIMULATOR" == "1" ]] && copy_framework tvos tvos/Release-appletvsimulator tvos-simulator
    copy_framework macos macos/Release                macos
    SLICES="散装 framework 见 $FW_DIR/$NAME-Frameworks/"
fi

# 预编译依赖库软链(ffmpeg/ass 等实际在源码仓内，软链便于一眼找到；不复制以免占双倍磁盘)
LN_DIR="$OUTPUT_ROOT/$NAME/预编译依赖库"
rm -rf "$LN_DIR"; ln -s "$WORKDIR/FFToolChain/build/product" "$LN_DIR"

# Xcode工程软链：编译用的工程实际生成在源码仓根目录(每次构建自动重生成)，工作区放入口便于双击打开浏览/修改/IDE构建
PROJ_DIR="$OUTPUT_ROOT/$NAME/Xcode工程"
mkdir -p "$PROJ_DIR"
rm -rf "$PROJ_DIR/$NAME.xcodeproj"
ln -s "$WORKDIR/$NAME.xcodeproj" "$PROJ_DIR/$NAME.xcodeproj"

# 构建信息
# 模块名说明按深度改名状态生成(开启=类名/日志/文件等全部为新前缀，关闭=仅换框架名)
if [[ "$RENAME_SYMBOLS" == "1" ]]; then
    _PREFIX_LOWER="$(echo "$SYMBOL_PREFIX" | tr '[:upper:]' '[:lower:]')"
    SYMBOL_DESC="模块名(import用): ${NAME} (深度改名已开启：类名/日志/文件名等均为 ${SYMBOL_PREFIX} 前缀，如 ${SYMBOL_PREFIX}Player/${SYMBOL_PREFIX}Options；小写工具函数为 ${_PREFIX_LOWER} 前缀)"
else
    SYMBOL_DESC="模块名(import用): ${NAME} (类名保持 FS 前缀，如 FSPlayer/FSOptions)"
fi

cat > "$FW_DIR/构建信息.txt" << INFO
产物名称: $NAME
构建时间: $(date '+%Y-%m-%d %H:%M:%S')
FSPlayer 版本: $DESCRIBE (commit $COMMIT)
源码仓库: $REPO
FFmpeg: 随仓库配置($LIBS)，产物见 ../预编译依赖库/
输出类型: $TYPE
平台: $PLATFORMS (含模拟器: $SIMULATOR)
${SYMBOL_DESC}
切片:
$SLICES
INFO

# 工作区说明(仅首次生成，不覆盖用户可能改过的版本)
WS_README="$OUTPUT_ROOT/$NAME/README.md"
if [[ ! -f "$WS_README" ]]; then
# 脚本与说明文档的实际位置(动态引用，脚本挪到哪里 README 里的路径就指向哪里)
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
DOC_PATH="$(cd "$(dirname "$0")" && pwd)/IJKPlayerKit自编译使用说明.md"
cat > "$WS_README" << README
# 工作区说明

- \`FSPlayer/\` —— FSPlayer 源码仓库(git)。**想改播放器内核代码在这里改**（如 ijkmedia/ 下的 C 源码、渲染层等）
- \`Xcode工程/\` —— 编译用的 Xcode 工程入口(软链到源码仓内自动生成的工程)，双击即可在 IDE 里浏览代码、修改、构建
- \`Frameworks/\` —— 编译产物与构建信息(含模块名/符号前缀等关键信息)
- \`预编译依赖库/\` —— 软链，指向源码内 FFToolChain/build/product（ffmpeg/ass 等官方预编译包的实际位置）

## 修改代码后重新编译

\`\`\`bash
# 1. 在 FSPlayer/ 里修改源码
# 2. 重跑构建脚本(会自动检测到本地修改并保留，跳过版本更新)：
bash "${SCRIPT_PATH}" -y
# 3. 产物在 Frameworks/

# 放弃自己的修改、回到上游状态(之后务必重跑一次构建脚本，让源码改名与Xcode工程重新对齐)：
cd FSPlayer && git checkout -- . && git clean -fd
\`\`\`

## 换名字 / 换符号前缀 / 换版本 / 只出某平台

\`\`\`bash
bash "${SCRIPT_PATH}" -n NewName -x MR -v 1.0.9 -p ios -t framework -y
# -n 框架名(import模块名)  -x 符号前缀(类名如 FSPlayer→MRPlayer，fs_hls→mr_hls)  -d 0 可关闭深度改名
\`\`\`

详细说明见 ${DOC_PATH}
README
fi

echo ""
echo "==================== ✅ 构建完成 ===================="
echo "工作区: $OUTPUT_ROOT/$NAME/"
echo "  ├── FSPlayer/        源码(改代码在这里)"
echo "  ├── Xcode工程/        编译工程入口(双击 $NAME.xcodeproj 可在IDE浏览/构建)"
echo "  ├── Frameworks/      产物(见构建信息.txt)"
echo "  └── 预编译依赖库/     ffmpeg/ass 等预编译包(软链)"
if [[ "$RENAME_SYMBOLS" == "1" ]]; then
    echo "模块名(import用): $NAME  |  符号前缀: $SYMBOL_PREFIX(类名如 ${SYMBOL_PREFIX}Player)与${SYMBOL_PREFIX_LOWER}_小写工具函数"
else
    echo "模块名(import用): $NAME  |  类名保持 FS 前缀(FSPlayer/FSOptions/...)"
fi
echo "验证模块名: head -1 $FW_DIR/$NAME.xcframework/ios-arm64/$NAME.framework/Modules/module.modulemap 2>/dev/null"
