#!/bin/bash
# IJKPlayerKit.sh 自动下载脚本
# 用途：自动下载解压远程资源
# 作者：官人
#
# 默认行为如下：
#   - 如果 ZIP_PATH 存在，则直接解压使用(解压后不删除压缩包)，否则就执行下载逻辑
#   - 如果脚本文件中没有记录下载时间戳，强制下载；
#   - 如果距离上次下载已超过 MAX_INTERVAL_HOURS 小时，强制重新下载；
#   - 如果传入的本地路径下的文件夹不存在，也会强制下载；
#   - 其他情况则跳过下载。
#
# 终端调试方式(在 脚本目录 下执行)：
#   bash IJKPlayerKit.sh
#
# 更新时间戳的方式：直接更新脚本文件中的 # LAST_DOWNLOAD_TIMESTAMP=xxx 注释行。

# ————— 脚本配置 ————— #
[[ $1 == "--debug" ]] && set -x      # 可手动添加参数开启调试日志
set -e                               # 遇到错误立即退出
export LC_ALL=en_US.UTF-8            # 强制 UTF-8 避免 printf 中文乱码
export LANG=en_US.UTF-8

TARGETNAME="IJKPlayerKit"            # 要下载的资源的名字
SCRIPT_PATH="${BASH_SOURCE[0]}"      # 当前脚本路径（用于更新时间戳）
FRAMEWORK_DIR="./$TARGETNAME"        # 解压后的目标目录
ZIP_URL="https://github.com/aiguanren/IJKPlayerKit/releases/download/1.0.0/IJKPlayerKit.zip"  # 下载链接
ZIP_PATH="./$TARGETNAME.zip"         # ZIP 包保存路径
UNZIP_TEMP_DIR="$FRAMEWORK_DIR/__temp__"                # 解压临时目录
MAX_INTERVAL_HOURS=0                 # 最大允许的间隔时间（小时）超过则强制重新下载（<=0 表示无限大）

printf '⏩ 当前路径: %s\n' "$(pwd)"

# ————— 如果本地存在 TARGETNAME.zip 则跳过下载(直接解压) ————— #
if [[ -f "$ZIP_PATH" ]]; then
  printf '💼 检测到 %s 已存在，解压中...\n' "$ZIP_PATH"
  rm -rf "$FRAMEWORK_DIR"
  mkdir -p "$FRAMEWORK_DIR"
  unzip -o -q "$ZIP_PATH" -d "$UNZIP_TEMP_DIR"
  mv "$UNZIP_TEMP_DIR/$TARGETNAME/"* "$FRAMEWORK_DIR/"
  rm -rf "$UNZIP_TEMP_DIR" "$FRAMEWORK_DIR/__MACOSX"
  printf '✅ 解压成功，路径：%s\n' "$FRAMEWORK_DIR"
  exit 0
fi

# ————— 判断本地 TARGETNAME 是否存在 ————— #
if [[ ! -d "$FRAMEWORK_DIR" ]]; then
  LOCAL_EXIST=false     # 不存在则标记为 false
else
  LOCAL_EXIST=true      # 存在则标记为 true
fi

# ————— 读取上次下载时间戳 ————— #
LAST_LINE=$(grep "^# LAST_DOWNLOAD_TIMESTAMP=" "$SCRIPT_PATH" || true)   # 查找脚本中记录的时间戳注释行
LAST_TS=0                                                                # 默认时间戳为 0
[[ $LAST_LINE =~ =([0-9]+)$ ]] && LAST_TS=${BASH_REMATCH[1]}             # 如果匹配到时间戳就提取出来

CURRENT_TS=$(date +%s)                             # 当前时间戳（单位秒）
DIFF_SECS=$(( CURRENT_TS - LAST_TS ))              # 与上次下载间隔秒数
DIFF_HOURS=$(( DIFF_SECS / 3600 ))                 # 小时
DIFF_MINUTES=$(( (DIFF_SECS % 3600) / 60 ))        # 分钟

# ————— 判断是否需要下载 ————— #
NEED_DOWNLOAD=false                                 # 默认不需要下载
if [[ $LAST_TS -eq 0 ]]; then
  NEED_DOWNLOAD=true
  printf '🔍 未检测到 %s 下载记录\n' "$TARGETNAME"
elif [[ "$LOCAL_EXIST" = false ]]; then
  NEED_DOWNLOAD=true
  printf '🔍 本地未发现 %s\n' "$TARGETNAME"
elif [[ $MAX_INTERVAL_HOURS -gt 0 && $DIFF_HOURS -ge $MAX_INTERVAL_HOURS ]]; then
  NEED_DOWNLOAD=true
  printf '⏰ 本地已存在 %s，但距离上次下载时间间隔已超过 %s小时%s分(默认间隔时间为%s小时)\n' \
         "$TARGETNAME" "$DIFF_HOURS" "$DIFF_MINUTES" "$MAX_INTERVAL_HOURS"
fi

if ! $NEED_DOWNLOAD; then
  if [[ $MAX_INTERVAL_HOURS -le 0 ]]; then
    printf '💼 本地已存在 %s，且已设置为无限间隔模式（MAX_INTERVAL_HOURS<=0），本次无需下载\n' "$TARGETNAME"
  else
    printf '💼 本地已存在 %s，且距离上次下载时间间隔不超过 %s 小时（当前间隔 %s小时%s分），本次无需下载\n' \
           "$TARGETNAME" "$MAX_INTERVAL_HOURS" "$DIFF_HOURS" "$DIFF_MINUTES"
  fi
  exit 0
fi

# ————— 执行下载与解压 ————— #
printf '🚀 开始下载 %s\n' "$TARGETNAME"

rm -rf "$FRAMEWORK_DIR"               # 删除旧的 TARGETNAME
mkdir -p "$FRAMEWORK_DIR"             # 新建 TARGETNAME 目录

curl -sSL -o "$ZIP_PATH" "$ZIP_URL"   # 下载 ZIP 包到指定位置（静默模式）
unzip -o -q "$ZIP_PATH" -d "$UNZIP_TEMP_DIR"   # 解压到临时目录
mv "$UNZIP_TEMP_DIR/$TARGETNAME/"* "$FRAMEWORK_DIR/"  # 移动文件到目标目录

rm -rf "$UNZIP_TEMP_DIR" "$FRAMEWORK_DIR/__MACOSX" "$ZIP_PATH"   # 清理临时文件和 TARGETNAME.zip（仅下载的 TARGETNAME.zip 会被删）

# ————— 更新时间戳到脚本文件中 ————— #
if grep -q "^# LAST_DOWNLOAD_TIMESTAMP=" "$SCRIPT_PATH"; then
  # 若已有时间戳行，直接替换为当前时间戳（macOS 用法）
  sed -i '' "s/^# LAST_DOWNLOAD_TIMESTAMP=.*/# LAST_DOWNLOAD_TIMESTAMP=$CURRENT_TS/" "$SCRIPT_PATH"
else
  # 否则，在文件末尾追加一个新的时间戳行
  printf "\n# LAST_DOWNLOAD_TIMESTAMP=%s\n" "$CURRENT_TS" >> "$SCRIPT_PATH"
fi

printf '✅ %s下载完成（已更新/记录本次下载时间戳到当前脚本文件中）\n' "$TARGETNAME"

# LAST_DOWNLOAD_TIMESTAMP=1755259584
