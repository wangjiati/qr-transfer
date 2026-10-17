#!/usr/bin/env bash
# 无头浏览器运行 qr-transfer.html 的 #test 自测
set -u
CHROME="${CHROME:-}"
if [ -z "$CHROME" ]; then
  for p in \
    "/c/Program Files/Google/Chrome/Application/chrome.exe" \
    "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
    "/c/Program Files/Microsoft/Edge/Application/msedge.exe" \
    "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"; do
    [ -f "$p" ] && CHROME="$p" && break
  done
fi
if [ -z "$CHROME" ]; then
  echo "未找到 Chrome/Edge，请设置 CHROME 环境变量，或手动打开 qr-transfer.html#test"
  exit 2
fi
DIR="$(cd "$(dirname "$0")/.." && pwd -W 2>/dev/null || pwd)"
OUT="$("$CHROME" --headless=new --disable-gpu --virtual-time-budget=20000 --dump-dom "file:///${DIR}/qr-transfer.html#test" 2>/dev/null)"
echo "$OUT" | grep -oE 'TEST-SUMMARY: [^<]*' || echo "未找到 TEST-SUMMARY（页面可能未运行）"
echo "$OUT" | grep -oE '<div class="fail">[^<]*' || true
if echo "$OUT" | grep -q 'TEST-SUMMARY: ALL PASS'; then echo "PASS"; exit 0; else echo "FAIL"; exit 1; fi
