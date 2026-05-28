#!/usr/bin/env bash
# ┌─────────────────────────────────────────────────────────────────┐
# │  Run — macOS (Apple Silicon) 智能安装脚本                        │
# │  先安装 Run，再检查并安装 Git / Node.js                          │
# │  用法: curl -fsSL https://raw.githubusercontent.com/RunhuaHuang/Run-Releases/main/install.sh | bash │
# └─────────────────────────────────────────────────────────────────┘
set -euo pipefail

# ══════════════════════════════════════════════════════════════════
# !! 稳定安装入口配置（仅安装协议变化时才需要更新） !!
# ══════════════════════════════════════════════════════════════════
GITHUB_OWNER="RunhuaHuang"
GITHUB_REPO="Run-Releases"
GITHUB_RELEASES_BASE="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases"
MAC_FALLBACK_URL="https://ug.link/piercehome/filemgr/share-download/?id=3ad35dc82660496488fb6ca44de1ea34"

# GitHub 代理前缀（无代理用户回退用）。GitHub 直连不通时，按顺序探测，
# 取第一个可用的，之后所有 github.com 下载都套上该前缀。
# 这些是第三方公共代理，仅作兜底，可能不定期失效，失效时更新此列表即可。
GH_PROXIES=(
  "https://ghproxy.com"
  "https://ghfast.top"
  "https://gh-proxy.com"
  "https://gh.ddlc.top"
)
# 运行时确定：空=直连 GitHub；非空=代理前缀（形如 https://ghfast.top）
GH_PROXY=""
NODE_VERSION="24.15.0"
NODE_PKG_NAME="node-v${NODE_VERSION}.pkg"
NODE_RELEASE_TAG="bootstrap"
NODE_PKG_URL="${GITHUB_RELEASES_BASE}/download/${NODE_RELEASE_TAG}/${NODE_PKG_NAME}"
NODE_PKG_SHA256="179cdd07168002ed8395ed63d43dc12e4ac1ab8d375f608eabfb9aff2706ff53"
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
    echo -e "  ${YELLOW}网络提示：请确保网络连接正常后重试${RESET}"
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
trap '_spinner_stop; [[ -n "${TMP_DIR:-}" ]] && rm -rf "$TMP_DIR" 2>/dev/null || true' EXIT

_download_with_progress() {
  local url="$1" output="$2" label="$3"
  echo ""
  _info "$label"
  curl --fail --location --progress-bar \
    --output "$output" \
    "$url" \
    || _fail "下载失败，请检查网络" "network"
  echo ""
}

_check_github_access() {
  curl --fail --location --silent --show-error \
    --output /dev/null \
    --max-time 20 \
    "https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest"
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

# GitHub 直连失败时调用：按顺序探测代理，找到第一个能拉到 latest-mac.yml 的就用它。
# 成功设置 GH_PROXY 并返回 0；全部不可用返回 1。
_select_gh_proxy() {
  local probe="${GITHUB_RELEASES_BASE}/latest/download/latest-mac.yml"
  local proxy
  for proxy in "${GH_PROXIES[@]}"; do
    if curl --fail --location --silent --show-error \
        --output /dev/null --max-time 15 \
        "${proxy}/${probe}"; then
      GH_PROXY="$proxy"
      return 0
    fi
  done
  return 1
}

_show_github_fallback() {
  echo ""
  echo -e "  ${YELLOW}${BOLD}无法连接 GitHub。${RESET}"
  echo -e "  ${YELLOW}请先尝试开启代理/VPN 后重新运行此脚本。${RESET}"
  echo ""
  echo -e "  ${DIM}如果没有代理，请改用备用手动安装方式：${RESET}"
  echo -e "    1. 打开：${BLUE}${MAC_FALLBACK_URL}${RESET}"
  echo -e "    2. 下载并安装里面的两个安装包：${GRAY}Run${RESET} 和 ${GRAY}Node.js${RESET}"
  echo -e "    3. 安装完成后，在终端执行：${GRAY}xcode-select --install${RESET}"
  echo -e "    4. 再执行：${GRAY}xattr -dr com.apple.quarantine /Applications/Run.app${RESET}"
  echo -e "    5. 最后执行：${GRAY}open /Applications/Run.app${RESET}"
  echo ""
  exit 1
}

# 从稳定的 latest-mac.yml 读取最新版本号（直连/代理通用，不依赖重定向解析）。
# 返回形如 v0.10.12。
_resolve_latest_release_tag() {
  local yml_url ver
  yml_url=$(_gh "${GITHUB_RELEASES_BASE}/latest/download/latest-mac.yml")
  ver=$(curl --fail --location --silent --show-error --max-time 20 "$yml_url" \
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

# 从 latest-mac.yml 中取出指定资产名对应的 base64 sha512。
_get_asset_sha512() {
  local asset="$1" yml_url
  yml_url=$(_gh "${GITHUB_RELEASES_BASE}/latest/download/latest-mac.yml")
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

_spinner_start "正在检测 GitHub 连通性..."
if _check_github_access; then
  _spinner_stop
  _ok "GitHub 连通性正常（直连下载）"
else
  _spinner_stop
  _warn "GitHub 直连失败，正在尝试国内代理通道..."
  _spinner_start "正在探测可用代理..."
  if _select_gh_proxy; then
    _spinner_stop
    _ok "已启用代理通道：${GH_PROXY}"
    _warn "代理为第三方公共服务，速度可能较慢，请耐心等待。"
  else
    _spinner_stop
    _show_github_fallback
  fi
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
ASSET_SHA512=$(_get_asset_sha512 "$ASSET_NAME")
_ok "最新版本：${BOLD}${VERSION}${RESET}"
_ok "安装包：${ASSET_NAME}"

# ══════════════════════════════════════════════════════════════════
# STEP 3 — 下载并安装 Run
# ══════════════════════════════════════════════════════════════════
_step "下载并安装 Run"

TMP_DIR="${TMP_DIR:-$(mktemp -d)}"
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

# 挂载 DMG
MOUNT_POINT=$(mktemp -d)
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

if [[ -d "${INSTALL_DIR}/${APP_NAME}.app" ]]; then
  _spinner_start "移除旧版本..."
  rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
  _spinner_stop
  _ok "旧版本已移除"
fi

_spinner_start "正在安装（约需几秒）..."
cp -Rf "$APP_SRC" "${INSTALL_DIR}/"
_spinner_stop
_ok "已安装到 ${INSTALL_DIR}/${APP_NAME}.app"

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

  TMP_DIR="${TMP_DIR:-$(mktemp -d)}"
  NODE_PKG_PATH="${TMP_DIR}/${NODE_PKG_NAME}"

  _badge_gh "从固定公开链接下载 Node.js v${NODE_VERSION}..."
  _download_with_progress "$(_gh "$NODE_PKG_URL")" "$NODE_PKG_PATH" "正在下载 ${NODE_PKG_NAME}"

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
