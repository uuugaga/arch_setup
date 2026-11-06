#!/usr/bin/env bash
# 00-preflight.sh - read-only environment inspection.
#
# Writes:
#   logs/preflight.md    Markdown report (stable path)
#   logs/preflight.env   Machine-readable summary for orchestration
#   logs/preflight-*.log Full transcript
#
# This step never installs anything. It exits 1 only on critical blockers.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=../config/packages.conf
source "${PROJECT_ROOT}/config/packages.conf"
init_logging preflight notrap
detect_install_env

REPORT="${LOG_DIR}/preflight.md"
ENVFILE="${LOG_DIR}/preflight.env"
: > "${REPORT}"

CRITICAL=0
WARNINGS=0

md() {
  printf '%s\n' "$*" >> "${REPORT}"
}

md_row() {
  local a b c
  a="$(printf '%s' "${1:-}" | tr '|\n' '//')"
  b="$(printf '%s' "${2:-}" | tr '|\n' '//')"
  c="$(printf '%s' "${3:--}" | tr '|\n' '//')"
  printf '| %s | %s | %s |\n' "${a}" "${b}" "${c}" >> "${REPORT}"
}

critical() {
  CRITICAL=$((CRITICAL + 1))
  err "CRITICAL: $*"
  md "- **CRITICAL**: $*"
}

warning() {
  WARNINGS=$((WARNINGS + 1))
  warn "$*"
  md "- **WARN**: $*"
}

passed() {
  md "- OK: $*"
}

section "Collecting system information"

HOSTNAME_V="$(cat /etc/hostname 2>/dev/null || hostname 2>/dev/null || echo unknown)"
VIRT="$(systemd-detect-virt 2>/dev/null)" || VIRT="none"
KERNEL="$(uname -r)"
ARCH="$(uname -m)"
USER_NAME="$(id -un)"
USER_GROUPS="$(id -Gn 2>/dev/null || echo unknown)"
IS_ROOT="no"
[[ "${EUID}" -eq 0 ]] && IS_ROOT="yes"
SUDO_OK="no"
if sudo -n true 2>/dev/null; then
  SUDO_OK="yes"
fi
if [[ "${SUDO_OK}" == "yes" ]]; then
  SUDO_USER_RESULT="$(sudo -n whoami 2>/dev/null || echo failed)"
else
  SUDO_USER_RESULT="n/a (interactive)"
fi
OS_PRETTY="$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || echo unknown)"
SESSION_TYPE="${XDG_SESSION_TYPE:-unset}"
DEFAULT_TARGET="$(systemctl get-default 2>/dev/null || echo unknown)"
SNAPSHOT_NAME="${VBOX_SNAPSHOT_NAME:-not-provided}"

# Network
IP_BRIEF="$(ip -brief address 2>/dev/null | tr '\n' '; ' || echo none)"
DEFAULT_ROUTE="$(ip route show default 2>/dev/null | head -n1 || true)"
DNS_SERVERS="$(grep -h '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' ' || true)"
HTTP_CODE="$(curl -fsS -m 10 -o /dev/null -w '%{http_code}' https://archlinux.org/ 2>/dev/null || echo FAIL)"
PING_OK="no"
ping -c1 -W3 archlinux.org >/dev/null 2>&1 && PING_OK="yes"

# Pacman
PACMAN_LOCK="absent"
[[ -e /var/lib/pacman/db.lck ]] && PACMAN_LOCK="PRESENT"
PACMAN_SYNC_AGE="$(stat -c '%y' /var/lib/pacman/sync/core.db 2>/dev/null || echo never)"
PACMAN_KEYRING="$(pacman -Q archlinux-keyring 2>/dev/null | awk '{print $2}' || echo missing)"
TOTAL_PKGS="$(pacman -Q 2>/dev/null | wc -l)"
FOREIGN_PKGS="$(pacman -Qm 2>/dev/null | wc -l)"
UPGRADABLE="$(pacman -Qu 2>/dev/null | wc -l)"

