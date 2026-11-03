#!/usr/bin/env bash
# 50-extras.sh - optional modules from the old setup, ported and made idempotent.
#
# Nothing runs unless a module is selected:
#   ./install/50-extras.sh --fcitx
#   ./install/50-extras.sh --wallpaper
#   ./install/50-extras.sh --apps
#   ./install/50-extras.sh --gaming
#   ./install/50-extras.sh --zsh
#   ./install/50-extras.sh --all
#
# Run install/30-niri.sh and install/40-desktop.sh first. The --fcitx module
# replaces the core niri config with config.full.kdl, so run it last.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=../config/packages.conf
source "${PROJECT_ROOT}/config/packages.conf"
init_logging 50-extras

require_non_root
require_sudo
require_arch

FORCE="${FORCE:-0}"
WANT_FCITX=0
WANT_WALLPAPER=0
WANT_APPS=0
WANT_GAMING=0
WANT_ZSH=0

usage() {
  sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

if [[ "$#" -eq 0 ]]; then
  usage
  exit 1
fi

for arg in "$@"; do
  case "${arg}" in
    --fcitx) WANT_FCITX=1 ;;
    --wallpaper) WANT_WALLPAPER=1 ;;
    --apps) WANT_APPS=1 ;;
    --gaming) WANT_GAMING=1 ;;
    --zsh) WANT_ZSH=1 ;;
    --all)
      WANT_FCITX=1
      WANT_WALLPAPER=1
      WANT_APPS=1
      WANT_GAMING=1
      WANT_ZSH=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: ${arg} (see --help)"
      ;;
  esac
done

deploy_or_warn() {
  local src="$1"
  local dest="$2"
  local mode="${3:-644}"
  local rc=0
  deploy_file "${src}" "${dest}" "${FORCE}" "${mode}" || rc=$?
  if [[ "${rc}" -eq 2 ]]; then
    warn "kept existing unmanaged file: ${dest}"
  elif [[ "${rc}" -ne 0 ]]; then
    die "deploy failed: ${src} -> ${dest} (exit ${rc})"
  fi
}

install_available_repo() {
  local available=()
  local p
  for p in "$@"; do
    if pkg_available "${p}"; then
      available+=("${p}")
    else
      warn "not available in enabled repos: ${p}"
    fi
  done
  if [[ "${#available[@]}" -gt 0 ]]; then
    pacman_install "${available[@]}"
  fi
}

user_systemd() {
  if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    systemctl --user "$@"
  else
    warn "No user D-Bus session; run manually after login: systemctl --user $*"
    return 0
  fi
}

deploy_full_niri_config() {
  section "Deploying full niri config (extras enabled)"
  local rc=0
  deploy_file "${DOTFILES_DIR}/niri/config.full.kdl" "${HOME}/.config/niri/config.kdl" "${FORCE}" 644 || rc=$?
  if [[ "${rc}" -eq 2 ]]; then
    warn "Existing unmanaged niri config kept; extras config not applied."
    return 0
  fi
  ensure_monitor_file
  niri validate -c "${HOME}/.config/niri/config.kdl"

  if [[ -x "${HOME}/.local/bin/theme-from-wallpaper" && -f "${HOME}/.config/arch-niri-setup/current-wallpaper" ]]; then
    "${HOME}/.local/bin/theme-from-wallpaper" "$(cat "${HOME}/.config/arch-niri-setup/current-wallpaper")" --no-reload || warn "Theme reapply failed."
  fi
}

if [[ "${WANT_FCITX}" -eq 1 ]]; then
  section "Module: fcitx5 + Chewing"
  pacman_install "${EXTRAS_FCITX[@]}"
  mkdir -p "${HOME}/.config/fcitx5"
  deploy_or_warn "${DOTFILES_DIR}/fcitx5/profile" "${HOME}/.config/fcitx5/profile" 644
  deploy_full_niri_config
  info "fcitx5 is started by niri (single owner); no systemd user service is installed."
fi

