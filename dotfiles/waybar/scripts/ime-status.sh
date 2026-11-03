#!/usr/bin/env bash
# managed-by: arch-niri-setup
# Emits a Waybar JSON line. When fcitx5 is not installed the module is hidden
# by style.css (#custom-ime.missing) instead of reserving empty space.
set -euo pipefail

if ! command -v fcitx5-remote >/dev/null 2>&1; then
  printf '{"text":"","tooltip":"fcitx5 is not installed (install/50-extras.sh --fcitx)","class":"missing"}\n'
  exit 0
fi

name="$(fcitx5-remote -n 2>/dev/null || true)"

case "${name}" in
  keyboard-us|keyboard-us-dvorak|keyboard-us-colemak)
    printf '{"text":"EN","tooltip":"Input method: English keyboard-us","class":"en"}\n'
    ;;
  chewing)
    printf '{"text":"ZH","tooltip":"Input method: Chewing 注音","class":"zh"}\n'
    ;;
  "")
    printf '{"text":"","tooltip":"fcitx5 is not running","class":"missing"}\n'
    ;;
  *)
    printf '{"text":"IM","tooltip":"Input method: %s","class":"other"}\n' "${name}"
    ;;
esac