# Disk / memory
ROOT_TOTAL="$(df -h --output=size / 2>/dev/null | tail -n1 | tr -d ' ' || echo unknown)"
ROOT_AVAIL="$(df -h --output=avail / 2>/dev/null | tail -n1 | tr -d ' ' || echo unknown)"
ROOT_AVAIL_GB="$(df --output=avail -BG / 2>/dev/null | tail -n1 | tr -dc '0-9' || echo 0)"
MEM_TOTAL="$(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo unknown)"

# Graphics
GPU_LSPCI="$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' | tr '\n' '; ' || echo unknown)"
GPU_VENDOR="unknown"
if grep -qi 'nvidia' <<< "${GPU_LSPCI}"; then
  GPU_VENDOR="nvidia"
elif grep -Eiq 'amd|radeon|advanced micro devices' <<< "${GPU_LSPCI}"; then
  GPU_VENDOR="amd"
elif grep -qi 'intel' <<< "${GPU_LSPCI}"; then
  GPU_VENDOR="intel"
elif grep -Eiqi 'vmware|virtualbox|svga' <<< "${GPU_LSPCI}"; then
  GPU_VENDOR="vmware"
fi
GPU_MODULES="$(lsmod 2>/dev/null | grep -E '^(vmwgfx|virtio_gpu|amdgpu|i915|nouveau|nvidia)' | awk '{print $1}' | tr '\n' ' ' || true)"
DRI_DEVICES="$(ls /dev/dri 2>/dev/null | tr '\n' ' ' || echo none)"
MESA_VERSION="$(pacman -Q mesa 2>/dev/null | awk '{print $2}' || echo missing)"

# Display managers
declare -A DM_STATE=()
for dm in gdm lightdm sddm ly greetd; do
  DM_STATE["${dm}"]="$(systemctl is-enabled "${dm}" 2>/dev/null | head -n1 || true)"
  [[ -n "${DM_STATE[${dm}]}" ]] || DM_STATE["${dm}"]="not-found"
done
GREETD_CONFIG="none"
[[ -f /etc/greetd/config.toml ]] && GREETD_CONFIG="exists"
GREETER_USER="none"
getent passwd greeter >/dev/null 2>&1 && GREETER_USER="exists"
DM_LINK="$(ls -l /etc/systemd/system/display-manager.service 2>/dev/null || echo none)"

# Niri / desktop state
HAS_NIRI="no"
pkg_present niri && HAS_NIRI="yes"
HAS_PARU="no"
PARU_PATH=""
if has_command paru; then
  HAS_PARU="yes"
  PARU_PATH="$(command -v paru)"
elif pkg_present paru; then
  HAS_PARU="yes"
  PARU_PATH="pacman:paru (not in PATH)"
fi
NIRI_RUNNING="no"
pgrep -x niri >/dev/null 2>&1 && NIRI_RUNNING="yes"
WAYLAND_SESSIONS="$(ls /usr/share/wayland-sessions 2>/dev/null | tr '\n' ' ' || echo none)"
XSESSIONS="$(ls /usr/share/xsessions 2>/dev/null | tr '\n' ' ' || echo none)"
USER_CONFIGS="$(ls -A "${HOME}/.config" 2>/dev/null | tr '\n' ' ' || echo empty)"

# Locale
LOCALE_VALUE="$(locale 2>/dev/null | awk -F= '/^LANG=/{print $2; exit}' || true)"
LOCALE_CONF="$(cat /etc/locale.conf 2>/dev/null | tr '\n' ' ' || echo none)"
LOCALES_AVAILABLE="$(locale -a 2>/dev/null | tr '\n' ' ' || echo none)"

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
{
  echo "# Arch Linux Niri Preflight Report"
  echo
  echo "- Generated: $(date -Is)"
  echo "- Host: \`${HOSTNAME_V}\`"
  echo "- Project: \`${PROJECT_ROOT}\`"
  echo "- Log: \`${LOG_FILE}\`"
  echo
} >> "${REPORT}"

