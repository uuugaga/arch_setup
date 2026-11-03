#!/usr/bin/env bash
# managed-by: arch-niri-setup
set -euo pipefail

items="$(
  makoctl list -j 2>/dev/null \
    | jq -r '.data[]?[]? | "\((.["app-name"].data // .app_name // .app // "unknown")) — \((.summary.data // .summary // ""))"' 2>/dev/null \
    | sed '/^ — $/d'
)" || items=""

if [[ -z "${items}" ]]; then
  printf "No notifications\n" | fuzzel --dmenu --prompt='Notifications > ' >/dev/null
  exit 0
fi

choice="$(
  printf '%s\n\nDismiss all\nRestore last\n' "${items}" \
    | fuzzel --dmenu --prompt='Notifications > '
)" || exit 0

case "${choice}" in
  "Dismiss all")
    makoctl dismiss -a
    ;;
  "Restore last")
    makoctl restore
    ;;
  *)
    exit 0
    ;;
esac
