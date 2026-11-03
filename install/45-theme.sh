#!/usr/bin/env bash
# 45-theme.sh - install hourly wallpaper rotation and dynamic theming.
#
# The wallpaper images themselves are user data. Put them in
# ~/Pictures/Wallpapers (see README) before or after running this step.
#
# Deploys:
#   ~/.local/bin/wallpaper-rotate
#   ~/.local/bin/theme-from-wallpaper
#   ~/.config/arch-niri-setup/templates/*
#   ~/.config/systemd/user/wallpaper-rotate.{service,timer}
#
# Renders an initial theme from the current wallpaper using --theme-only.
# It does not start a Wayland session; niri applies the wallpaper at login.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=../config/packages.conf
source "${PROJECT_ROOT}/config/packages.conf"
init_logging 45-theme

require_non_root
require_sudo
require_arch

FORCE="${FORCE:-0}"

section "Installing theme packages"
pacman_install awww python-pillow libnotify

section "Preparing directories"
mkdir -p \
  "${HOME}/.local/bin" \
  "${HOME}/.config/arch-niri-setup/templates" \
  "${HOME}/.config/arch-niri-setup/rendered" \
  "${HOME}/.local/state/arch-niri-setup" \
  "${HOME}/.config/systemd/user/timers.target.wants" \
  "${HOME}/Pictures/Wallpapers"

section "Deploying theme scripts"
deploy_file "${DOTFILES_DIR}/theme/theme-from-wallpaper" "${HOME}/.local/bin/theme-from-wallpaper" "${FORCE}" 755
deploy_file "${DOTFILES_DIR}/awww/wallpaper-rotate" "${HOME}/.local/bin/wallpaper-rotate" "${FORCE}" 755

section "Deploying templates"
for template in waybar-style.css mako-config fuzzel.ini alacritty.toml; do
  deploy_file \
    "${DOTFILES_DIR}/theme/templates/${template}" \
    "${HOME}/.config/arch-niri-setup/templates/${template}" \
    "${FORCE}" 644
done

section "Deploying systemd user units"
deploy_file "${DOTFILES_DIR}/systemd/user/wallpaper-rotate.service" "${HOME}/.config/systemd/user/wallpaper-rotate.service" "${FORCE}" 644
deploy_file "${DOTFILES_DIR}/systemd/user/wallpaper-rotate.timer" "${HOME}/.config/systemd/user/wallpaper-rotate.timer" "${FORCE}" 644

ln -sfn \
  "${HOME}/.config/systemd/user/wallpaper-rotate.timer" \
  "${HOME}/.config/systemd/user/timers.target.wants/wallpaper-rotate.timer"
log "enabled wallpaper-rotate.timer (WantedBy=timers.target)"

if ! systemctl --user daemon-reload 2>/dev/null; then
  warn "systemctl --user is not available over this session; the timer will load at next login."
fi

section "Deploying niri config with wallpaper hook"
NIRI_TEMPLATE="${DOTFILES_DIR}/niri/config.kdl"
if has_command fcitx5-remote; then
  NIRI_TEMPLATE="${DOTFILES_DIR}/niri/config.full.kdl"
  log "fcitx5 detected; using config.full.kdl"
fi

rc=0
deploy_file "${NIRI_TEMPLATE}" "${HOME}/.config/niri/config.kdl" "${FORCE}" 644 || rc=$?
if [[ "${rc}" -eq 2 ]]; then
  die "Existing unmanaged niri config was kept. Rerun with FORCE=1 to replace it."
elif [[ "${rc}" -ne 0 ]]; then
  die "Failed to deploy niri config (exit ${rc})."
fi
run niri validate -c "${HOME}/.config/niri/config.kdl"

section "Rendering initial theme"
mapfile -d '' WALLPAPERS < <(
  find "${HOME}/Pictures/Wallpapers" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    -print0 | sort -z
)

if [[ "${#WALLPAPERS[@]}" -eq 0 ]]; then
  warn "No wallpapers in ${HOME}/Pictures/Wallpapers yet."
  warn "Copy images there, then run: wallpaper-rotate --next"
else
  run "${HOME}/.local/bin/wallpaper-rotate" --theme-only
  info "Initial theme generated from: $(cat "${HOME}/.config/arch-niri-setup/current-wallpaper" 2>/dev/null || echo unknown)"
fi

section "Starting timer for the current session (if possible)"
if systemctl --user start wallpaper-rotate.timer 2>/dev/null; then
  log "wallpaper-rotate.timer started"
else
  warn "Timer not started in this SSH session; it will start at next login."
fi

section "Theme step complete"
info "Wallpaper directory: ${HOME}/Pictures/Wallpapers"
info "Hourly timer: wallpaper-rotate.timer"
info "Manual switch: wallpaper-rotate --next"
