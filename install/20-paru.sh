#!/usr/bin/env bash
# 20-paru.sh - build and install paru as the normal user.
#
# Never runs makepkg or paru as root. Never runs `sudo paru`.
# Idempotent: exits early when paru is already installed and working.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
init_logging 20-paru

require_non_root
require_arch

if has_command paru; then
  section "paru is already installed"
  paru --version
  info "Nothing to do."
  exit 0
fi

require_sudo

section "Installing build prerequisites"
pacman_install base-devel git

BUILD_ROOT="${HOME}/build"
PARU_DIR="${BUILD_ROOT}/paru"
mkdir -p "${BUILD_ROOT}"

if [[ -d "${PARU_DIR}/.git" ]]; then
  section "Updating existing paru checkout"
  if ! git -C "${PARU_DIR}" pull --ff-only; then
    warn "git pull failed; rebuilding from the existing checkout."
  fi
elif [[ -e "${PARU_DIR}" ]]; then
  die "${PARU_DIR} exists but is not a git checkout. Move it away and rerun."
else
  section "Cloning paru from AUR"
  run git clone --depth 1 https://aur.archlinux.org/paru.git "${PARU_DIR}"
fi

section "Building paru with makepkg (as ${USER})"
(
  cd "${PARU_DIR}"
  # -s installs missing build dependencies through sudo pacman.
  # -i installs the built package. This must never run as root.
  run makepkg -si --noconfirm
)

section "Verifying paru"
has_command paru || die "paru was not installed into PATH."
paru --version

info "paru installed. AUR helpers must still be run as the normal user."
info "This project never calls 'sudo paru'."
