#!/usr/bin/env bash
# ┌─────────────────────────────────────────────────────────────────┐
# │  Run — macOS (Apple Silicon) 智能安装脚本                        │
# │  先安装 Run，再检查并安装 Git / Node.js                          │
# │  有 VPN（直连）:                                                   │
# │    curl -fsSL https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.sh | bash │
# │  无 VPN（走 gh-proxy.com 代理）:                                    │
# │    curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.sh | RUN_GH_PROXY=https://gh-proxy.com bash │
# └─────────────────────────────────────────────────────────────────┘
set -euo pipefail

# ══════════════════════════════════════════════════════════════════
# !! 稳定安装入口配置（仅安装协议变化时才需要更新） !!
# ══════════════════════════════════════════════════════════════════
GITHUB_OWNER="RunhuaHuang"
GITHUB_REPO="Run-Releases"
GITHUB_RELEASES_BASE="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases"
# raw.githubusercontent.com 上的 VERSION 文件：版本号发现的通用通道。
# 三家代理（gh-proxy.com / ghfast.top / ghproxy.net）都能代理 raw 与「带版本号的」
# 资产下载，但只有前两家能代理 /releases/latest/download 的重定向链（ghproxy.net 会 502），
# 所以版本发现一律走 raw VERSION，资产下载一律走 /releases/download/vX.Y.Z/ 带版本号路径。
GITHUB_RAW_BASE="https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/main"
MAC_FALLBACK_URL="https://ug.link/piercehome/filemgr/share-download/?id=3ad35dc82660496488fb6ca44de1ea34"

# GitHub 代理前缀：由用户选择的安装命令决定，脚本内部不再做连通性探测。
# 实测发现国内不挂代理有时也能连上 GitHub（能过连通性测试）但速度极慢，
# 探测会被这种「能连但龟速」的情况骗过，所以改为「用哪条命令走哪条路」：
#   - 直连命令：不设 RUN_GH_PROXY        → 全程直连 GitHub（适合有 VPN/能直连的用户）
#   - 代理命令：RUN_GH_PROXY=https://gh-proxy.com → 所有 github.com 下载都套此前缀（适合无 VPN 用户）
GH_PROXY="${RUN_GH_PROXY:-}"
# Node.js 安装包：走清华 TUNA 镜像（镜像 nodejs.org 官方分发，国内直连极速），
# SHA256 与官方 SHASUMS256.txt 完全一致，不再依赖 nodejs.org 直连、GitHub Releases 与 gh-proxy 代理。
NODE_VERSION="24.1.0"
NODE_PKG_NAME="node-v${NODE_VERSION}.pkg"
NODE_PKG_URL="https://mirrors.tuna.tsinghua.edu.cn/nodejs-release/v${NODE_VERSION}/${NODE_PKG_NAME}"
NODE_PKG_SHA256="623b7a5fd6886dcfff8aa360b268a7f5031ec1a8a363b30173c0033c96948100"
APP_NAME="Run"
INSTALL_DIR="/Applications"

# ══════════════════════════════════════════════════════════════════
# 颜色 & 格式
# ══════════════════════════════════════════════════════════════════
BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; GRAY='\033[0;37m'; BLUE='\033[0;34m'

# ══════════════════════════════════════════════════════════════════
# 工具函数
# ══════════════════════════════════════════════════════════════════
STEP=0; TOTAL=6