echo "## System" >> "${REPORT}"
echo >> "${REPORT}"
echo "| Item | Value |" >> "${REPORT}"
echo "|---|---|" >> "${REPORT}"
md_row "OS" "PRETTY_NAME" "${OS_PRETTY}"
md_row "Kernel" "uname -r" "${KERNEL}"
md_row "Architecture" "uname -m" "${ARCH}"
md_row "User" "id -un" "${USER_NAME}"
md_row "Groups" "id -Gn" "${USER_GROUPS}"
md_row "Running as root" "EUID" "${IS_ROOT}"
md_row "Install environment" "INSTALL_ENV" "${INSTALL_ENV}"
md_row "Sudo policy" "vm=passwordless, baremetal=interactive" "-"
md_row "Passwordless sudo" "sudo -n true" "${SUDO_OK}"
md_row "sudo -n whoami" "result" "${SUDO_USER_RESULT}"
md_row "Virtualization" "systemd-detect-virt" "${VIRT}"
md_row "Snapshot (host-provided)" "VBOX_SNAPSHOT_NAME" "${SNAPSHOT_NAME}"
md_row "Session type" "XDG_SESSION_TYPE" "${SESSION_TYPE}"
md_row "Default systemd target" "systemctl get-default" "${DEFAULT_TARGET}"
echo >> "${REPORT}"

echo "## Network" >> "${REPORT}"
echo >> "${REPORT}"
echo "| Item | Value |" >> "${REPORT}"
echo "|---|---|" >> "${REPORT}"
md_row "Interfaces" "ip -brief address" "${IP_BRIEF}"
md_row "Default route" "ip route" "${DEFAULT_ROUTE}"
md_row "DNS" "/etc/resolv.conf" "${DNS_SERVERS}"
md_row "HTTPS archlinux.org" "curl" "${HTTP_CODE}"
md_row "ICMP archlinux.org" "ping" "${PING_OK}"
echo >> "${REPORT}"

echo "## Pacman" >> "${REPORT}"
echo >> "${REPORT}"
echo "| Item | Value |" >> "${REPORT}"
echo "|---|---|" >> "${REPORT}"
md_row "Database lock" "/var/lib/pacman/db.lck" "${PACMAN_LOCK}"
md_row "Last sync" "core.db mtime" "${PACMAN_SYNC_AGE}"
md_row "Keyring" "archlinux-keyring" "${PACMAN_KEYRING}"
md_row "Installed packages" "pacman -Q" "${TOTAL_PKGS}"
md_row "Foreign packages" "pacman -Qm" "${FOREIGN_PKGS}"
md_row "Upgradable" "pacman -Qu" "${UPGRADABLE}"
echo >> "${REPORT}"

echo "## Storage / Memory" >> "${REPORT}"
echo >> "${REPORT}"
echo "| Item | Value |" >> "${REPORT}"
echo "|---|---|" >> "${REPORT}"
md_row "Root size" "df -h /" "${ROOT_TOTAL}"
md_row "Root available" "df -h /" "${ROOT_AVAIL}"
md_row "Memory" "free -h" "${MEM_TOTAL}"
echo >> "${REPORT}"

echo "## Graphics" >> "${REPORT}"
echo >> "${REPORT}"
echo "| Item | Value |" >> "${REPORT}"
echo "|---|---|" >> "${REPORT}"
md_row "GPU (lspci)" "VGA/3D/Display" "${GPU_LSPCI}"
md_row "Detected vendor" "heuristic" "${GPU_VENDOR}"
md_row "Loaded modules" "lsmod" "${GPU_MODULES:-none}"
md_row "/dev/dri" "list" "${DRI_DEVICES}"
md_row "Mesa" "pacman -Q mesa" "${MESA_VERSION}"
echo >> "${REPORT}"

