#!/usr/bin/env bash
set -Eeuo pipefail

# Responsive Windows RDP client profile. Passwords are deliberately interactive.
VM_IP="${WIN11_RDP_IP:-192.168.122.199}"
USER_NAME="${WIN11_RDP_USER:-WIN11SIEMENS\\thoma}"
WIDTH="${WIN11_RDP_WIDTH:-1600}"
HEIGHT="${WIN11_RDP_HEIGHT:-900}"
HOME_DIR="${WIN11_RDP_HOME:-$HOME}"

command -v xfreerdp3 >/dev/null || { printf 'xfreerdp3 is not installed\n' >&2; exit 1; }
exec xfreerdp3 \
  "/v:$VM_IP" "/u:$USER_NAME" \
  "/w:$WIDTH" "/h:$HEIGHT" +dynamic-resolution +window-drag \
  /network:lan /gfx:AVC444 +video /rfx-mode:video \
  /compression-level:2 /cache:bitmap:on,codec:rfx,glyph:on,offscreen:on \
  -wallpaper -themes -fonts -menu-anims -aero \
  /audio-mode:redirect \
  /sound:sys:pulse /microphone:sys:pulse \
  /clipboard "/drive:home,$HOME_DIR" \
  /drive:fast-storage,/mnt/fast-storage \
  /printer /smartcard \
  /cert:ignore
