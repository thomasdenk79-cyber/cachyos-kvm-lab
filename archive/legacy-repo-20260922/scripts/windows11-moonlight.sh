#!/usr/bin/env bash
set -Eeuo pipefail
HOST="${MOONLIGHT_HOST:-192.168.122.199}"
APP="${MOONLIGHT_APP:-Desktop}"
BITRATE="${MOONLIGHT_BITRATE:-50000}"
command -v moonlight >/dev/null || { echo 'moonlight-qt is not installed' >&2; exit 1; }
exec moonlight stream --1080 --fps 60 --bitrate "$BITRATE" \
  --display-mode windowed --audio-on-host --absolute-mouse --frame-pacing \
  "$HOST" "$APP"
