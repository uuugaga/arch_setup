#!/usr/bin/env bash
# 90-validate.sh - post-install validation.
#
# This is a read-only check. It never installs or restarts anything.
# It cannot prove that a Wayland session renders; that requires the graphical
# console. The report marks that limitation explicitly.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=../config/packages.conf
source "${PROJECT_ROOT}/config/packages.conf"
init_logging validate

require_non_root
require_arch

REPORT="${LOG_DIR}/validate.md"
: > "${REPORT}"
PASS=0
WARN=0
FAIL=0

md() {
  printf '%s\n' "$*" >> "${REPORT}"
}

result() {
  local name="$1"
  local status="$2"
  local detail="$3"
  name="$(printf '%s' "${name}" | tr '|\n' '//')"
  detail="$(printf '%s' "${detail}" | tr '|\n' '//')"
  printf '| %s | %s | %s |\n' "${name}" "${status}" "${detail}" >> "${REPORT}"
  case "${status}" in
    PASS) PASS=$((PASS + 1)); log "PASS: ${name} - ${detail}" ;;
    WARN) WARN=$((WARN + 1)); warn "WARN: ${name} - ${detail}" ;;
    FAIL) FAIL=$((FAIL + 1)); err "FAIL: ${name} - ${detail}" ;;
  esac
}

{
  echo "# Niri Desktop Validation"
  echo
  echo "- Generated: $(date -Is)"
  echo "- Host: \`$(cat /etc/hostname 2>/dev/null || echo unknown)\`"
  echo "- Project: \`${PROJECT_ROOT}\`"
  echo
  echo "## Checks"
  echo
  echo "| Check | Result | Detail |"
  echo "|---|---|---|"
} >> "${REPORT}"

section "Binary checks"
for c in "${REQUIRED_COMMANDS[@]}"; do
  if has_command "${c}"; then
    result "binary:${c}" PASS "$(command -v "${c}")"
  else
    result "binary:${c}" FAIL "not found in PATH"
  fi
done

section "Package checks"
for p in "${CORE_PKGS[@]}"; do
  if pkg_present "${p}"; then
    result "package:${p}" PASS "$(pkg_version "${p}")"
  else
    result "package:${p}" FAIL "missing"
  fi
done

section "Niri configuration"
NIRI_REPO="${DOTFILES_DIR}/niri/config.kdl"
NIRI_DEPLOYED="${HOME}/.config/niri/config.kdl"

if [[ -f "${NIRI_REPO}" ]]; then
  if out="$(niri validate -c "${NIRI_REPO}" 2>&1)"; then
    result "niri:validate:repo" PASS "config.kdl is valid"
  else
    result "niri:validate:repo" FAIL "$(tail -n 3 <<< "${out}")"
  fi
else
  result "niri:validate:repo" FAIL "missing ${NIRI_REPO}"
fi

if [[ -f "${NIRI_DEPLOYED}" ]]; then
  if out="$(niri validate -c "${NIRI_DEPLOYED}" 2>&1)"; then
    result "niri:validate:deployed" PASS "~/.config/niri/config.kdl is valid"
  else
    result "niri:validate:deployed" FAIL "$(tail -n 3 <<< "${out}")"
  fi
  if grep -qF "${MARKER}" "${NIRI_DEPLOYED}"; then
    result "niri:marker" PASS "deployed config is managed by this project"
  else
    result "niri:marker" WARN "deployed config lacks the managed-by marker"
  fi
else
  result "niri:validate:deployed" FAIL "missing ${NIRI_DEPLOYED}"
fi

section "Waybar configuration"
WAYBAR_CONFIG="${HOME}/.config/waybar/config.jsonc"
WAYBAR_STYLE="${HOME}/.config/waybar/style.css"

if [[ -f "${WAYBAR_CONFIG}" ]]; then
  if out="$(parse_jsonc "${WAYBAR_CONFIG}" 2>&1)"; then
    result "waybar:config" PASS "valid JSON(C)"
  else
    result "waybar:config" FAIL "invalid JSON(C): $(tail -n 2 <<< "${out}")"
  fi
  if grep -q 'niri/workspaces' "${WAYBAR_CONFIG}"; then
    result "waybar:niri-module" PASS "niri/workspaces configured"
  else
    result "waybar:niri-module" WARN "niri/workspaces not configured"
  fi
else
  result "waybar:config" FAIL "missing ${WAYBAR_CONFIG}"
