#!/usr/bin/env bash
# managed-by: arch-niri-setup
set -euo pipefail

count="$(
  makoctl list -j 2>/dev/null \
    | jq '[.data[]?[]?] | length' 2>/dev/null \
    || echo 0
)"

count="${count//[[:space:]]/}"

if [[ "${count}" -gt 0 ]]; then
  printf '{"text":"󰂚 %s","tooltip":"%s active notifications","class":"has-notifications"}\n' "${count}" "${count}"
else
  printf '{"text":"󰂚","tooltip":"No active notifications","class":"empty"}\n'
fi
