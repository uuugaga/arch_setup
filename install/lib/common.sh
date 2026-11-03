#!/usr/bin/env bash
# Shared helpers for arch-niri-setup.
#
# Every entry script must set `set -Eeuo pipefail` and then source this file.
# The library never uses `sudo paru`; AUR builds always run as the normal user.

# shellcheck disable=SC2034

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_DIR="${PROJECT_ROOT}/config"
DOTFILES_DIR="${PROJECT_ROOT}/dotfiles"
LOG_DIR="${PROJECT_ROOT}/logs"

BACKUP_ROOT="${XDG_DATA_HOME:-${HOME}/.local/share}/arch-niri-setup/backups"
SYSTEM_BACKUP_ROOT="/var/backups/arch-niri-setup"
RUN_TS="$(date +%Y%m%d-%H%M%S)"

# Marker written into every file this project deploys. deploy_file uses it to
# decide whether an existing file is safe to replace.
MARKER="managed-by: arch-niri-setup"

if [[ -t 1 ]]; then
  C_RED=$'\033[31m'
  C_YEL=$'\033[33m'
  C_GRN=$'\033[32m'
  C_BLU=$'\033[34m'
  C_DIM=$'\033[2m'
  C_RST=$'\033[0m'
else
  C_RED=''
  C_YEL=''
  C_GRN=''
  C_BLU=''
  C_DIM=''
  C_RST=''
fi

LOG_FILE="${LOG_FILE:-}"

log() {
  printf '%s[%s]%s %s\n' "${C_DIM}" "$(date +%H:%M:%S)" "${C_RST}" "$*"
}

info() {
  printf '%s[info]%s %s\n' "${C_BLU}" "${C_RST}" "$*"
}

warn() {
  printf '%s[warn]%s %s\n' "${C_YEL}" "${C_RST}" "$*" >&2
}

err() {
  printf '%s[error]%s %s\n' "${C_RED}" "${C_RST}" "$*" >&2
}

die() {
  err "$*"
  exit 1
}

section() {
  printf '\n%s==> %s%s\n' "${C_GRN}" "$*" "${C_RST}"
}

# init_logging <step-name> [trap|notrap]
#
# Redirects stdout/stderr through tee so the terminal still shows progress
# while logs/<step>-<timestamp>.log keeps the full transcript.
init_logging() {
  local name="$1"
  local trap_mode="${2:-trap}"
  local base

  mkdir -p "${LOG_DIR}"
  LOG_FILE="${LOG_DIR}/${name}-${RUN_TS}.log"
  : > "${LOG_FILE}"
  ln -sfn "$(basename "${LOG_FILE}")" "${LOG_DIR}/latest-${name}.log"

  # Process substitution keeps the script's exit status independent of tee.
  exec > >(tee -a "${LOG_FILE}") 2>&1

  log "=== ${name} start: $(date -Is) ==="
  log "project=${PROJECT_ROOT}"
  log "log=${LOG_FILE}"

  if [[ "${trap_mode}" == "trap" ]]; then
    trap 'on_error $? $LINENO' ERR
  fi
}

on_error() {
  local status="$1"
  local line="$2"
  trap - ERR
  err "FAILED at line ${line} (exit ${status})"
  [[ -n "${LOG_FILE}" ]] && err "Full log: ${LOG_FILE}"
  exit "${status}"
}

require_non_root() {
  [[ "${EUID}" -ne 0 ]] || die "Do not run this script as root. Run it as the normal desktop user."
}

require_sudo() {
  sudo -n true 2>/dev/null || die "Passwordless sudo is required: 'sudo -n true' failed."
}