_step() {
  STEP=$((STEP + 1))
  echo ""
  echo -e "${BOLD}${CYAN}  [$STEP/$TOTAL] $1${RESET}"
}
_ok()       { echo -e "    ${GREEN}✓${RESET}  ${GRAY}$1${RESET}"; }
_info()     { echo -e "    ${BLUE}→${RESET}  ${GRAY}$1${RESET}"; }
_warn()     { echo -e "    ${YELLOW}⚠${RESET}  ${YELLOW}$1${RESET}"; }
_badge_gh() { echo -e "    ${BOLD}${BLUE}[ GitHub ]${RESET}  ${GRAY}$1${RESET}"; }
_badge_r2() { echo -e "    ${BOLD}${GREEN}[ Cloudflare R2 ]${RESET}  ${GRAY}$1${RESET}"; }
_fail() {
  echo ""
  echo -e "  ${RED}${BOLD}✗  $1${RESET}"
  if [[ "${2:-}" == "network" ]]; then
    echo ""
    if [[ -n "$GH_PROXY" ]]; then
      echo -e "  ${YELLOW}已在使用代理通道（${GH_PROXY}）仍失败，请检查网络后重试。${RESET}"
    else
      echo -e "  ${YELLOW}直连 GitHub 失败。若你在国内且没有 VPN，请改用「无 VPN」的代理安装命令（见 README）。${RESET}"
    fi
    echo -e "  ${DIM}仍不行可用手动备用方式：${BLUE}${MAC_FALLBACK_URL}${RESET}"
  fi
  echo ""
  [[ -n "${TMP_DIR:-}" ]] && rm -rf "$TMP_DIR" 2>/dev/null || true
  exit 1
}

SPINNER_PID=""
_spinner_start() {
  local msg="$1"
  ( local s='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
    while true; do
      i=$(( (i+1) % 10 ))
      printf "\r    ${CYAN}${s:$i:1}${RESET}  ${GRAY}${msg}${RESET}   "
      sleep 0.08
    done
  ) &
  SPINNER_PID=$!
}
_spinner_stop() {
  [[ -n "$SPINNER_PID" ]] || return
  kill "$SPINNER_PID" 2>/dev/null || true
  wait "$SPINNER_PID" 2>/dev/null || true
  SPINNER_PID=""; printf "\r\033[K"
}
DL_CURL_PID=""
DL_HEADER_FILE=""
_cleanup_resources() {
  _spinner_stop
  if [[ -n "${DL_CURL_PID:-}" ]]; then
    kill "$DL_CURL_PID" 2>/dev/null || true
    wait "$DL_CURL_PID" 2>/dev/null || true
    DL_CURL_PID=""
  fi
  [[ -n "${DL_HEADER_FILE:-}" ]] && rm -f "$DL_HEADER_FILE" 2>/dev/null || true
  if [[ "${KEEP_DOWNLOADS:-0}" != "1" && -n "${TMP_DIR:-}" ]]; then
    rm -rf "$TMP_DIR" 2>/dev/null || true
  fi
}
trap '_cleanup_resources' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 字节数 → 人类可读（B/KB/MB/GB，≥1KB 取小数 1 位）。用 awk 处理浮点，兼容 bash 3.2。
_fmt_bytes() {
  awk -v b="$1" 'BEGIN{
    if (b+0 < 0) {print "0 B"; exit}
    split("B KB MB GB TB", u, " ")
    i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    if (i == 1) printf "%d %s", b, u[i]
    else        printf "%.1f %s", b, u[i]
  }'
}

# 子秒级时间戳（秒，浮点）。perl 的 Time::HiRes 是 macOS 自带 perl 的标准模块，
# 最稳；date +%s.%N 作为兜底（BSD date 亦支持子秒）。
_now() {
  perl -MTime::HiRes=time -e 'printf "%.3f\n", time' 2>/dev/null \
    || date +%s.%N
}

