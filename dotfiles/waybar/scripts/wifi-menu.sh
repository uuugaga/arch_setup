#!/usr/bin/env bash
# managed-by: arch-niri-setup
set -euo pipefail

nmcli radio wifi on
nmcli device wifi rescan >/dev/null 2>&1 || true

ssid="$(
  nmcli -t -f SSID device wifi list --rescan yes \
    | sed '/^$/d' \
    | awk '!seen[$0]++' \
    | fuzzel --dmenu --prompt='Wi-Fi > '
)" || exit 0

[[ -z "${ssid}" ]] && exit 0

if nmcli -t -f NAME connection show | grep -Fxq "${ssid}"; then
  nmcli connection up "${ssid}"
  exit 0
fi

security="$(
  nmcli -t -f SSID,SECURITY device wifi list \
    | awk -F: -v s="${ssid}" '$1 == s {print $2; exit}'
)"

if [[ -z "${security}" || "${security}" == "--" ]]; then
  nmcli device wifi connect "${ssid}"
  exit 0
fi

alacritty -e bash -c '
ssid="$1"
read -rsp "Password for ${ssid}: " pass
echo
nmcli device wifi connect "${ssid}" password "${pass}"
echo
read -rp "Press Enter to close..."
' _ "${ssid}"
