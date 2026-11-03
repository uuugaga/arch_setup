#!/usr/bin/env bash
# 30-niri.sh - deploy niri config and configure greetd + tuigreet.
#
# Does not start greetd. Starting the display manager is a separate,
# approval-gated action because it takes over a VT.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
init_logging 30-niri

require_non_root
require_sudo
require_arch

has_command niri || die "niri is not installed; run install/10-packages.sh first."
has_command niri-session || die "niri-session is missing; check the niri package."
has_command greetd || die "greetd is not installed; run install/10-packages.sh first."
has_command tuigreet || die "tuigreet is not installed; run install/10-packages.sh first."

FORCE="${FORCE:-0}"
NIRI_SRC="${DOTFILES_DIR}/niri/config.kdl"
NIRI_DEST="${HOME}/.config/niri/config.kdl"

section "Validating repository niri config"
run niri validate -c "${NIRI_SRC}"

section "Deploying niri config"
rc=0
deploy_file "${NIRI_SRC}" "${NIRI_DEST}" "${FORCE}" 644 || rc=$?
if [[ "${rc}" -eq 2 ]]; then
  warn "Existing niri config was kept. Rerun with FORCE=1 to replace it."
  die "Cannot continue with an unmanaged niri config."
elif [[ "${rc}" -ne 0 ]]; then
  die "Failed to deploy niri config (exit ${rc})."
fi

section "Validating deployed niri config"
run niri validate -c "${NIRI_DEST}"

section "Configuring greetd"
getent passwd greeter >/dev/null 2>&1 || die "The 'greeter' user is missing; reinstall greetd."

# The greetd package ships its own unmanaged default; force replaces it after
# taking a backup under /var/backups/arch-niri-setup/<timestamp>/.
rc=0
deploy_system_file "${DOTFILES_DIR}/greetd/config.toml" "/etc/greetd/config.toml" 1 || rc=$?
if [[ "${rc}" -ne 0 ]]; then
  die "Failed to deploy /etc/greetd/config.toml (exit ${rc})."
fi

section "Enabling services"
ensure_service_enabled greetd.service
for other_dm in sddm.service gdm.service lightdm.service ly.service; do
  disable_service_if_enabled "${other_dm}"
done
run sudo -n systemctl set-default graphical.target

section "Checking XWayland support"
if has_command xwayland-satellite; then
  log "ok: xwayland-satellite -> $(command -v xwayland-satellite)"
  log "niri launches xwayland-satellite automatically when it is in PATH."
else
  warn "xwayland-satellite is not installed; X11 apps will not run."
fi

section "Niri step complete"
info "greetd is enabled but NOT started."
info "Start it when you are ready to test the graphical console:"
info "  sudo systemctl start greetd"
