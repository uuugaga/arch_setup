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
for c in niri niri-session waybar fuzzel alacritty mako greetd tuigreet xwayland-satellite nmcli wpctl jq nwg-displays; do
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

section "Input method"
if has_command fcitx5; then
  for c in fcitx5 fcitx5-remote fcitx5-configtool; do
    if has_command "${c}"; then
      ok "${c}"
    else
      bad "missing command: ${c}"
    fi
  done

  if [[ -f "${HOME}/.config/fcitx5/profile" ]] \
    && grep -qx 'Name=keyboard-us' "${HOME}/.config/fcitx5/profile" \
    && grep -qx 'Name=chewing' "${HOME}/.config/fcitx5/profile"; then
    ok "fcitx5 profile has keyboard-us + chewing"
  else
    bad "fcitx5 profile missing keyboard-us/chewing"
  fi

  if [[ -x "${HOME}/.config/waybar/scripts/ime-status.sh" ]]; then
    ok "ime-status.sh executable"
  else
    bad "ime-status.sh missing"
  fi

  if [[ -x "${HOME}/.local/bin/ime-toggle" ]]; then
    ok "ime-toggle executable"
  else
    bad "ime-toggle missing"
  fi

  if grep -qF 'ime-toggle' "${HOME}/.config/niri/config.kdl" 2>/dev/null; then
    ok "Mod+Space uses ime-toggle"
  else
    bad "Mod+Space does not use ime-toggle"
  fi

  if grep -qF '"custom/ime"' "${HOME}/.config/waybar/config.jsonc" 2>/dev/null; then
    ok "Waybar custom/ime module configured"
  else
    bad "Waybar custom/ime module missing"
  fi
else
  info "fcitx5 not installed; skipping optional IME checks"
fi

section "Wallpaper / theme"
if [[ -x "${HOME}/.local/bin/wallpaper-rotate" && -x "${HOME}/.local/bin/theme-from-wallpaper" ]]; then
  ok "theme scripts executable"
else
  bad "theme scripts missing"
fi

WALLPAPER_COUNT="$(find "${HOME}/Pictures/Wallpapers" -maxdepth 1 -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
  2>/dev/null | wc -l)"
if [[ "${WALLPAPER_COUNT}" -gt 0 ]]; then
  ok "${WALLPAPER_COUNT} wallpaper(s)"
else
  bad "no wallpapers in ~/Pictures/Wallpapers"
fi

if [[ -f "${HOME}/.config/arch-niri-setup/theme.env" ]]; then
  ok "theme.env present"
else
  bad "theme.env missing"
fi

if [[ -L "${HOME}/.config/systemd/user/timers.target.wants/wallpaper-rotate.timer" ]]; then
  ok "wallpaper-rotate.timer enabled"
else
  bad "wallpaper-rotate.timer not enabled"
fi

if [[ -f "${HOME}/.config/arch-niri-setup/current-wallpaper" ]]; then
  current="$(cat "${HOME}/.config/arch-niri-setup/current-wallpaper" 2>/dev/null || true)"
  [[ -n "${current}" && -f "${current}" ]] && ok "current wallpaper exists" || bad "current wallpaper missing"
else
  bad "current-wallpaper not set"
fi

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
