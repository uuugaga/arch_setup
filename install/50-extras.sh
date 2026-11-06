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

# fcitx5 rewrites ~/.config/fcitx5/profile without the managed-by marker when
# it exits. Keep a profile that already has the two expected input methods;
# otherwise back it up and replace it so a fresh install really has working
# English + Chewing switching.
deploy_fcitx_profile() {
  local src="${DOTFILES_DIR}/fcitx5/profile"
  local dest="${HOME}/.config/fcitx5/profile"
  local force="${FORCE}"

  if [[ -f "${dest}" ]] && ! grep -qF "${MARKER}" "${dest}"; then
    if grep -qx 'Name=keyboard-us' "${dest}" && grep -qx 'Name=chewing' "${dest}"; then
      log "keeping existing fcitx5 profile (keyboard-us + chewing)"
      return 0
    fi
    warn "existing fcitx5 profile lacks keyboard-us/chewing; backing it up and replacing it"
    force=1
  fi

  local rc=0
  deploy_file "${src}" "${dest}" "${force}" 644 || rc=$?
  if [[ "${rc}" -eq 2 ]]; then
    warn "kept existing unmanaged fcitx5 profile: ${dest}"
  elif [[ "${rc}" -ne 0 ]]; then
    die "deploy failed: ${src} -> ${dest} (exit ${rc})"
  fi
}

