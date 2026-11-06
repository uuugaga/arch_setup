#!/usr/bin/env bash
# 55-snapshots.sh - manual-only Btrfs snapshots with Snapper + Btrfs Assistant.
#
# Intentionally does NOT install snap-pac or grub-btrfs:
#   - no automatic pre/post pacman snapshots
#   - no GRUB snapshot menu / grub-btrfsd regeneration
#   - timeline timers are disabled and TIMELINE_CREATE is set to no
#
# The first run creates one baseline manual snapshot. Later runs keep it and do
# not create duplicates; use `snapper -c root create` for new snapshots.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=../config/packages.conf
source "${PROJECT_ROOT}/config/packages.conf"
init_logging 55-snapshots

require_non_root
require_sudo
require_arch

ROOT_FS="$(findmnt -no FSTYPE / 2>/dev/null || echo unknown)"
if [[ "${ROOT_FS}" != "btrfs" ]]; then
  die "Root filesystem is '${ROOT_FS}', not btrfs. This module is Btrfs-only."
fi

section "Installing Snapper and Btrfs Assistant"
pacman_install snapper btrfs-assistant

section "Creating the snapper root config"
if [[ -f /etc/snapper/configs/root ]]; then
  log "snapper root config already exists"
else
  run as_root snapper -c root create-config /
fi

section "Disabling automatic snapshots"
for timer in snapper-timeline.timer snapper-cleanup.timer snapper-boot.timer; do
  if systemctl list-unit-files "${timer}" --no-legend 2>/dev/null | grep -q "${timer}"; then
    run as_root systemctl disable --now "${timer}" || warn "Could not disable ${timer}"
  else
    log "timer not present: ${timer}"
  fi
done

run as_root snapper -c root set-config TIMELINE_CREATE=no
run as_root snapper -c root set-config NUMBER_LIMIT=5
run as_root snapper -c root set-config NUMBER_LIMIT_IMPORTANT=3

if pkg_present snap-pac; then
  warn "snap-pac is installed; it creates automatic pacman snapshots."
  warn "The project does not install it. Remove it if you want manual-only snapshots."
fi

section "Creating the baseline manual snapshot"
# Idempotent: keep the first baseline; use snapper create for a new one.
if as_root snapper -c root list --columns description 2>/dev/null | grep -qx "baseline-manual"; then
  log "baseline-manual already exists; keeping it"
else
  run as_root snapper -c root create \
    --description "baseline-manual" \
    --userdata important=yes
fi

section "Snapshot status"
run as_root snapper -c root list
for timer in snapper-timeline.timer snapper-cleanup.timer snapper-boot.timer; do
  if systemctl list-unit-files "${timer}" --no-legend 2>/dev/null | grep -q "${timer}"; then
    printf '%s: %s\n' "${timer}" "$(systemctl is-enabled "${timer}" 2>/dev/null || true)"
  fi
done

if has_command btrfs-assistant; then
  log "GUI: btrfs-assistant -> $(command -v btrfs-assistant)"
else
  warn "btrfs-assistant command not found"
fi

run as_root btrfs filesystem usage /

section "Snapshot step complete"
info "Automatic snapshots are disabled (TIMELINE_CREATE=no, timers disabled)."
info "Manual create: sudo snapper -c root create --description 'before update'"
info "Manual list:   sudo snapper -c root list"
info "GUI:           btrfs-assistant"
info "grub-btrfs and snap-pac were intentionally NOT installed."
