#!/usr/bin/env bash
# managed-by: arch-niri-setup
# Emits a Waybar JSON line for fcitx5.
#
# Both labels are single CJK characters ("英" and "中") rendered with the same
# font family and font size. That guarantees the indicator has identical
# metrics in both states; "EN"/"ZH" or "EN"/"中" would use different glyph
# widths. Classes let style.css color the active state.
#
# fcitx5 reports an empty input method when no text field is focused (state 0).
# Cache the last non-empty value; a fresh session has no cache and starts in
# the inactive English layout, so fall back to keyboard-us rather than the
# profile's DefaultIM (which fcitx5 normalizes to the active Chewing method).
set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/arch-niri-setup"
CACHE_FILE="${CACHE_DIR}/ime-last"
PENDING_FILE="${CACHE_DIR}/ime-pending"

missing() {
  printf '{"text":"","tooltip":"%s","class":"missing"}\n' "$1"
  exit 0
}

command -v fcitx5-remote >/dev/null 2>&1 \
  || missing "fcitx5 is not installed (install/50-extras.sh --fcitx)"
fcitx5-remote --check >/dev/null 2>&1 \
  || missing "fcitx5 is not running"

name="$(fcitx5-remote -n 2>/dev/null || true)"

# A click on the badge while no text field was focused queued the target. Apply
# it now that fcitx5 has an input context; `-s` is a no-op at state 0.
if [[ -n "${name}" && -s "${PENDING_FILE}" ]]; then
  target="$(head -n1 "${PENDING_FILE}" 2>/dev/null || true)"
  if [[ -n "${target}" && "${target}" != "${name}" ]]; then
    fcitx5-remote -s "${target}" >/dev/null 2>&1 || true
    updated="$(fcitx5-remote -n 2>/dev/null || true)"
    if [[ -n "${updated}" ]]; then
      name="${updated}"
    fi
  fi
  rm -f "${PENDING_FILE}"
fi

if [[ -n "${name}" ]]; then
  if [[ ! -f "${CACHE_FILE}" || "$(head -n1 "${CACHE_FILE}" 2>/dev/null || true)" != "${name}" ]]; then
    mkdir -p "${CACHE_DIR}" 2>/dev/null || true
    tmp="${CACHE_FILE}.$$"
    if printf '%s\n' "${name}" > "${tmp}" 2>/dev/null; then
      mv -f "${tmp}" "${CACHE_FILE}" 2>/dev/null || rm -f "${tmp}"
    else
      rm -f "${tmp}"
    fi
  fi
elif [[ -s "${CACHE_FILE}" ]]; then
  name="$(head -n1 "${CACHE_FILE}" 2>/dev/null || true)"
else
  # Fresh session: fcitx5 starts in the inactive English keyboard layout.
  name="keyboard-us"
fi

case "${name}" in
  keyboard-*)
    printf '{"text":"英","tooltip":"English keyboard (%s)","class":"en"}\n' "${name}"
    ;;
  chewing*)
    printf '{"text":"中","tooltip":"Chinese - Chewing 注音 (%s)","class":"zh"}\n' "${name}"
    ;;
  pinyin*)
    printf '{"text":"中","tooltip":"Chinese - Pinyin (%s)","class":"zh"}\n' "${name}"
    ;;
  "")
    missing "fcitx5 is running but has no input method"
    ;;
  *)
    printf '{"text":"中","tooltip":"Chinese input (%s)","class":"zh"}\n' "${name}"
    ;;
esac
