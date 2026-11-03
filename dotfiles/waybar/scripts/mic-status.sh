#!/usr/bin/env bash
# managed-by: arch-niri-setup
set -euo pipefail

info="$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null || true)"

if [[ -z "${info}" ]]; then
  printf '{"text":"󰍭","tooltip":"No microphone detected","class":"missing"}\n'
  exit 0
fi

volume="$(awk '{printf "%d", $2 * 100}' <<< "${info}")"

if grep -q MUTED <<< "${info}"; then
  printf '{"text":"󰍭","tooltip":"Microphone muted","class":"muted"}\n'
else
  printf '{"text":"󰍬","tooltip":"Microphone: %s%%","class":"active"}\n' "${volume}"
fi
