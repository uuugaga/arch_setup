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
- `install/45-theme.sh` - wallpaper rotation + dynamic theme; deploys scripts,
  templates and the user timer.
- `install/50-extras.sh` - optional modules; flags, never implicit.
- `install/60-gpu.sh` - VM/bare-metal GPU drivers; `WANT_32BIT=1` for Steam.
- `install/90-validate.sh` - read-only; writes `logs/validate.md`.
- `tests/smoke-test.sh` - fast read-only checks.
- `logs/` - generated. Do not commit logs.

Theme source files:

- `dotfiles/theme/theme-from-wallpaper` - palette extraction and deployment.
- `dotfiles/theme/templates/` - Waybar, mako, Fuzzel, Alacritty templates.
- `dotfiles/awww/wallpaper-rotate` - stateful image selection + theme call.
- `dotfiles/systemd/user/wallpaper-rotate.{service,timer}` - hourly rotation.

## Ordering

Core order: `00 -> 10 -> 20 -> 30 -> 40 -> 45 -> 60 -> 90 -> smoke-test`.

Extras order: core first, then `50-extras.sh --fcitx` **after** `30-niri.sh`
because `--fcitx` deploys `dotfiles/niri/config.full.kdl` over the core config.
Re-running `30-niri.sh` afterwards would revert extras config; either avoid that
or re-run `--fcitx`.

## Theme / wallpaper

- Wallpaper images are user data in `~/Pictures/Wallpapers`. Do not delete or
  overwrite them. The host source used for this run is
  `../wallpaper` in the workspace root.
- `theme-from-wallpaper` is the only writer of generated configs:
  `~/.config/waybar/style.css`, `~/.config/mako/config`,
  `~/.config/fuzzel/fuzzel.ini`, `~/.config/alacritty/alacritty.toml`, and the
  color lines in `~/.config/niri/config.kdl`.
- Never hand-edit those generated files. Edit
  `dotfiles/theme/templates/` (and keep `dotfiles/waybar/style.css` in sync
  for the non-themed base style), then rerun `theme-from-wallpaper`.
- `wallpaper-rotate` uses a state file and `LC_ALL=C sort` so the systemd
  service and an SSH shell select the same image. Do not change the sort
  locale without updating the state semantics.
- `wallpaper-rotate` discovers `WAYLAND_DISPLAY` from
  `$XDG_RUNTIME_DIR/wayland-*`; systemd user timers may have a stale value.
- Over SSH, use `wallpaper-rotate --theme-only` to regenerate colors without
  touching awww. Use `--next` only inside a live niri session.
- The hourly timer is enabled by a `timers.target.wants` symlink. Test the real
  path with `systemctl --user start wallpaper-rotate.service`.
- GTK apps only get `prefer-dark` + the nearest `accent-color`; they are not
  fully recolored. State this limitation in reports.
- Glass settings live in the templates/config:
  - Waybar pills: `rgba(bg, 0.62)` + accent border + shadow. Do **not** add a
    `^waybar$` layer-rule blur: Waybar's layer surface spans the full screen
    width, so niri would blur the transparent gaps between the pills too.
    Stock Waybar has no shaped blur region.
  - Alacritty: `opacity = 0.62`; niri window-rule
    `draw-border-with-background false` plus
    `background-effect { blur true; xray false; }`.
    `draw-border-with-background false` is required: otherwise niri paints the
    focus ring/border as a solid accent rectangle behind the window, which
    shows through a transparent terminal and looks like an opaque tint.
  - Fuzzel: 0.80 background alpha + `layer-rule` namespace `^launcher$` blur.
  - mako: 0.87 background alpha + `layer-rule` namespace `^mako$` blur.
  - niri `hotkey-overlay { skip-at-startup }` avoids the help overlay on every
    login.
- Keep the palette soft: background value around 0.13, saturation capped near
  0.22, accent value 0.74-0.84. Avoid returning to near-black backgrounds or
  fully saturated accents; check text contrast against bright wallpaper areas.
- After changing transparency, take a console screenshot over both a dark and a
  bright part of the wallpaper and verify text contrast.
- If the user reports all text is blurry, compare a native 1280x800 screenshot
  first. Blur only affects the surface backdrop, not glyphs. VirtualBox scaled
  mode / HiDPI scaling blurs the entire framebuffer; semi-transparent surfaces
  also use grayscale antialiasing instead of subpixel AA.

## Validation protocol

1. `bash -n` every shell script and `python3 -m py_compile` the theme script.
2. `./install/00-preflight.sh` must exit 0 before installing.
3. Run the core steps (including `45-theme.sh`).
4. `./install/90-validate.sh` must have zero FAIL. WARN is acceptable only for
   documented reasons (no niri process over SSH, greetd not started yet).
5. `./tests/smoke-test.sh` must exit 0.
6. Graphical console test is separate and mandatory. SSH cannot prove Wayland.
   Follow `tests/graphical-test.md`. Never claim the desktop works from SSH
   output alone.
7. Theme-specific checks:
   - `wallpaper-rotate --status` must name the same image as `awww query` and
     `~/.config/arch-niri-setup/current-wallpaper`.
   - Rotate through every wallpaper (`--next`) and screenshot the bar, a
     terminal window, Fuzzel and a mako notification.
   - `systemctl --user start wallpaper-rotate.service` must advance exactly one
     image and leave the theme matching it.
   - `niri` must auto-start awww at login; test with a clean session restart.

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