# fcitx5 writes HiddenNotifications as an indexed section:
#   [HiddenNotifications]
#   0=wayland-diagnose-other
# Add the tip ID without dropping other hidden notification IDs.
ensure_fcitx_notifications() {
  local dest="${HOME}/.config/fcitx5/conf/notifications.conf"
  mkdir -p "$(dirname "${dest}")"

  if [[ ! -f "${dest}" ]]; then
    deploy_file "${DOTFILES_DIR}/fcitx5/conf/notifications.conf" "${dest}" 0 644
    return 0
  fi

  if grep -Eq '^[0-9]+=wayland-diagnose-other$' "${dest}"; then
    log "fcitx5 Wayland diagnostic tip already hidden"
    return 0
  fi

  backup_file "${dest}"
  python3 - "${dest}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
if any(re.fullmatch(r"\d+=wayland-diagnose-other", line.strip()) for line in lines):
    raise SystemExit(0)

# The old/empty form is a flat key and is not how fcitx5 serializes a vector.
lines = [line for line in lines if not line.strip().startswith("HiddenNotifications=")]

start = None
for index, line in enumerate(lines):
    if line.strip() == "[HiddenNotifications]":
        start = index
        break

if start is None:
    lines.append("[HiddenNotifications]")
    start = len(lines) - 1

end = len(lines)
for index in range(start + 1, len(lines)):
    if lines[index].strip().startswith("["):
        end = index
        break

max_index = -1
for line in lines[start + 1 : end]:
    match = re.match(r"\s*(\d+)\s*=", line)
    if match:
        max_index = max(max_index, int(match.group(1)))

lines.insert(end, f"{max_index + 1}=wayland-diagnose-other")
path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
  log "hid the fcitx5 Wayland diagnostic tip"
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

# Choose the 32-bit Vulkan ICD that matches the GPU. A software lavapipe
# fallback is only correct for VMs or unknown GPUs; installing it next to a
# hardware GPU can make 32-bit games pick the CPU renderer.
gaming_gpu_packages() {
  local gpu_info
  local has_nvidia=0
  local has_amd=0
  local has_intel=0

  gpu_info="$(lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' || true)"
  grep -Eiq 'nvidia' <<< "${gpu_info}" && has_nvidia=1
  grep -Eiq 'amd|radeon|advanced micro devices' <<< "${gpu_info}" && has_amd=1
  grep -Eiq 'intel' <<< "${gpu_info}" && has_intel=1

  [[ "${has_nvidia}" -eq 1 ]] && printf '%s\n' "${GAMING_32BIT_NVIDIA[@]}"
  [[ "${has_amd}" -eq 1 ]] && printf '%s\n' "${GAMING_32BIT_AMD[@]}"
  [[ "${has_intel}" -eq 1 ]] && printf '%s\n' "${GAMING_32BIT_INTEL[@]}"
  if [[ "${has_nvidia}" -eq 0 && "${has_amd}" -eq 0 && "${has_intel}" -eq 0 ]]; then
    printf '%s\n' "${GAMING_SOFTWARE_VULKAN[@]}"
  fi
}

# Steam is a [multilib] package. Enable the repository idempotently and do a
# full -Syu the first time, because a partial -Sy would leave the system in an
# unsupported state. The pacman.conf edit is backed up first.
enable_multilib() {
  if grep -q '^\[multilib\]' /etc/pacman.conf; then
    log "[multilib] already enabled"
    if [[ ! -f /var/lib/pacman/sync/multilib.db ]]; then
      warn "[multilib] is enabled but its sync database is missing; running pacman -Syu"
      pacman_upgrade
    fi
    return 0
  fi

  section "Enabling [multilib]"
  backup_system_file /etc/pacman.conf
  sudo -n /usr/bin/python3 - <<'PY'
from pathlib import Path

path = Path("/etc/pacman.conf")
lines = path.read_text(encoding="utf-8").splitlines()
out = []
inside = False
enabled = False
for line in lines:
    stripped = line.strip()
    if stripped == "#[multilib]":
        out.append("[multilib]")
        inside = True
        enabled = True
        continue
    if inside and stripped == "#Include = /etc/pacman.d/mirrorlist":
        out.append("Include = /etc/pacman.d/mirrorlist")
        inside = False
        continue
    out.append(line)
if not enabled:
    raise SystemExit("could not find the commented [multilib] block")
path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY

  if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    die "Failed to enable [multilib] in /etc/pacman.conf"
  fi
  if ! sed -n '/^\[multilib\]/,/^$/p' /etc/pacman.conf \
    | grep -q '^Include = /etc/pacman.d/mirrorlist$'; then
    die "[multilib] is enabled but its Include line is missing"
  fi
  pacman_upgrade
}

user_systemd() {
  if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    systemctl --user "$@"
  else
    warn "No user D-Bus session; run manually after login: systemctl --user $*"
    return 0
  fi
}

start_fcitx5_in_session() {
  local socket="${NIRI_SOCKET:-}"
  if [[ -z "${socket}" && -n "${XDG_RUNTIME_DIR:-}" ]]; then
    socket="$(find "${XDG_RUNTIME_DIR}" -maxdepth 1 -name 'niri.*.sock' -print -quit 2>/dev/null || true)"
  fi
  if [[ -z "${socket}" ]] || ! has_command niri; then
    log "no active niri session; fcitx5 will start at next login"
    return 0
  fi
  if NIRI_SOCKET="${socket}" niri msg action spawn -- fcitx5 -d --replace >/dev/null 2>&1; then
    log "started fcitx5 in the active niri session"
  else
    warn "could not start fcitx5 in the active session; it will start at next login"
  fi
}

reload_niri_in_session() {
  local socket="${NIRI_SOCKET:-}"
  if [[ -z "${socket}" && -n "${XDG_RUNTIME_DIR:-}" ]]; then
    socket="$(find "${XDG_RUNTIME_DIR}" -maxdepth 1 -name 'niri.*.sock' -print -quit 2>/dev/null || true)"
  fi
  if [[ -z "${socket}" ]] || ! has_command niri; then
    return 0
  fi
  if NIRI_SOCKET="${socket}" niri msg action load-config-file >/dev/null 2>&1; then
    log "reloaded niri config in the active session"
  else
    warn "could not reload niri config; log out/in to apply the new binds"
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

  # fcitx5 saves its in-memory input method list over ~/.config/fcitx5/profile
  # when it exits. Stop it before deploying the profile, otherwise a running
  # instance would overwrite the new keyboard-us + chewing list.
  if pgrep -x fcitx5 >/dev/null 2>&1; then
    log "stopping fcitx5 before deploying profile"
    pkill -TERM -x fcitx5 || true
    for _ in {1..50}; do
      pgrep -x fcitx5 >/dev/null 2>&1 || break
      sleep 0.1
    done
    if pgrep -x fcitx5 >/dev/null 2>&1; then
      warn "fcitx5 did not stop; it may overwrite the deployed profile on exit"
    fi
  fi

  mkdir -p "${HOME}/.config/fcitx5" "${HOME}/.local/bin"
  deploy_fcitx_profile
  ensure_fcitx_notifications
  deploy_or_warn "${DOTFILES_DIR}/fcitx5/ime-toggle" "${HOME}/.local/bin/ime-toggle" 755
  deploy_full_niri_config
  reload_niri_in_session
  start_fcitx5_in_session
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
  enable_multilib

  mapfile -t GAMING_GPU_PKGS < <(gaming_gpu_packages)
  if printf '%s\n' "${GAMING_GPU_PKGS[@]}" | grep -qx 'lib32-nvidia-utils' \
    && ! pkg_present nvidia-open; then
    warn "NVIDIA kernel modules are not installed yet; run WANT_32BIT=1 ./install/60-gpu.sh."
  fi
  pacman_install "${EXTRAS_GAMING[@]}" "${GAMING_GPU_PKGS[@]}"

  mkdir -p \
    "${HOME}/.config/MangoHud" \
    "${HOME}/Games/SteamLibrary" \
    "${HOME}/.config/arch-niri-setup"
  deploy_or_warn "${DOTFILES_DIR}/gaming/MangoHud.conf" "${HOME}/.config/MangoHud/MangoHud.conf" 644
  printf 'installed=%s\n' "$(date -Iseconds)" > "${HOME}/.config/arch-niri-setup/gaming"

  info "Steam library directory: ${HOME}/Games/SteamLibrary"
  info "Add it in Steam: Settings -> Storage -> Add Drive."
  info "First launch downloads the Steam runtime and requires your account login."
  info "Suggested per-game launch options: gamemoderun mangohud %command%"
  if has_command vulkaninfo; then
    VK_SUMMARY="$(vulkaninfo --summary 2>&1 || true)"
    if grep -qi 'PHYSICAL_DEVICE_TYPE_CPU' <<< "${VK_SUMMARY}" \
      && ! grep -qiE 'PHYSICAL_DEVICE_TYPE_(DISCRETE_GPU|INTEGRATED_GPU|VIRTUAL_GPU|OTHER)' <<< "${VK_SUMMARY}"; then
      warn "Vulkan is software-only (lavapipe). Proton games will be slow; use Steam Remote Play for real 3D games."
    elif [[ -z "${VK_SUMMARY}" ]]; then
      warn "vulkaninfo produced no output; run it again inside the graphical session."
    fi
  fi
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