# curl 后台下载 + 前台轮询文件大小，算实时速度 / 已下载 / 总量 / 百分比，单行 \r 刷新。
# 与 Windows 版 Download-File 的展示对齐：percent% (have / total)  speed。
_download_with_progress() {
  local url="$1" output="$2" label="$3"
  echo ""
  _info "$label"

  # 用全局变量记录 header 临时文件路径，使顶层 EXIT trap 能在中断时一并回收。
  DL_HEADER_FILE="$(mktemp -t run-hdr)"
  local header_file="$DL_HEADER_FILE"
  # 后台拉取：--dump-header 抓响应头以获取 Content-Length（重定向跟随取最后一个值），
  # --silent 关闭 curl 自带进度输出。
  ( curl --fail --location --silent --show-error \
        --dump-header "$header_file" \
        --output "$output" \
        "$url" ) &
  local curl_pid=$!

  local total=0 have=0 pct=0 speed=0
  local t0 t_prev prev_have
  t0=$(_now); t_prev=$t0; prev_have=0
  DL_CURL_PID="$curl_pid"

  # 轮询落盘文件大小，刷新单行进度。
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' si=0
  while kill -0 "$curl_pid" 2>/dev/null; do
    have=$(stat -f%z "$output" 2>/dev/null || echo 0)
    si=$(( (si + 1) % 10 ))
    local t_now win
    t_now=$(_now)
    win=$(awk -v a="$t_prev" -v b="$t_now" 'BEGIN{printf "%.3f", b-a}')

    # 速度：基于近 0.5s 窗口的增量算瞬时速度，避免长窗口被平均拉低。
    if awk -v w="$win" 'BEGIN{exit !(w+0 >= 0.5)}'; then
      local dl=$(( have - prev_have ))
      [[ $dl -lt 0 ]] && dl=0
      speed=$(awk -v d="$dl" -v w="$win" 'BEGIN{printf "%.1f", (w+0>0)?d/w:0}')
      prev_have=$have; t_prev=$t_now
    fi

    # 响应头可能稍后才写入；下载期间持续尝试解析 Content-Length。
    if [[ $total -eq 0 ]] && [[ -s "$header_file" ]]; then
      total=$(awk 'tolower($0) ~ /^content-length:/{
        v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); sub(/\r/,"",v); print v
      }' "$header_file" | tail -1 | tr -dc '0-9')
      total=${total:-0}
    fi

    local spd="$(_fmt_bytes "$speed")/s"
    if [[ $total -gt 0 ]]; then
      pct=$(awk -v h="$have" -v t="$total" 'BEGIN{
        p = (t+0 > 0) ? (h / t * 100) : 0
        if (p > 100) p = 100
        printf "%d", p
      }')
      printf "\r    ${CYAN}${spin:$si:1}${RESET}  ${GRAY}%3d%%  %s / %s   ${BOLD}%s${RESET}    " \
        "$pct" "$(_fmt_bytes "$have")" "$(_fmt_bytes "$total")" "$spd" 2>/dev/null || true
    else
      printf "\r    ${CYAN}${spin:$si:1}${RESET}  ${GRAY}已下载 %s   ${BOLD}%s${RESET}    " \
        "$(_fmt_bytes "$have")" "$spd" 2>/dev/null || true
    fi
    sleep 0.1
  done

  # 下载结束：收尾取最终大小 + 总耗时平均速度。
  wait "$curl_pid" || { DL_CURL_PID=""; rm -f "$header_file"; DL_HEADER_FILE=""; _fail "下载失败，请检查网络" "network"; }
  DL_CURL_PID=""
  have=$(stat -f%z "$output" 2>/dev/null || echo 0)
  local t_end total_elapsed final_speed
  t_end=$(_now)
  total_elapsed=$(awk -v a="$t0" -v b="$t_end" 'BEGIN{d=b-a; if(d<0.001)d=0.001; printf "%.3f", d}')
  final_speed=$(awk -v h="$have" -v e="$total_elapsed" 'BEGIN{printf "%.1f", h / e}')
  rm -f "$header_file"; DL_HEADER_FILE=""

  printf "\r\033[K"
  if [[ $total -gt 0 ]]; then
    _ok "下载完成（$(_fmt_bytes "$have")，平均 $(_fmt_bytes "$final_speed")/s）"
  else
    _ok "下载完成（$(_fmt_bytes "$have")，平均 $(_fmt_bytes "$final_speed")/s）"
  fi
}