if [[ "${WANT_WALLPAPER}" -eq 1 ]]; then
  section "Module: wallpaper rotation (awww)"
  pacman_install "${EXTRAS_WALLPAPER[@]}"
  mkdir -p "${HOME}/.local/bin" "${HOME}/.config/systemd/user" "${HOME}/Pictures/Wallpapers"
  deploy_or_warn "${DOTFILES_DIR}/awww/wallpaper-rotate" "${HOME}/.local/bin/wallpaper-rotate" 755
  deploy_or_warn "${DOTFILES_DIR}/systemd/user/wallpaper-rotate.service" "${HOME}/.config/systemd/user/wallpaper-rotate.service" 644
  deploy_or_warn "${DOTFILES_DIR}/systemd/user/wallpaper-rotate.timer" "${HOME}/.config/systemd/user/wallpaper-rotate.timer" 644
  user_systemd daemon-reload
  user_systemd enable --now wallpaper-rotate.timer
  info "Put images in ~/Pictures/Wallpapers. awww-daemon is started by niri."
fi

if [[ "${WANT_APPS}" -eq 1 ]]; then
  section "Module: common applications"
  install_available_repo "${EXTRAS_APPS_REPO[@]}"

  AUR_FAILED=()
  if has_command paru; then
    for p in "${EXTRAS_APPS_AUR[@]}"; do
      if pkg_present "${p}"; then
        log "already installed: ${p}"
        continue
      fi
      section "AUR app: ${p}"
      if run paru -S --needed --noconfirm "${p}"; then
        log "installed: ${p}"
      else
        warn "AUR install failed: ${p}"
        AUR_FAILED+=("${p}")
      fi
    done
  else
    warn "paru missing; skipping AUR apps. Run install/20-paru.sh first."
  fi

  if has_command docker; then
    ensure_service_active docker.service
    if ! id -nG | tr ' ' '\n' | grep -qx docker; then
      run sudo -n usermod -aG docker "${USER}"
      warn "Added ${USER} to the docker group. Log out and back in to use docker without sudo."
    fi
  fi

  if has_command tailscale; then
    ensure_service_enabled tailscaled.service
    ensure_service_active tailscaled.service
    info "Tailscale is installed; run 'sudo tailscale up' to log in."
  fi

  mkdir -p "${HOME}/.local/bin"
  deploy_or_warn "${DOTFILES_DIR}/apps/app-check" "${HOME}/.local/bin/app-check" 755

  if [[ "${#AUR_FAILED[@]}" -gt 0 ]]; then
    warn "Some AUR apps failed: ${AUR_FAILED[*]}"
    warn "Rerun ./install/50-extras.sh --apps after fixing the failure."
  fi

  info "Run 'app-check' after logging out/in to review the app set."
fi

if [[ "${WANT_GAMING}" -eq 1 ]]; then
  section "Module: Steam / gaming"
  if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    warn "The [multilib] repository is not enabled in /etc/pacman.conf."
    warn "Enable it, run 'sudo pacman -Syu', then rerun --gaming."
    die "Cannot install Steam without multilib."
  fi
  pacman_install "${EXTRAS_GAMING[@]}"
  warn "For NVIDIA 32-bit drivers run: WANT_32BIT=1 ./install/60-gpu.sh"
fi

if [[ "${WANT_ZSH}" -eq 1 ]]; then
  section "Module: Zsh + Starship"
  pacman_install "${EXTRAS_ZSH[@]}"
  local_rc=0
  deploy_file "${DOTFILES_DIR}/zsh/zshrc" "${HOME}/.zshrc" "${FORCE}" 644 || local_rc=$?
  if [[ "${local_rc}" -eq 2 ]]; then
    warn "Existing ~/.zshrc kept. Sample: ${DOTFILES_DIR}/zsh/zshrc"
  fi
  info "Change your shell manually if desired: chsh -s /usr/bin/zsh"
fi

section "Extras complete"
info "Selected modules applied. Re-run install/90-validate.sh."
