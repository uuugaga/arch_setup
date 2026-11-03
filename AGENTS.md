# Agent Notes

## Purpose

Maintain `arch-niri-setup`, a reproducible Arch Linux installer for
niri + Waybar + Fuzzel + Alacritty. The older `../arch-niri-setup-master`
folder is user history: **do not modify or delete it** unless explicitly asked.

## Non-negotiable constraints

- Target: Arch Linux VM (`ArchLinux x86_64`, VMSVGA) and bare metal.
- Terminal: **Alacritty**. Do not add kitty.
- AUR: build paru as the normal user. Never run `sudo paru` or makepkg as root.
- Do not delete/recreate the VM, reset disks, or restore snapshots without
  explicit approval. Shutting down/rebooting the VM also needs approval.
- Do not read or transmit Windows SSH private keys.
- Do not touch VirtualBox shared folders or unrelated Windows projects.
- All durable changes must land in versioned scripts/dotfiles, not one-off
  shell commands.
- Every entry script: `set -Eeuo pipefail`, source `install/lib/common.sh`,
  call `init_logging`, and use the shared helpers.
- Deployed files must keep the `managed-by: arch-niri-setup` marker.
- Back up before replacing. `deploy_file` refuses unmanaged files unless
  `FORCE=1`.

## Layout

- `install/00-preflight.sh` - read-only; writes `logs/preflight.md` and
  `logs/preflight.env`.
- `install/10-packages.sh` - core repo packages from `config/packages.conf`.
- `install/20-paru.sh` - user-owned paru build in `~/build/paru`.
- `install/30-niri.sh` - niri config, greetd/tuigreet config, enable greetd.
- `install/40-desktop.sh` - Waybar/Fuzzel/mako/Alacritty, services.
- `install/50-extras.sh` - optional modules; flags, never implicit.
- `install/60-gpu.sh` - VM/bare-metal GPU drivers; `WANT_32BIT=1` for Steam.
- `install/90-validate.sh` - read-only; writes `logs/validate.md`.
- `tests/smoke-test.sh` - fast read-only checks.
- `logs/` - generated. Do not commit logs.

## Ordering

Core order: `00 -> 10 -> 20 -> 30 -> 40 -> 60 -> 90 -> smoke-test`.

Extras order: core first, then `50-extras.sh --fcitx` **after** `30-niri.sh`
because `--fcitx` deploys `dotfiles/niri/config.full.kdl` over the core config.
Re-running `30-niri.sh` afterwards would revert extras config; either avoid that
or re-run `--fcitx`.

## Validation protocol

1. `bash -n` every shell script.
2. `./install/00-preflight.sh` must exit 0 before installing.
3. Run the core steps.
4. `./install/90-validate.sh` must have zero FAIL. WARN is acceptable only for
   documented reasons (no niri process over SSH, greetd not started yet).
5. `./tests/smoke-test.sh` must exit 0.
6. Graphical console test is separate and mandatory. SSH cannot prove Wayland.
   Follow `tests/graphical-test.md`. Never claim the desktop works from SSH
   output alone.

## VirtualBox guests

- niri 26.04 skips software EGL renderers. A VMSVGA guest with 3D acceleration
  off will start niri but render a black screen.
- Required VM setting: `--accelerate3d on --vram 128` (or more VRAM).
  Changing it requires a VM power-off, which needs explicit approval.
- Verify with `sudo eglinfo -B | grep -E 'SVGA3D|No 3D enabled'`.
- Take a snapshot before changing VM settings. `90-validate.sh` checks
  `gpu:egl` and fails on `No 3D enabled`.
- Graphical test flow: start greetd, screenshot tuigreet, then temporarily
  deploy `tests/greetd-autologin.toml`, verify niri + Waybar + Alacritty +
  Fuzzel + mako + XWayland, then restore `dotfiles/greetd/config.toml` and stop
  the test niri user service.

## Reporting

- Keep `logs/preflight.md` and `logs/validate.md` in sync with the last run.
- Summarize PASS/WARN/FAIL counts and any root cause.
- If a step fails, fix the script, not only the machine, then rerun from the
  failed stage. Maximum three automated retries per failure.

## Style

- Match the existing helper names: `deploy_file`, `pacman_install`,
  `aur_install`, `ensure_service_enabled`, `pkg_present`.
- Prefer small functions and explicit arrays.
- Avoid `eval`, unquoted globs, and `rm -rf` on user paths.
- Use `sudo -n` (passwordless) and fail clearly if it is unavailable.
