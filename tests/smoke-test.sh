#!/usr/bin/env bash
# tests/smoke-test.sh - fast, read-only sanity checks.
#
# Intended to run after install/90-validate.sh and after every change.
# Exits non-zero if a required binary or config is broken.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib/common.sh
source "${SCRIPT_DIR}/../install/lib/common.sh"
# shellcheck source=../config/packages.conf
source "${PROJECT_ROOT}/config/packages.conf"
init_logging smoke-test

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

section "Commands"
for c in niri niri-session waybar fuzzel alacritty mako greetd tuigreet xwayland-satellite nmcli wpctl jq; do
  if has_command "${c}"; then
    ok "${c}"
  else
    bad "missing command: ${c}"
  fi
done

section "Configs"
if [[ -f "${HOME}/.config/niri/config.kdl" ]]; then
  if niri validate -c "${HOME}/.config/niri/config.kdl" >/dev/null 2>&1; then
    ok "niri config valid"
  else
    bad "niri config invalid: niri validate -c ~/.config/niri/config.kdl"
  fi
else
  bad "missing ~/.config/niri/config.kdl"
fi

if [[ -f "${HOME}/.config/waybar/config.jsonc" ]]; then
  if parse_jsonc "${HOME}/.config/waybar/config.jsonc" >/dev/null 2>&1; then
    ok "waybar config valid JSON(C)"
  else
    bad "waybar config invalid"
  fi
else
  bad "missing waybar config"
fi

for f in \
  "${HOME}/.config/fuzzel/fuzzel.ini" \
  "${HOME}/.config/mako/config" \
  "${HOME}/.config/alacritty/alacritty.toml"; do
  [[ -f "${f}" ]] && ok "present: ${f}" || bad "missing: ${f}"
done

section "Services"
for svc in sshd.service NetworkManager.service; do
  if systemctl is-active -q "${svc}" 2>/dev/null; then
    ok "${svc} active"
  else
    bad "${svc} not active"
  fi
done

if service_enabled greetd.service; then
  ok "greetd.service enabled"
else
  bad "greetd.service not enabled"
fi

section "SSH"
if ss -ltnH 2>/dev/null | grep -q ':22 '; then
  ok "sshd listening on :22"
else
  bad "sshd not listening on :22"
fi

section "Summary"
info "PASS=${PASS} FAIL=${FAIL}"

if [[ "${FAIL}" -gt 0 ]]; then
  err "Smoke test failed."
  exit 1
fi

info "Smoke test passed."
