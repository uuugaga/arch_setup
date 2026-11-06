#!/usr/bin/env bash
# 60-gpu.sh - install Mesa/Vulkan/VA-API drivers for the detected GPU.
#
# Supports VirtualBox/VMware guests, NVIDIA, AMD and Intel, including hybrids.
# Supports exactly one kernel: the standard Arch 'linux' package. Do not add
# DKMS or linux-lts/zen/hardened branches.
# WANT_32BIT=1 adds 32-bit libraries (needed by Steam).
# Does not reboot. NVIDIA modeset is applied on the next boot.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
init_logging 60-gpu

require_non_root
require_sudo
require_arch

WANT_32BIT="${WANT_32BIT:-0}"
VIRT="$(systemd-detect-virt 2>/dev/null)" || VIRT="none"
GPU_INFO="$(lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' || true)"

section "Detected environment"
log "virtualization: ${VIRT}"
log "GPU:"
printf '%s\n' "${GPU_INFO:-  (none detected)}"

HAS_NVIDIA=0
HAS_AMD=0
HAS_INTEL=0
HAS_VMWARE=0

grep -Eiq 'nvidia' <<< "${GPU_INFO}" && HAS_NVIDIA=1
grep -Eiq 'amd|radeon|advanced micro devices' <<< "${GPU_INFO}" && HAS_AMD=1
grep -Eiq 'intel' <<< "${GPU_INFO}" && HAS_INTEL=1
grep -Eiq 'vmware|virtualbox|svga' <<< "${GPU_INFO}" && HAS_VMWARE=1
[[ "${VIRT}" == "oracle" ]] && HAS_VMWARE=1

pacman_install pciutils mesa mesa-utils

install_available_pkgs() {
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

if [[ "${HAS_VMWARE}" -eq 1 ]]; then
  section "Virtual machine GPU (VMSVGA/vmwgfx)"
  pacman_install libva libva-utils
  log "The vmwgfx kernel driver and Mesa handle Wayland; no vendor driver is needed."
fi

if [[ "${HAS_NVIDIA}" -eq 1 ]]; then
  section "NVIDIA GPU"

  # This project supports exactly one kernel: the standard Arch 'linux'
  # package. The open modules are the only NVIDIA kernel modules in the current
  # official repositories; legacy Pascal/Maxwell cards need an out-of-tree
  # driver instead.
  pkg_present linux \
    || die "NVIDIA path requires the standard 'linux' kernel package."
  NVIDIA_MODULE_PKG=nvidia-open
  pkg_available "${NVIDIA_MODULE_PKG}" \
    || die "${NVIDIA_MODULE_PKG} is not available in the enabled repositories; install a legacy NVIDIA driver manually."

  NVIDIA_MODEL="$(grep -i nvidia <<< "${GPU_INFO}" | head -n 1 || true)"
  if grep -Eiq 'GTX[[:space:]]*(6|7|8|9|10)|GT[[:space:]]*(6|7|8|9|10)|Quadro[[:space:]]*(K|M|P)|Tesla[[:space:]]*(K|M|P)|Pascal|Maxwell|Kepler' <<< "${NVIDIA_MODEL}"; then
    die "Detected a pre-Turing NVIDIA GPU (${NVIDIA_MODEL}). nvidia-open does not support it; install a legacy NVIDIA driver manually."
  fi

  NVIDIA_PKGS=(
    "${NVIDIA_MODULE_PKG}"
    nvidia-utils
    nvidia-settings
    libva-nvidia-driver
    libva-utils
    vulkan-icd-loader
    libxnvctrl
  )
  # Hybrid laptops need prime-run for NVIDIA render offload.
  if [[ "${HAS_INTEL}" -eq 1 || "${HAS_AMD}" -eq 1 ]]; then
    NVIDIA_PKGS+=(nvidia-prime)
  fi
  pacman_install "${NVIDIA_PKGS[@]}"
  install_available_pkgs linux-firmware-nvidia

  MODPROBE_TMP="$(mktemp)"
  cat > "${MODPROBE_TMP}" <<'EOF'
# managed-by: arch-niri-setup
options nvidia_drm modeset=1
options nvidia_drm fbdev=1
EOF
  deploy_system_file "${MODPROBE_TMP}" "/etc/modprobe.d/nvidia-drm.conf" 1 || true
  rm -f "${MODPROBE_TMP}"
fi

if [[ "${HAS_AMD}" -eq 1 ]]; then
  section "AMD GPU"
  # mesa already provides libva-mesa-driver and the radeonsi VA-API driver.
  # mesa-vdpau was removed from the repositories; VA-API is the supported path.
  pacman_install vulkan-radeon libva-utils
  install_available_pkgs linux-firmware-amdgpu linux-firmware-radeon
fi

if [[ "${HAS_INTEL}" -eq 1 ]]; then
  section "Intel GPU"
  # intel-media-driver covers Gen9+; libva-intel-driver keeps older i965
  # hardware working. They can coexist.
  pacman_install vulkan-intel intel-media-driver libva-intel-driver libva-utils
  install_available_pkgs linux-firmware-intel
fi

if [[ "${HAS_NVIDIA}" -eq 0 && "${HAS_AMD}" -eq 0 && "${HAS_INTEL}" -eq 0 && "${HAS_VMWARE}" -eq 0 ]]; then
  warn "No known GPU detected. Mesa was installed, but review this script manually."
fi

if [[ "${WANT_32BIT}" == "1" ]]; then
  section "32-bit graphics libraries"
  PACMAN32=(lib32-mesa lib32-vulkan-icd-loader)
  [[ "${HAS_NVIDIA}" -eq 1 ]] && PACMAN32+=(lib32-nvidia-utils)
  [[ "${HAS_AMD}" -eq 1 ]] && PACMAN32+=(lib32-vulkan-radeon)
  [[ "${HAS_INTEL}" -eq 1 ]] && PACMAN32+=(lib32-vulkan-intel)
  # VMSVGA/vmwgfx has no hardware Vulkan driver. Lavapipe gives 32-bit
  # applications a software Vulkan device for diagnostics and light use.
  [[ "${HAS_VMWARE}" -eq 1 ]] && PACMAN32+=(lib32-vulkan-swrast)
  pacman_install "${PACMAN32[@]}"
fi

if [[ "${HAS_NVIDIA}" -eq 1 ]]; then
  section "Regenerating initramfs for NVIDIA"
  run as_root mkinitcpio -p linux
fi

section "GPU step complete"
info "Virtualization: ${VIRT}"
info "NVIDIA=${HAS_NVIDIA} AMD=${HAS_AMD} Intel=${HAS_INTEL} VMware=${HAS_VMWARE}"
info "Verify after reboot:"
info "  lspci -k | grep -A 4 -Ei 'VGA|3D|Display'"
info "  eglinfo -B 2>/dev/null | head"
if [[ "${HAS_NVIDIA}" -eq 1 ]]; then
  info "  nvidia-smi"
fi