# 把一个 github.com 下载链接按需套上代理前缀。
# GH_PROXY 为空时原样返回（直连）。
_gh() {
  if [[ -n "$GH_PROXY" ]]; then
    echo "${GH_PROXY}/$1"
  else
    echo "$1"
  fi
}

# 读取最新版本号。优先走 raw 上的 VERSION 文件（三家代理通用），
# 失败时回退到 /releases/latest/download/latest-mac.yml（直连及 gh-proxy.com/ghfast.top 可用）。
# 返回形如 v0.10.18。
_resolve_latest_release_tag() {
  local ver
  # 通道一：raw VERSION 文件（最稳，所有代理都能代理 raw）
  ver=$(curl --fail --location --silent --show-error --max-time 20 \
    "$(_gh "${GITHUB_RAW_BASE}/VERSION")" 2>/dev/null \
    | head -1 | tr -d '[:space:]')
  if [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "v${ver}"; return 0
  fi
  # 通道二：回退到 latest-mac.yml 的 version 字段
  ver=$(curl --fail --location --silent --show-error --max-time 20 \
    "$(_gh "${GITHUB_RELEASES_BASE}/latest/download/latest-mac.yml")" 2>/dev/null \
    | grep -E '^version:' | head -1 | awk '{print $2}' | tr -d '\r')
  [[ -n "$ver" ]] || _fail "无法解析最新版本号" "network"
  echo "v${ver}"
}

_verify_sha256() {
  local file="$1" expected="$2" actual
  actual=$(shasum -a 256 "$file" | awk '{print $1}')
  [[ "$actual" == "$expected" ]] || _fail "文件校验失败：$(basename "$file")"
}

# 校验文件的 base64 编码 sha512（与 latest-mac.yml 中的格式一致）。
_verify_sha512_b64() {
  local file="$1" expected="$2" actual
  actual=$(openssl dgst -sha512 -binary "$file" | openssl base64 -A)
  [[ "$actual" == "$expected" ]] || _fail "文件校验失败：$(basename "$file")（完整性校验不通过，可能下载被篡改或损坏）"
}

# 从指定版本的 latest-mac.yml 中取出指定资产名对应的 base64 sha512。
# 用带版本号的路径（/releases/download/vX.Y.Z/latest-mac.yml），三家代理通用。
_get_asset_sha512() {
  local asset="$1" version="$2" yml_url
  yml_url=$(_gh "${GITHUB_RELEASES_BASE}/download/${version}/latest-mac.yml")
  curl --fail --location --silent --show-error --max-time 20 "$yml_url" \
    | awk -v name="$asset" '
        $1=="-" && $2=="url:" { cur=$3; next }
        $1=="sha512:" && cur==name { print $2; exit }
      '
}

# 从 tty 读取用户输入（即使是 curl | bash 场景也能工作）
_wait_for_enter() {
  local msg="${1:-请完成操作后按 [Enter] 继续...}"
  echo -e "    ${YELLOW}⏎  ${msg}${RESET}"
  read -r </dev/tty 2>/dev/null || sleep 3
}

_prompt_keep_downloads() {
  local prompt="${1:-是否保留本次下载的安装包？[直接回车=自动删除，输入 k 再回车=保留]}"
  if [[ ! -t 0 && ! -r /dev/tty ]]; then
    return 1
  fi
  echo ""
  echo -e "    ${DIM}直接按 Enter：自动删除本次下载的安装包（推荐）${RESET}"
  echo -e "    ${DIM}输入 k 后回车：保留安装包，便于排障或手动重装${RESET}"
  echo -e "    ${DIM}${prompt}${RESET}"
  local reply=""
  read -r reply </dev/tty 2>/dev/null || reply=""
  [[ "$reply" =~ ^[Kk]$ ]]
}

# ══════════════════════════════════════════════════════════════════
# 页眉
# ══════════════════════════════════════════════════════════════════
printf '\n'
echo -e "${CYAN}${BOLD}"
cat << 'LOGO'
    ██████╗ ██╗   ██╗███╗   ██╗
    ██╔══██╗██║   ██║████╗  ██║
    ██████╔╝██║   ██║██╔██╗ ██║
    ██╔══██╗██║   ██║██║╚██╗██║
    ██║  ██║╚██████╔╝██║ ╚████║
    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝
LOGO
echo -e "${RESET}${DIM}    智能 AI 桌面助理  ·  macOS 安装向导${RESET}"
echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ══════════════════════════════════════════════════════════════════
# STEP 1 — 系统检测
# ══════════════════════════════════════════════════════════════════
_step "检测系统环境"

[[ "$(uname)" == "Darwin" ]] || _fail "此安装程序仅支持 macOS（Apple Silicon）"
_ok "操作系统：macOS $(sw_vers -productVersion)"

ARCH=$(uname -m)
case "$ARCH" in
  arm64)  _ok "处理器：Apple Silicon（M 系列）"; DMG_ARCH="arm64" ;;
  x86_64) _fail "Intel Mac 已不再支持，请改用 Apple Silicon Mac 或 Windows x64" ;;
  *)      _fail "不支持的处理器架构：$ARCH" ;;