echo "## Session / Display Manager" >> "${REPORT}"
echo >> "${REPORT}"
echo "| Item | Value |" >> "${REPORT}"
echo "|---|---|" >> "${REPORT}"
for dm in gdm lightdm sddm ly greetd; do
  md_row "${dm}.service" "systemctl is-enabled" "${DM_STATE[${dm}]}"
done
md_row "display-manager.service" "readlink" "${DM_LINK}"
md_row "/etc/greetd/config.toml" "file" "${GREETD_CONFIG}"
md_row "greeter user" "getent passwd greeter" "${GREETER_USER}"
md_row "Niri running" "pgrep -x niri" "${NIRI_RUNNING}"
md_row "Wayland sessions" "/usr/share/wayland-sessions" "${WAYLAND_SESSIONS}"
md_row "X11 sessions" "/usr/share/xsessions" "${XSESSIONS}"
md_row "~/.config entries" "ls -A" "${USER_CONFIGS}"
md_row "LANG" "locale" "${LOCALE_VALUE:-unset}"
md_row "/etc/locale.conf" "content" "${LOCALE_CONF}"
md_row "Available locales" "locale -a" "${LOCALES_AVAILABLE}"
echo >> "${REPORT}"

echo "## Existing project-managed configs" >> "${REPORT}"
echo >> "${REPORT}"
echo "| File | State | Notes |" >> "${REPORT}"
echo "|---|---|---|" >> "${REPORT}"
for f in \
  "${HOME}/.config/niri/config.kdl" \
  "${HOME}/.config/waybar/config.jsonc" \
  "${HOME}/.config/waybar/style.css" \
  "${HOME}/.config/fuzzel/fuzzel.ini" \
  "${HOME}/.config/mako/config" \
  "${HOME}/.config/alacritty/alacritty.toml"; do
  if [[ -e "${f}" ]]; then
    if grep -qF "${MARKER}" "${f}" 2>/dev/null; then
      md_row "${f}" "managed by arch-niri-setup"
    else
      md_row "${f}" "UNMANAGED (will not be overwritten without --force)"
      warning "unmanaged config exists: ${f}"
    fi
  else
    md_row "${f}" "absent"
  fi
done
echo >> "${REPORT}"

echo "## Package status" >> "${REPORT}"
echo >> "${REPORT}"
echo "| Package | Status | Version |" >> "${REPORT}"
echo "|---|---|---|" >> "${REPORT}"
MISSING_PKGS=0
for p in "${CORE_PKGS[@]}"; do
  if pkg_present "${p}"; then
    v="$(pkg_version "${p}")"
    [[ -n "${v}" ]] || v="group"
    md_row "${p}" "installed" "${v}"
  else
    md_row "${p}" "MISSING" "-"
    MISSING_PKGS=$((MISSING_PKGS + 1))
  fi
done
echo >> "${REPORT}"

echo "## Critical checks" >> "${REPORT}"
echo >> "${REPORT}"

if [[ "${IS_ROOT}" == "yes" ]]; then
  critical "Script must run as the desktop user, not root."
else
  passed "Running as normal user: ${USER_NAME}"
fi

if [[ -f /etc/arch-release ]]; then
  passed "Arch Linux detected."
else
  critical "This is not Arch Linux."
fi

if [[ "${INSTALL_ENV}" == "vm" ]]; then
  if [[ "${SUDO_OK}" == "yes" ]]; then
    passed "VM/test: passwordless sudo works (sudo -n whoami = ${SUDO_USER_RESULT})."
  else
    critical "VM/test install: passwordless sudo is required ('sudo -n true' failed)."
  fi
else
  if [[ "${SUDO_OK}" == "yes" ]]; then
    warning "Bare metal: passwordless sudo is enabled; production policy expects interactive sudo."
  else
    passed "Bare metal: interactive sudo (no passwordless rule required)."
  fi
fi

if [[ "${PACMAN_LOCK}" == "absent" ]]; then
  passed "Pacman database lock is absent."
else
  critical "Pacman database is locked (/var/lib/pacman/db.lck)."
