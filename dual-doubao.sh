#!/usr/bin/env bash
# =============================================================================
# 豆包多账号脚本（Linux 版）
# =============================================================================
# 重要说明：
#   豆包官方**没有 Linux 原生桌面客户端**（只有 Windows / macOS / 手机 / 网页版）。
#   因此 Linux 下只能通过浏览器访问豆包网页版 doubao.com。
#
#   本脚本利用 Chrome / Chromium 的 --user-data-dir 参数，为每个账号开一个
#   独立的浏览器配置窗口，各自登录不同账号，互不干扰。
#   原理和 Windows 版一致（Chromium 原生参数），只是载体从"豆包客户端"
#   换成了"Chrome 浏览器开网页版"。
#
# 用法：
#   ./dual-doubao.sh            # 开 2 个浏览器窗口（不同账号）
#   ./dual-doubao.sh 3          # 开 3 个
# =============================================================================
set -euo pipefail

COUNT="${1:-2}"   # 总共开几个窗口（默认 2 = 双开）
PROFILE_ROOT="${HOME}/.doubao-profiles"
DOUBAO_URL="https://www.doubao.com/chat/"

log()  { printf '\033[36m[信息]\033[0m %s\n' "$*"; }
err()  { printf '\033[31m[错误]\033[0m %s\n' "$*" >&2; }

# ---- 找浏览器 ----
BROWSER=""
for b in google-chrome google-chrome-stable chromium chromium-browser microsoft-edge; do
    if command -v "$b" >/dev/null 2>&1; then BROWSER="$b"; break; fi
done
if [[ -z "$BROWSER" ]]; then
    err "未找到 Chrome / Chromium，请先安装（如 sudo apt install chromium-browser）。"
    exit 1
fi
log "使用浏览器: $BROWSER"
log "豆包地址: $DOUBAO_URL"
log "注意: Linux 下豆包无原生桌面客户端，本脚本通过浏览器网页版实现多账号。"

mkdir -p "$PROFILE_ROOT"

# ---- 每个窗口用独立 user-data-dir，天然隔离登录态 ----
for ((i = 1; i <= COUNT; i++)); do
    prof="$PROFILE_ROOT/account-$i"
    mkdir -p "$prof"
    log "账号 $i -> 配置目录 $prof"
    "$BROWSER" --user-data-dir="$prof" --no-first-run --no-default-browser-check "$DOUBAO_URL" >/dev/null 2>&1 &
    sleep 0.5
done

log "完成。每个窗口独立登录不同豆包账号即可，首次需要登录，之后自动记住。"