esac

command -v curl &>/dev/null || _fail "缺少 curl（请先安装 Xcode Command Line Tools）"
_ok "curl 已就绪"

# 下载通道由用户选择的命令决定（见文件头注释），不再做连通性探测。
if [[ -n "$GH_PROXY" ]]; then
  _ok "下载通道：代理（${GH_PROXY}）"
  _warn "代理为第三方公共服务，速度可能较慢，请耐心等待。"
else
  _ok "下载通道：GitHub 直连"
fi



# ══════════════════════════════════════════════════════════════════
# STEP 2 — 准备 Run 安装包
# ══════════════════════════════════════════════════════════════════
_step "准备 Run 安装包"

VERSION=$(_resolve_latest_release_tag)
[[ -n "$VERSION" ]] || _fail "无法解析最新版本号"
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  _fail "当前没有可安装的 Run 正式版本（解析到的 release: ${VERSION}）。请等待 Run-Releases 发布 vX.Y.Z 正式版本后重试。"
fi
VERSION_NUM="${VERSION#v}"
ASSET_NAME="Run-${VERSION_NUM}-${DMG_ARCH}.dmg"
ASSET_URL="${GITHUB_RELEASES_BASE}/download/${VERSION}/${ASSET_NAME}"
ASSET_SHA512=$(_get_asset_sha512 "$ASSET_NAME" "$VERSION")
_ok "最新版本：${BOLD}${VERSION}${RESET}"
_ok "安装包：${ASSET_NAME}"

# ══════════════════════════════════════════════════════════════════
# STEP 3 — 下载并安装 Run
# ══════════════════════════════════════════════════════════════════
_step "下载并安装 Run"

# 用 run-bootstrap. 前缀，方便 Run 内部"磁盘管理 → 下载/更新缓存"识别和清理；
# 显式 TMPDIR fallback /tmp 让 BSD（mac）和 GNU（linux）mktemp 都通过模板形式工作。
TMP_DIR="${TMP_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/run-bootstrap.XXXXXXXX")}"
DMG_PATH="${TMP_DIR}/${ASSET_NAME}"

echo ""
  if [[ -n "$GH_PROXY" ]]; then
    _badge_gh "通过代理（${GH_PROXY}）下载中..."
  else
    _badge_gh "从 GitHub 下载中..."
  fi
  _download_with_progress "$(_gh "$ASSET_URL")" "$DMG_PATH" "正在下载 ${ASSET_NAME}"

echo ""
[[ -s "$DMG_PATH" ]] || _fail "下载文件为空，网络可能中断，请重试"
_ok "下载完成（$(du -sh "$DMG_PATH" | cut -f1)）"