fi

if [[ -f "${WAYBAR_STYLE}" ]]; then
  result "waybar:style" PASS "${WAYBAR_STYLE}"
else
  result "waybar:style" FAIL "missing ${WAYBAR_STYLE}"
fi

for s in notifications.sh notifications-menu.sh wifi-menu.sh mic-status.sh ime-status.sh; do
  f="${HOME}/.config/waybar/scripts/${s}"
  if [[ -x "${f}" ]]; then
    result "waybar:script:${s}" PASS "executable"
  elif [[ -f "${f}" ]]; then
    result "waybar:script:${s}" WARN "present but not executable"
  else
    result "waybar:script:${s}" FAIL "missing"
  fi
done

section "Fuzzel / mako / Alacritty"
FUZZEL_CONF="${HOME}/.config/fuzzel/fuzzel.ini"
if [[ -f "${FUZZEL_CONF}" ]]; then
  FUZZEL_HELP="$(fuzzel --help 2>&1 || true)"
  if grep -q -- '--check-config' <<< "${FUZZEL_HELP}"; then
    # Fuzzel rejects non-ASCII prompt strings in the C locale. Desktop sessions
    # run under en_US.UTF-8; validate explicitly with a UTF-8 locale.
    if out="$(LC_ALL=C.UTF-8 fuzzel --check-config --config "${FUZZEL_CONF}" 2>&1)"; then
      result "fuzzel:config" PASS "valid"
    else
      result "fuzzel:config" FAIL "$(tail -n 2 <<< "${out}")"
    fi
  else
    result "fuzzel:config" WARN "fuzzel build has no --check-config; file present"
  fi
else
  result "fuzzel:config" FAIL "missing ${FUZZEL_CONF}"
fi

if [[ -f "${HOME}/.config/mako/config" ]]; then
  result "mako:config" PASS "present"
else
  result "mako:config" FAIL "missing"
fi

ALACRITTY_CONF="${HOME}/.config/alacritty/alacritty.toml"
if [[ -f "${ALACRITTY_CONF}" ]]; then
  if out="$(python3 - "${ALACRITTY_CONF}" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    tomllib.load(f)
print("valid")
PY
)"; then
    result "alacritty:config" PASS "valid TOML"
  else
    result "alacritty:config" FAIL "$(tail -n 2 <<< "${out}")"
  fi
fi

section "greetd / display manager"
GREETD_CONF="/etc/greetd/config.toml"
if [[ -r "${GREETD_CONF}" ]]; then
  if out="$(python3 - "${GREETD_CONF}" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
cmd = data.get("default_session", {}).get("command", "")
assert "niri-session" in cmd, "default_session.command does not start niri-session"
assert data.get("default_session", {}).get("user") == "greeter", "default_session.user is not greeter"
print("valid")
PY
)"; then
    result "greetd:config" PASS "valid TOML and starts niri-session"
  else
    result "greetd:config" FAIL "$(tail -n 2 <<< "${out}")"
  fi
else
  result "greetd:config" FAIL "cannot read ${GREETD_CONF}"
fi

if getent passwd greeter >/dev/null 2>&1; then
  result "greetd:greeter-user" PASS "greeter exists"
else
  result "greetd:greeter-user" FAIL "greeter user missing"
fi

if service_enabled greetd.service; then
  result "systemd:greetd-enabled" PASS "enabled"
else
  result "systemd:greetd-enabled" FAIL "not enabled"
fi

if systemctl is-active -q greetd.service 2>/dev/null; then
  result "systemd:greetd-active" PASS "running"
else
  result "systemd:greetd-active" WARN "not running (expected until graphical test)"
fi

section "Other services"
for svc in sshd.service NetworkManager.service; do
  if systemctl is-active -q "${svc}" 2>/dev/null; then
    result "systemd:${svc}" PASS "active"
  else
    result "systemd:${svc}" FAIL "not active"
  fi
done

if has_command bluetoothctl; then
  if service_enabled bluetooth.service; then
    result "systemd:bluetooth.service" PASS "enabled"
  else
    result "systemd:bluetooth.service" WARN "not enabled"
  fi
fi

FAILED_UNITS="$(systemctl --failed --no-legend --plain 2>/dev/null | wc -l)"
if [[ "${FAILED_UNITS}" -eq 0 ]]; then
  result "systemd:failed-units" PASS "0 failed units"
else
  result "systemd:failed-units" WARN "${FAILED_UNITS} failed unit(s): $(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
