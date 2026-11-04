#!/usr/bin/env bash
# 60-gpu.sh - install Mesa/Vulkan/VA-API drivers for the detected GPU.
#
# Supports VirtualBox/VMware guests, NVIDIA, AMD and Intel, including hybrids.
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
VIRT="$(systemd-detect-virt 2>/dev/null || echo none)"
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

if [[ "${HAS_VMWARE}" -eq 1 ]]; then
  section "Virtual machine GPU (VMSVGA/vmwgfx)"
  pacman_install libva libva-utils
  log "The vmwgfx kernel driver and Mesa handle Wayland; no vendor driver is needed."
fi

if [[ "${HAS_NVIDIA}" -eq 1 ]]; then
  section "NVIDIA GPU"
  NVIDIA_PKGS=()

  if pkg_present linux; then
    if pkg_available nvidia-open; then
      NVIDIA_PKGS+=(nvidia-open)
    else
      NVIDIA_PKGS+=(nvidia)
    fi
  fi

  if pkg_present linux-lts; then
    if pkg_available nvidia-open-lts; then
      NVIDIA_PKGS+=(nvidia-open-lts)
    else
      NVIDIA_PKGS+=(nvidia-lts)
    fi
  fi

  NEED_DKMS=0
  pkg_present linux-zen && NEED_DKMS=1
  pkg_present linux-hardened && NEED_DKMS=1
  [[ "${#NVIDIA_PKGS[@]}" -eq 0 ]] && NEED_DKMS=1

  if [[ "${NEED_DKMS}" -eq 1 ]]; then
    if pkg_available nvidia-open-dkms; then
      NVIDIA_PKGS+=(nvidia-open-dkms)
    else
      NVIDIA_PKGS+=(nvidia-dkms)
    fi
    NVIDIA_PKGS+=(dkms)
    pkg_present linux && NVIDIA_PKGS+=(linux-headers)
    pkg_present linux-lts && NVIDIA_PKGS+=(linux-lts-headers)
    pkg_present linux-zen && NVIDIA_PKGS+=(linux-zen-headers)
    pkg_present linux-hardened && NVIDIA_PKGS+=(linux-hardened-headers)
  fi

  NVIDIA_PKGS+=(nvidia-utils nvidia-settings libva-nvidia-driver)
  pacman_install "${NVIDIA_PKGS[@]}"

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
  pacman_install vulkan-radeon libva-mesa-driver mesa-vdpau
fi

if [[ "${HAS_INTEL}" -eq 1 ]]; then
  section "Intel GPU"
  pacman_install vulkan-intel intel-media-driver
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
  run sudo -n mkinitcpio -P
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