fi

if [[ "${HTTP_CODE}" == "200" ]]; then
  passed "HTTPS to archlinux.org works."
else
  critical "Cannot reach https://archlinux.org (HTTP ${HTTP_CODE})."
fi

if [[ "${ROOT_AVAIL_GB}" -ge 3 ]]; then
  passed "At least 3 GiB free on / (${ROOT_AVAIL})."
else
  critical "Less than 3 GiB free on / (${ROOT_AVAIL})."
fi

if [[ "${GPU_VENDOR}" == "vmware" || "${GPU_VENDOR}" == "nvidia" || "${GPU_VENDOR}" == "amd" || "${GPU_VENDOR}" == "intel" ]]; then
  passed "Recognized GPU vendor: ${GPU_VENDOR}."
else
  warning "GPU vendor not recognized; 60-gpu.sh will need manual review."
fi

DRI_CARD="$(find /dev/dri -maxdepth 1 -type c -name 'card*' -print -quit 2>/dev/null || true)"
if [[ -n "${DRI_CARD}" ]]; then
  passed "${DRI_CARD} exists (Wayland can use DRM)."
else
  critical "No /dev/dri/card* device; a Wayland session cannot start."
fi

if [[ "${SNAPSHOT_NAME}" == "not-provided" ]]; then
  if [[ "${VIRT}" == "none" ]]; then
    passed "Bare metal: no host snapshot required."
  else
    warning "No snapshot name was passed. Verify the virtualization host snapshot before installing."
  fi
else
  passed "Host snapshot reported: ${SNAPSHOT_NAME}."
fi

if [[ "${MISSING_PKGS}" -gt 0 ]]; then
  passed "Core packages missing: ${MISSING_PKGS} (expected before 10-packages.sh)."
else
  passed "All core packages already installed."
fi

if [[ "${HAS_PARU}" == "yes" ]]; then
  passed "paru is installed (${PARU_PATH})."
else
  passed "paru is not installed yet (expected; 20-paru.sh will build it)."
fi

echo >> "${REPORT}"

STATUS="ok"
[[ "${CRITICAL}" -gt 0 ]] && STATUS="failed"

{
  echo "## Verdict"
  echo
  echo "- Critical failures: **${CRITICAL}**"
  echo "- Warnings: **${WARNINGS}**"
  echo "- Missing core packages: **${MISSING_PKGS}**"
  echo "- Status: **${STATUS}**"
  echo
  if [[ "${STATUS}" == "ok" ]]; then
    echo "Preflight passed. Proceed with \`install/10-packages.sh\`."
  else
    echo "Preflight failed. Resolve critical items before installing."
  fi
} >> "${REPORT}"

{
  echo "PREFLIGHT_STATUS=${STATUS}"
  echo "PREFLIGHT_CRITICAL=${CRITICAL}"
  echo "PREFLIGHT_WARNINGS=${WARNINGS}"
  echo "PREFLIGHT_MISSING_PKGS=${MISSING_PKGS}"
  echo "VIRT=${VIRT}"
  echo "INSTALL_ENV=${INSTALL_ENV}"
  echo "GPU_VENDOR=${GPU_VENDOR}"
  echo "ARCH=${ARCH}"
  echo "HAS_NIRI=${HAS_NIRI}"
  echo "HAS_PARU=${HAS_PARU}"
  echo "SUDO_OK=${SUDO_OK}"
  echo "ROOT_AVAIL=${ROOT_AVAIL}"
} > "${ENVFILE}"

section "Preflight result"
info "Report: ${REPORT}"
info "Summary: ${ENVFILE}"
info "Critical: ${CRITICAL}  Warnings: ${WARNINGS}  Missing core packages: ${MISSING_PKGS}"

if [[ "${CRITICAL}" -gt 0 ]]; then
  err "Preflight failed with ${CRITICAL} critical issue(s). See ${REPORT}"
  exit 1
fi

info "Preflight passed."