fi

section "SSH"
if ss -ltnH 2>/dev/null | grep -q ':22 '; then
  result "ssh:listen" PASS "port 22 is listening"
else
  result "ssh:listen" FAIL "nothing listening on port 22"
fi

section "Wallpaper / theme"
if [[ -x "${HOME}/.local/bin/wallpaper-rotate" && -x "${HOME}/.local/bin/theme-from-wallpaper" ]]; then
  result "theme:scripts" PASS "wallpaper-rotate and theme-from-wallpaper are executable"
else
  result "theme:scripts" FAIL "theme scripts missing under ~/.local/bin"
fi

if has_command awww && python3 -c 'import PIL' >/dev/null 2>&1; then
  result "theme:packages" PASS "awww and python-pillow available"
else
  result "theme:packages" FAIL "awww or python-pillow is missing"
fi

WALLPAPER_COUNT="$(find "${HOME}/Pictures/Wallpapers" -maxdepth 1 -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
  2>/dev/null | wc -l)"
if [[ "${WALLPAPER_COUNT}" -gt 0 ]]; then
  result "theme:wallpapers" PASS "${WALLPAPER_COUNT} image(s) in ~/Pictures/Wallpapers"
else
  result "theme:wallpapers" FAIL "no wallpapers in ~/Pictures/Wallpapers"
fi

if [[ -f "${HOME}/.config/arch-niri-setup/theme.env" ]]; then
  result "theme:state" PASS "theme.env exists"
else
  result "theme:state" WARN "theme.env missing; theme not generated yet"
fi

if [[ -f "${HOME}/.config/arch-niri-setup/current-wallpaper" ]]; then
  CURRENT_WALLPAPER="$(cat "${HOME}/.config/arch-niri-setup/current-wallpaper" 2>/dev/null || true)"
  if [[ -n "${CURRENT_WALLPAPER}" && -f "${CURRENT_WALLPAPER}" ]]; then
    result "theme:current-wallpaper" PASS "${CURRENT_WALLPAPER}"
  else
    result "theme:current-wallpaper" FAIL "current-wallpaper points to a missing file"
  fi
else
  result "theme:current-wallpaper" WARN "current-wallpaper is not set"
fi

if [[ -L "${HOME}/.config/systemd/user/timers.target.wants/wallpaper-rotate.timer" ]]; then
  result "theme:timer" PASS "wallpaper-rotate.timer is enabled"
else
  result "theme:timer" FAIL "wallpaper-rotate.timer is not enabled"
fi

if grep -q 'wallpaper-rotate.*--start' "${HOME}/.config/niri/config.kdl" 2>/dev/null; then
  result "theme:niri-hook" PASS "niri starts wallpaper-rotate at login"
else
  result "theme:niri-hook" FAIL "niri config has no wallpaper-rotate startup hook"
fi

if grep -qF 'generated by theme-from-wallpaper' "${HOME}/.config/waybar/style.css" 2>/dev/null; then
  result "theme:waybar-style" PASS "Waybar style was generated from a wallpaper"
else
  result "theme:waybar-style" WARN "Waybar style is still the base theme"
fi

section "Config drift"
check_drift() {
  local src="$1"
  local dest="$2"
  local label="$3"
  local rendered="${4:-}"
  local compare="${src}"
  local compare_label="repo"

  if [[ -n "${rendered}" && -f "${HOME}/.config/arch-niri-setup/rendered/${rendered}" ]]; then
    compare="${HOME}/.config/arch-niri-setup/rendered/${rendered}"
    compare_label="rendered theme"
  fi

  if [[ ! -f "${dest}" ]]; then
    result "drift:${label}" FAIL "missing ${dest}"
  elif cmp -s "${compare}" "${dest}"; then
    result "drift:${label}" PASS "matches ${compare_label}"
  else
    result "drift:${label}" WARN "differs from ${compare_label} (extras or manual edit)"
  fi
}