# 完整性校验：与 latest-mac.yml 中的 sha512 比对（尤其是走代理时防篡改）
if [[ -n "$ASSET_SHA512" ]]; then
  _verify_sha512_b64 "$DMG_PATH" "$ASSET_SHA512"
  _ok "安装包完整性校验通过"
else
  _warn "未能取得安装包校验值，跳过完整性校验"
fi

# 挂载 DMG（同样用 run-bootstrap- 前缀，便于 Run 内部清理识别）
MOUNT_POINT=$(mktemp -d "${TMPDIR:-/tmp}/run-bootstrap-mount.XXXXXXXX")
_spinner_start "正在挂载安装包..."
hdiutil attach "$DMG_PATH" \
  -mountpoint "$MOUNT_POINT" \
  -quiet -nobrowse -noautoopen \
  || { _spinner_stop; _fail "安装包挂载失败"; }
_spinner_stop
_ok "安装包已挂载"

APP_SRC=$(find "$MOUNT_POINT" -maxdepth 1 -name "*.app" | head -1)
[[ -n "$APP_SRC" ]] || {
  hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
  _fail "安装包内未找到应用程序"
}

APP_DEST="${INSTALL_DIR}/${APP_NAME}.app"
TMP_APP="${INSTALL_DIR}/${APP_NAME}.app.tmp.$$"
BACKUP_APP="${INSTALL_DIR}/${APP_NAME}.app.backup.$$"
rm -rf "$TMP_APP" "$BACKUP_APP" 2>/dev/null || true

_spinner_start "正在复制新版本（约需几秒）..."
cp -Rf "$APP_SRC" "$TMP_APP" || { _spinner_stop; rm -rf "$TMP_APP" 2>/dev/null || true; _fail "应用复制失败，旧版本未修改"; }
_spinner_stop

if [[ -d "$APP_DEST" ]]; then
  _spinner_start "备份旧版本..."
  mv "$APP_DEST" "$BACKUP_APP" || { _spinner_stop; rm -rf "$TMP_APP" 2>/dev/null || true; _fail "旧版本备份失败，旧版本未修改"; }
  _spinner_stop
fi

_spinner_start "正在替换应用..."
if mv "$TMP_APP" "$APP_DEST"; then
  rm -rf "$BACKUP_APP" 2>/dev/null || true
  _spinner_stop
  _ok "已安装到 ${INSTALL_DIR}/${APP_NAME}.app"
else
  [[ -d "$BACKUP_APP" ]] && mv "$BACKUP_APP" "$APP_DEST" 2>/dev/null || true
  rm -rf "$TMP_APP" 2>/dev/null || true
  _spinner_stop
  _fail "应用替换失败，已尽量恢复旧版本"
fi

hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
_ok "安装包已弹出"

# ══════════════════════════════════════════════════════════════════
# STEP 4 — 检查并安装 Git
# ══════════════════════════════════════════════════════════════════
_step "检查 Git"

if command -v git &>/dev/null; then
  _ok "Git $(git --version | awk '{print $3}') 已安装"
else
  _warn "未检测到 Git"
  echo ""
  echo -e "    ${GRAY}Run Agent 模式需要 Git，脚本现在将触发 Xcode Command Line Tools 安装。${RESET}"
  echo ""
  xcode-select --install 2>/dev/null || true
  echo ""
  echo -e "    ${YELLOW}${BOLD}请在弹出的系统对话框中点击「安装」${RESET}"
  _wait_for_enter "Git 安装完成后按 [Enter] 继续..."
  echo ""
  _spinner_start "正在验证 Git 安装..."
  local_tries=0
  while ! command -v git &>/dev/null && [[ $local_tries -lt 18 ]]; do
    sleep 5; local_tries=$((local_tries+1))
  done
  _spinner_stop
  command -v git &>/dev/null || _fail "Git 尚未安装完成。请先完成 Xcode Command Line Tools 安装后重新运行脚本。"
  _ok "Git $(git --version | awk '{print $3}') 安装成功"
fi

