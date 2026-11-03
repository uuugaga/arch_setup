#!/usr/bin/env bash
# 40-desktop.sh - deploy Waybar, Fuzzel, mako, Alacritty configs and enable
# desktop services. Does not start a graphical session.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
init_logging 40-desktop

require_non_root
require_sudo
require_arch

FORCE="${FORCE:-0}"
CONFLICTS=0

section "Preparing directories"
mkdir -p \
  "${HOME}/.config/waybar/scripts" \
  "${HOME}/.config/fuzzel" \
  "${HOME}/.config/mako" \
  "${HOME}/.config/alacritty" \
  "${HOME}/Pictures/Wallpapers" \
  "${HOME}/Pictures/Screenshots"

xdg-user-dirs-update 2>/dev/null || warn "xdg-user-dirs-update failed (non-fatal)."

deploy_or_warn() {
  local src="$1"
  local dest="$2"
  local mode="${3:-644}"
  local rc=0
  deploy_file "${src}" "${dest}" "${FORCE}" "${mode}" || rc=$?
  if [[ "${rc}" -eq 2 ]]; then
    CONFLICTS=$((CONFLICTS + 1))
    warn "kept existing file: ${dest}"
  elif [[ "${rc}" -ne 0 ]]; then
    die "deploy failed: ${src} -> ${dest} (exit ${rc})"
  fi
}

section "Deploying Waybar"
deploy_or_warn "${DOTFILES_DIR}/waybar/config.jsonc" "${HOME}/.config/waybar/config.jsonc" 644
deploy_or_warn "${DOTFILES_DIR}/waybar/style.css" "${HOME}/.config/waybar/style.css" 644
for s in notifications.sh notifications-menu.sh wifi-menu.sh mic-status.sh ime-status.sh; do
  deploy_or_warn "${DOTFILES_DIR}/waybar/scripts/${s}" "${HOME}/.config/waybar/scripts/${s}" 755
done

section "Deploying Fuzzel"
deploy_or_warn "${DOTFILES_DIR}/fuzzel/fuzzel.ini" "${HOME}/.config/fuzzel/fuzzel.ini" 644

section "Deploying mako"
deploy_or_warn "${DOTFILES_DIR}/mako/config" "${HOME}/.config/mako/config" 644

section "Deploying Alacritty"
deploy_or_warn "${DOTFILES_DIR}/alacritty/alacritty.toml" "${HOME}/.config/alacritty/alacritty.toml" 644

section "Enabling desktop services"
ensure_service_active NetworkManager.service
if has_command bluetoothctl; then
  ensure_service_enabled bluetooth.service
else
  warn "bluez is not installed; skipping bluetooth.service."
fi
ensure_service_active sshd.service

section "Validating deployed desktop configs"
if ! parse_jsonc "${HOME}/.config/waybar/config.jsonc"; then
  die "Waybar config is not valid JSON(C)."
fi
log "ok: Waybar config parses as JSON"

if has_command python3; then
  python3 - "${HOME}/.config/alacritty/alacritty.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    tomllib.load(f)
print("ok: Alacritty config parses as TOML")
PY
fi

for c in waybar fuzzel alacritty mako; do
  has_command "${c}" || die "missing command: ${c}"
  log "ok: ${c} -> $(command -v "${c}")"
done

section "Desktop step complete"
info "Configs deployed. No graphical session was started."
if [[ "${CONFLICTS}" -gt 0 ]]; then
  warn "${CONFLICTS} existing config(s) were kept. Rerun with FORCE=1 to replace them."
fi
