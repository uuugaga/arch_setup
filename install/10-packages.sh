#!/usr/bin/env bash
# 10-packages.sh - install core and everyday CLI official-repository packages.
#
# Idempotent: pacman --needed skips what is already installed.
# Set SKIP_UPGRADE=1 to avoid the full system upgrade on repeated runs.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=../config/packages.conf
source "${PROJECT_ROOT}/config/packages.conf"
init_logging 10-packages

require_non_root
require_sudo
require_arch

SKIP_UPGRADE="${SKIP_UPGRADE:-0}"

if [[ "${SKIP_UPGRADE}" == "1" ]]; then
  warn "SKIP_UPGRADE=1: not running pacman -Syu."
else
  pacman_upgrade
fi

pacman_install "${CORE_PKGS[@]}" "${CLI_PKGS[@]}"

section "Verifying core packages"
MISSING=()
for p in "${CORE_PKGS[@]}"; do
  if pkg_present "${p}"; then
    v="$(pkg_version "${p}")"
    [[ -n "${v}" ]] || v="group"
    log "ok: ${p} ${v}"
  else
    err "missing: ${p}"
    MISSING+=("${p}")
  fi
done

section "Verifying CLI packages"
for p in "${CLI_PKGS[@]}"; do
  if pkg_present "${p}"; then
    v="$(pkg_version "${p}")"
    [[ -n "${v}" ]] || v="group"
    log "ok: ${p} ${v}"
  else
    err "missing: ${p}"
    MISSING+=("${p}")
  fi
done

if [[ "${#MISSING[@]}" -gt 0 ]]; then
  die "Packages still missing after install: ${MISSING[*]}"
fi

section "Verifying required commands"
MISSING_CMDS=()
for c in "${REQUIRED_COMMANDS[@]}" "${CLI_COMMANDS[@]}"; do
  if has_command "${c}"; then
    log "ok: ${c} -> $(command -v "${c}")"
  else
    err "missing command: ${c}"
    MISSING_CMDS+=("${c}")
  fi
done

if [[ "${#MISSING_CMDS[@]}" -gt 0 ]]; then
  die "Required commands missing: ${MISSING_CMDS[*]}"
fi

section "Package install complete"
info "Installed/verified ${#CORE_PKGS[@]} core + ${#CLI_PKGS[@]} CLI package entries."