# ══════════════════════════════════════════════════════════════════
# STEP 5 — 检查并安装 Node.js
# ══════════════════════════════════════════════════════════════════
_step "检查 Node.js"

if command -v node &>/dev/null; then
  NODE_VER=$(node --version)
  _ok "Node.js ${NODE_VER} 已安装"
else
  _warn "未检测到 Node.js"
  echo ""
  echo -e "    ${GRAY}Run 工具链需要 Node.js，脚本现在将自动下载并安装。${RESET}"
  echo ""

  TMP_DIR="${TMP_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/run-bootstrap.XXXXXXXX")}"
  NODE_PKG_PATH="${TMP_DIR}/${NODE_PKG_NAME}"

  # 清华 TUNA 镜像本身就是国内直达，不套 _gh 代理前缀。
  _badge_r2 "从清华 TUNA 镜像下载 Node.js v${NODE_VERSION}..."
  _download_with_progress "$NODE_PKG_URL" "$NODE_PKG_PATH" "正在下载 ${NODE_PKG_NAME}"

  echo ""
  [[ -s "$NODE_PKG_PATH" ]] || _fail "Node.js 安装包下载不完整"
  _verify_sha256 "$NODE_PKG_PATH" "$NODE_PKG_SHA256"
  _ok "Node.js 安装包校验通过"

  echo ""
  echo -e "    ${YELLOW}${BOLD}安装 Node.js 需要管理员权限，请在下方输入密码：${RESET}"
  echo ""
  sudo installer -pkg "$NODE_PKG_PATH" -target / \
    || _fail "Node.js 安装失败（权限不足？）"

  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
  hash -r
  command -v node &>/dev/null || _fail "Node.js 安装完成，但当前会话仍未检测到 node，请重新打开终端后重试。"
  _ok "Node.js $(node --version) 安装成功"
fi

command -v git &>/dev/null || _fail "缺少 Git，Run 还不能正常使用。"
command -v node &>/dev/null || _fail "缺少 Node.js，Run 还不能正常使用。"

# ══════════════════════════════════════════════════════════════════
# STEP 6 — 完成配置
# ══════════════════════════════════════════════════════════════════
_step "完成配置"

xattr -dr com.apple.quarantine "${INSTALL_DIR}/${APP_NAME}.app" 2>/dev/null || true
_ok "已移除 Gatekeeper 安全隔离"

KEEP_DOWNLOADS=0
if _prompt_keep_downloads; then
  KEEP_DOWNLOADS=1
fi
if [[ "$KEEP_DOWNLOADS" -eq 1 ]]; then
  _ok "已保留下载文件：${TMP_DIR}"
else
  rm -rf "$TMP_DIR" 2>/dev/null || true
  _ok "安装包已自动删除"
fi

sleep 0.3
_info "正在首次启动 Run..."
open "${INSTALL_DIR}/${APP_NAME}.app"

# ══════════════════════════════════════════════════════════════════
# 完成页
# ══════════════════════════════════════════════════════════════════
echo ""
echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${GREEN}${BOLD}🎉  安装完成！${RESET}"
echo ""
echo -e "  ${WHITE}  Run${RESET}  ${GRAY}→ ${INSTALL_DIR}/${APP_NAME}.app${RESET}"
echo ""

# 环境汇总
echo -e "  ${DIM}已安装环境：${RESET}"
command -v git  &>/dev/null && echo -e "    ${GREEN}✓${RESET}  ${GRAY}Git  $(git --version | awk '{print $3}')${RESET}"
command -v node &>/dev/null && echo -e "    ${GREEN}✓${RESET}  ${GRAY}Node.js $(node --version)${RESET}"
echo -e "  ${DIM}下载来源：${BLUE}GitHub Releases${RESET}"
echo ""
echo -e "  ${DIM}Git 和 Node.js 已就绪，现在可以正常使用 Run。${RESET}"
echo -e "  ${DIM}后续更新由应用内自动完成，无需重新运行此脚本。${RESET}"
echo ""