require_arch() {
  [[ -f /etc/arch-release ]] || die "This project targets Arch Linux only."
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

# pkg_present handles both packages and package groups (e.g. base-devel).
pkg_present() {
  pacman -Qq "$1" >/dev/null 2>&1 || pacman -Qg "$1" >/dev/null 2>&1
}

pkg_available() {
  pacman -Si "$1" >/dev/null 2>&1
}

pkg_version() {
  pacman -Q "$1" 2>/dev/null | awk '{print $2}' || true
}

run() {
  log "run: $*"
  "$@"
}

run_quiet() {
  "$@" >/dev/null 2>&1
}

pacman_upgrade() {
  section "Full system upgrade"
  run sudo -n pacman -Syu --noconfirm
}

pacman_install() {
  [[ "$#" -gt 0 ]] || die "pacman_install called without packages"
  section "Installing repo packages"
  run sudo -n pacman -S --needed --noconfirm "$@"
}

aur_install() {
  [[ "$#" -gt 0 ]] || die "aur_install called without packages"
  [[ "${EUID}" -ne 0 ]] || die "Never run paru as root"
  has_command paru || die "paru is not installed; run install/20-paru.sh first"
  section "Installing AUR packages (paru, as user)"
  run paru -S --needed --noconfirm "$@"
}

backup_file() {
  local path="$1"
  local dest
  [[ -e "${path}" ]] || return 0
  dest="${BACKUP_ROOT}/${RUN_TS}/${path#/}"
  mkdir -p "$(dirname "${dest}")"
  cp -a "${path}" "${dest}"
  log "backup: ${path} -> ${dest}"
}

backup_system_file() {
  local path="$1"
  local dest
  sudo -n test -e "${path}" || return 0
  dest="${SYSTEM_BACKUP_ROOT}/${RUN_TS}/${path#/}"
  sudo -n mkdir -p "$(dirname "${dest}")"
  sudo -n cp -a "${path}" "${dest}"
  log "system backup: ${path} -> ${dest}"
}

# deploy_file <src> <dest> [force] [mode]
#
# - identical destination: no-op
# - existing unmanaged destination: skip with return code 2 unless force=1
# - managed destination: back up, then replace
# Callers should treat return code 2 as a warning, not a hard failure:
#   rc=0; deploy_file ... || rc=$?; [[ $rc -eq 2 ]] && warn ...
deploy_file() {
  local src="$1"
  local dest="$2"
  local force="${3:-0}"
  local mode="${4:-644}"
  local tmp

  [[ -f "${src}" ]] || die "deploy_file: missing source ${src}"
  mkdir -p "$(dirname "${dest}")"

  if [[ -f "${dest}" ]] && cmp -s "${src}" "${dest}"; then
    log "unchanged: ${dest}"
    return 0
  fi

  if [[ -e "${dest}" ]]; then
    if [[ "${force}" != "1" ]] && ! grep -qF "${MARKER}" "${dest}" 2>/dev/null; then
      warn "conflict: ${dest} exists and is not managed by this project"
      warn "  keeping existing file; rerun with --force to back it up and replace it"
      return 2
    fi
    backup_file "${dest}"
  fi

  tmp="${dest}.tmp.$$"
  install -m "${mode}" "${src}" "${tmp}"
  mv -f "${tmp}" "${dest}"
  log "deployed: ${dest}"
}

# deploy_system_file <src> <dest> [force]
deploy_system_file() {
  local src="$1"
  local dest="$2"
  local force="${3:-0}"
  local tmp

  [[ -f "${src}" ]] || die "deploy_system_file: missing source ${src}"

  if sudo -n test -f "${dest}" && sudo -n cmp -s "${src}" "${dest}"; then
    log "unchanged: ${dest}"
    return 0
  fi

  if sudo -n test -e "${dest}"; then
    if [[ "${force}" != "1" ]] && ! sudo -n grep -qF "${MARKER}" "${dest}" 2>/dev/null; then
      warn "conflict: ${dest} exists and is not managed by this project"
      warn "  keeping existing file; rerun with --force to back it up and replace it"
      return 2
    fi
    backup_system_file "${dest}"
  fi

  tmp="${dest}.tmp.$$"
  sudo -n install -Dm644 "${src}" "${tmp}"
  sudo -n mv -f "${tmp}" "${dest}"
  log "deployed: ${dest}"
}

service_enabled() {
  systemctl is-enabled -q "$1" 2>/dev/null
}

ensure_service_enabled() {
  if service_enabled "$1"; then
    log "already enabled: $1"
  else
    run sudo -n systemctl enable "$1"
  fi
}

ensure_service_active() {
  if systemctl is-active -q "$1" 2>/dev/null; then
    log "already active: $1"
  else
    run sudo -n systemctl enable --now "$1"
  fi
}

disable_service_if_enabled() {
  if service_enabled "$1"; then
    warn "disabling conflicting display manager: $1"
    run sudo -n systemctl disable "$1"
  fi
}

# ensure_monitor_file makes sure the niri include target exists before
# validating the config. nwg-displays owns the file after the first install;
# never overwrite it on later runs.
ensure_monitor_file() {
  local src="${DOTFILES_DIR}/niri/monitor.kdl"
  local dest="${HOME}/.config/niri/monitor.kdl"
  if [[ -e "${dest}" ]]; then
    log "keeping existing niri monitor layout: ${dest}"
    return 0
  fi
  deploy_file "${src}" "${dest}" 0 644
}

# parse_jsonc <file> validates JSON with // and /* */ comments stripped.
parse_jsonc() {
  python3 - "$1" <<'PY'
import json
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
# Good enough for Waybar configs: no URLs or // inside strings in this project.
text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
text = re.sub(r"(^|\s)//.*$", "", text, flags=re.M)
json.loads(text)
print("valid")
PY
}

# run_step <script> [args...] is used by orchestration/tests if needed.
run_step() {
  local script="$1"
  shift
  bash "${PROJECT_ROOT}/install/${script}" "$@"
}
