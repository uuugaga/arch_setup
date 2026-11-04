#!/usr/bin/env bash
# tests/gaming-test.sh - optional Steam/gaming checks.
#
# Read-only. Exits 0 when Steam was not installed via 50-extras.sh --gaming,
# so the core smoke test can stay independent of optional modules.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib/common.sh
source "${SCRIPT_DIR}/../install/lib/common.sh"
# shellcheck source=../config/packages.conf
source "${PROJECT_ROOT}/config/packages.conf"
init_logging gaming-test

require_non_root

PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  log "ok: $*"
}

bad() {
  FAIL=$((FAIL + 1))
  err "fail: $*"
}

if [[ ! -f "${HOME}/.config/arch-niri-setup/gaming" ]]; then
  info "Steam/gaming is not installed via --gaming; skipping optional checks."
  exit 0
fi

section "Multilib"
if grep -q '^\[multilib\]' /etc/pacman.conf; then
  ok "[multilib] enabled"
else
  bad "[multilib] is not enabled"
fi

section "Packages"
for p in "${EXTRAS_GAMING[@]}"; do
  if pkg_present "${p}"; then
    ok "package: ${p}"
  else
    bad "missing package: ${p}"
  fi
done

section "Commands"
for c in "${GAMING_COMMANDS[@]}"; do
  if has_command "${c}"; then
    ok "command: ${c}"
  else
    bad "missing command: ${c}"
  fi
done

section "Vulkan"
if has_command vulkaninfo; then
  VK_SUMMARY="$(vulkaninfo --summary 2>&1 || true)"
  if grep -qi 'PHYSICAL_DEVICE_TYPE_CPU' <<< "${VK_SUMMARY}" \
    && ! grep -qiE 'PHYSICAL_DEVICE_TYPE_(DISCRETE_GPU|INTEGRATED_GPU|VIRTUAL_GPU|OTHER)' <<< "${VK_SUMMARY}"; then
    ok "Vulkan device: lavapipe (software; expected in this VM)"
  elif grep -qi 'deviceName' <<< "${VK_SUMMARY}"; then
    ok "Vulkan device: $(grep -i 'deviceName' <<< "${VK_SUMMARY}" | head -n 1 | sed 's/^[[:space:]]*//')"
  else
    bad "vulkaninfo could not enumerate a device"
  fi
else
  bad "vulkaninfo is missing"
fi

section "Steam devices"
if pkg_present steam-devices; then
  if pacman -Ql steam-devices 2>/dev/null | grep -q '/usr/lib/udev/rules.d/.*\.rules$'; then
    ok "steam-devices udev rules installed"
  else
    bad "steam-devices package has no udev rules"
  fi
else
  bad "steam-devices is missing"
fi

section "Configuration"
if [[ -f "${HOME}/.config/MangoHud/MangoHud.conf" ]]; then
  ok "MangoHud.conf present"
else
  bad "MangoHud.conf missing"
fi

if [[ -d "${HOME}/Games/SteamLibrary" ]]; then
  ok "Steam library directory present"
else
  bad "Steam library directory missing"
fi

if [[ -f "${HOME}/.config/arch-niri-setup/gaming" ]]; then
  ok "gaming marker present"
else
  bad "gaming marker missing"
fi

section "Summary"
info "PASS=${PASS} FAIL=${FAIL}"

if [[ "${FAIL}" -gt 0 ]]; then
  err "Gaming test failed."
  exit 1
fi

info "Gaming test passed."