check_drift "${DOTFILES_DIR}/niri/config.kdl" "${HOME}/.config/niri/config.kdl" "niri-config" "niri-config.kdl"
check_drift "${DOTFILES_DIR}/waybar/config.jsonc" "${HOME}/.config/waybar/config.jsonc" "waybar-config"
check_drift "${DOTFILES_DIR}/waybar/style.css" "${HOME}/.config/waybar/style.css" "waybar-style" "waybar-style.css"
check_drift "${DOTFILES_DIR}/fuzzel/fuzzel.ini" "${HOME}/.config/fuzzel/fuzzel.ini" "fuzzel" "fuzzel.ini"
check_drift "${DOTFILES_DIR}/mako/config" "${HOME}/.config/mako/config" "mako" "mako-config"
check_drift "${DOTFILES_DIR}/alacritty/alacritty.toml" "${HOME}/.config/alacritty/alacritty.toml" "alacritty" "alacritty.toml"

section "GPU / EGL"
if has_command eglinfo; then
  EGL_OUT="$(sudo -n eglinfo -B 2>/dev/null || true)"
  if [[ -z "${EGL_OUT}" ]]; then
    EGL_OUT="$(eglinfo -B 2>/dev/null || true)"
  fi
  if grep -qi 'No 3D enabled' <<< "${EGL_OUT}"; then
    result "gpu:egl" FAIL "VMware reports 'No 3D enabled'; niri will not render"
  elif grep -qi 'SVGA3D' <<< "${EGL_OUT}"; then
    result "gpu:egl" PASS "hardware EGL renderer available (SVGA3D)"
  elif grep -qiE 'llvmpipe|softpipe|swrast' <<< "${EGL_OUT}"; then
    result "gpu:egl" WARN "software EGL renderer only; niri skips software renderers"
  elif grep -qi 'renderer' <<< "${EGL_OUT}"; then
    result "gpu:egl" PASS "EGL renderer reported"
  else
    result "gpu:egl" WARN "could not determine EGL renderer"
  fi
else
  result "gpu:egl" WARN "eglinfo is missing; cannot inspect the renderer"
fi

section "Wayland session state"
if pgrep -x niri >/dev/null 2>&1; then
  result "session:niri-process" PASS "niri is running"
else
  result "session:niri-process" WARN "no niri process; SSH cannot verify the Wayland session"
fi
result "session:session-type" WARN "SSH session type is '${XDG_SESSION_TYPE:-unset}'; graphical console test required"

section "Log scan"
# Scan only the newest log per step, so an old fixed failure is not reported
# forever.
LOGFILES=()
for step in preflight 10-packages 20-paru 30-niri 40-desktop 50-extras 60-gpu smoke-test; do
  latest="$(find "${LOG_DIR}" -maxdepth 1 -name "${step}-*.log" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)"
  [[ -n "${latest}" ]] && LOGFILES+=("${latest}")
done

if [[ "${#LOGFILES[@]}" -eq 0 ]]; then
  result "logs:scan" WARN "no prior step logs found"
else
  ERRORS="$(grep -hiE '\b(error|failed|fatal)\b' "${LOGFILES[@]}" 2>/dev/null \
    | grep -viE '0 failed|errors=0|error: 0|no error|error_|--error|error-|failed=0|perl-error|Error while writing index|No debugging symbols|error while loading shared libraries: lib.*not found \(ignored\)' \
    | head -n 5 || true)"
  if [[ -z "${ERRORS}" ]]; then
    result "logs:scan" PASS "no error patterns in ${#LOGFILES[@]} recent log(s)"
  else
    result "logs:scan" WARN "error patterns found (review): $(head -n 1 <<< "${ERRORS}")"
  fi
fi

{
  echo
  echo "## Verdict"
  echo
  echo "- PASS: **${PASS}**"
  echo "- WARN: **${WARN}**"
  echo "- FAIL: **${FAIL}**"
  echo
  echo "### Limitation"
  echo
  echo "SSH validation can confirm packages, config syntax and services. It cannot"
  echo "prove that niri, Waybar, Fuzzel or Alacritty render correctly on Wayland."
  echo "Start greetd and test on the VirtualBox graphical console before calling"
  echo "the desktop usable."
  echo
  if [[ "${FAIL}" -eq 0 ]]; then
    echo "Result: **PASS (with ${WARN} warning(s))**"
  else
    echo "Result: **FAIL (${FAIL} failing check(s))**"
  fi
} >> "${REPORT}"

section "Validation summary"
info "Report: ${REPORT}"
info "PASS=${PASS} WARN=${WARN} FAIL=${FAIL}"

if [[ "${FAIL}" -gt 0 ]]; then
  err "Validation failed with ${FAIL} failing check(s)."
  exit 1
fi

info "Validation passed with ${WARN} warning(s)."
info "Graphical console test is still required (SSH cannot prove Wayland rendering)."
