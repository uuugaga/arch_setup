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
- `install/10-packages.sh` - core + everyday CLI repo packages from
  `config/packages.conf`.
- `install/20-paru.sh` - user-owned paru build in `~/build/paru`.
- `install/30-niri.sh` - niri config, greetd/tuigreet config, enable greetd.
- `install/40-desktop.sh` - Waybar/Fuzzel/mako/Alacritty, services.
- `install/45-theme.sh` - wallpaper rotation + dynamic theme; deploys scripts,
  templates and the user timer.
- `install/50-extras.sh` - optional modules; flags, never implicit.
- `install/55-snapshots.sh` - manual-only Snapper + Btrfs Assistant; disables
  automatic timers and creates one baseline snapshot.
- `install/60-gpu.sh` - VM/bare-metal GPU drivers; `WANT_32BIT=1` for Steam.
- `install/90-validate.sh` - read-only; writes `logs/validate.md`.
- `tests/smoke-test.sh` - fast read-only checks.
- `logs/` - generated. Do not commit logs.

Theme source files:

- `dotfiles/theme/theme-from-wallpaper` - palette extraction and deployment.
- `dotfiles/theme/templates/` - Waybar, mako, Fuzzel, Alacritty templates.
- `dotfiles/awww/wallpaper-rotate` - stateful image selection + theme call.
- `dotfiles/systemd/user/wallpaper-rotate.{service,timer}` - hourly rotation.
- `dotfiles/fcitx5/` - English/Chewing profile, `ime-toggle`, notification
  config.

## CLI tools

- `config/packages.conf` keeps `CLI_PKGS` separate from `CORE_PKGS`; both are
  installed by `10-packages.sh` in one pacman transaction. The current set is
  `less`, `vim`, `nano`, `htop`, `btop`, `fastfetch`, `tree`, `wget`, `unzip`,
  `zip`, `tmux`, `zsh`, `cmake`.
- Keep `CLI_COMMANDS` in sync with `CLI_PKGS`. `90-validate.sh` and
  `tests/smoke-test.sh` use them to check both packages and PATH commands.
- `zsh` is installed as an alternative shell but **not** made the default and
  no zshrc is deployed by `10-packages.sh`. `50-extras.sh --zsh` is the
  optional module for Starship, zsh plugins and the sample `~/.zshrc`. Do not
  run `chsh` without asking the user.
- These are official-repository packages; do not add AUR CLI tools to
  `CLI_PKGS`. Use the extras/AUR path if a tool is AUR-only.
- `man-db` is not part of the set; `less` alone does not provide `man`. Add it
  only if the user asks.

## Ordering

Core order: `00 -> 10 -> 20 -> 30 -> 40 -> 45 -> 50 -> 55 -> 60 -> 90 -> smoke-test`.

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
  glass-gradient accent endpoint plus urgent color in
  `~/.config/niri/config.kdl`.
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
- Window borders are a deliberate **1px glass rim**, not a focus ring:
  `focus-ring { off }`, `border { width 1 }`, and a top-to-bottom gradient
  (`#ffffff5c` -> accent at `40` alpha active, `#ffffff24` -> accent at `1f`
  inactive) plus a soft shadow. The white rim and alpha levels are constants;
  `theme-from-wallpaper` rewrites only the gradient's `to` endpoint and
  `urgent-color` (8-digit hex). Do not reintroduce a 2px+ border, a 4px focus
  ring, or solid `active-color`/`inactive-color` lines. niri renders the
  gradient per-window, so each window is lit from its own top edge.
- Keep the palette soft: background value around 0.13, saturation capped near
  0.22, accent value 0.74-0.84. Avoid returning to near-black backgrounds or
  fully saturated accents; check text contrast against bright wallpaper areas.
- After changing transparency, take a console screenshot over both a dark and a
  bright part of the wallpaper and verify text contrast.
- If the user reports all text is blurry, compare a native 1280x800 screenshot
  first. Blur only affects the surface backdrop, not glyphs. VirtualBox scaled
  mode / HiDPI scaling blurs the entire framebuffer; semi-transparent surfaces
  also use grayscale antialiasing instead of subpixel AA.

## Snapshots (manual-only)

- `55-snapshots.sh` installs `snapper` and `btrfs-assistant`, creates the root
  snapper config, disables all automatic timers, sets `TIMELINE_CREATE=no`, and
  creates one `baseline-manual` snapshot.
- Do **not** install `snap-pac` or `grub-btrfs` in this project. The user
  explicitly wants manual snapshots and no GRUB snapshot menu / `grub-btrfsd`
  overhead.
- Keep the baseline snapshot idempotent: rerunning the script must not create
  duplicate `baseline-manual` entries.
- Snapshots are for `@` only. `@home`, `@log` and `@pkg` are separate; do not
  include them in the root snapshot.
- The automatic cleanup timer is disabled; old snapshots are deleted manually
  or through Btrfs Assistant. `NUMBER_LIMIT=5` and
  `NUMBER_LIMIT_IMPORTANT=3` are retention hints only.
- No snapshot boot entries: restore with Btrfs Assistant or from a live
  environment (`snapper rollback`). Snapshots are not a backup; use btrbk for
  external copies.
- `90-validate.sh` checks snapper config, `TIMELINE_CREATE=no`, disabled timers,
  the baseline snapshot and the Btrfs Assistant binary.

## Display / multi-monitor

- `nwg-displays` is in `CORE_PKGS`; it supports niri, writes
  `~/.config/niri/monitor.kdl`, and niri includes it via
  `include "monitor.kdl"`.
- `ensure_monitor_file` creates an empty monitor layout only when missing.
  Never overwrite an existing `monitor.kdl`: nwg-displays owns it after first
  use. Both `config.kdl` templates contain the include.
- The GUI supports position, scale, resolution, refresh, DPMS and multiple
  output blocks. Niri uses dynamic workspaces, so nwg-displays cannot assign
  workspaces to outputs.
- `niri msg output <name> scale|mode|position` is runtime-only; persist via
  nwg-displays / monitor.kdl.
- Fractional scaling can blur XWayland apps; prefer Wayland-native apps.
- The VM has a single `Virtual-1`; multi-monitor GUI behavior is documented from
  upstream but cannot be physically tested without a second output.
- `theme-from-wallpaper` validates niri configs in a temp dir and copies sibling
  `*.kdl` includes, so theme regeneration must keep `monitor.kdl` available.

## Input method (fcitx5 + Chewing)

- `50-extras.sh --fcitx` installs `fcitx5`, `fcitx5-chewing`,
  `fcitx5-configtool`, `fcitx5-gtk` and `fcitx5-qt`. It deploys
  `config.full.kdl`, which is the only config with the IME environment,
  `fcitx5` autostart and `Mod+Space` bind.
- Profile: `keyboard-us` first (inactive English layout), `chewing` second.
  fcitx5 normalizes `DefaultIM` to the second item, so `DefaultIM=chewing` is
  expected; the session starts English and the first toggle activates Chewing.
  niri owns fcitx5 startup; do not add a systemd user service.
- `fcitx5-remote -t` toggles active/inactive, **not** English/Chinese. Use
  `~/.local/bin/ime-toggle`, which calls `fcitx5-remote -s keyboard-us` or
  `-s chewing`. Waybar's left click and `Mod+Space` both use it; middle click
  goes directly to English.
- fcitx5 only changes IM while a text field is focused (state != 0). With no
  input context, `ime-toggle` writes the target to
  `~/.cache/arch-niri-setup/ime-pending`; `ime-status.sh` applies it with
  `fcitx5-remote -s` when a context appears, then removes the pending file.
  The badge reads the cache, so it switches immediately even while queued.
  Do not add `-o`/`-t` loops; they do nothing at state 0. The actual IM can lag
  the badge by up to the Waybar poll interval (~1s).
- The Waybar badge must stay visually identical in both states: one CJK glyph
  (`英` / `中`), same `Noto Sans CJK TC` font, same 16px bold size, same pure
  white (`#ffffff`; **not** the accent for `中`), fixed 22px
  min-width/min-height and the same rounded background. Do not change it to
  `EN`/`ZH`, `EN`/`中`, or use different font sizes/colors.
- `ime-status.sh` polls every second. fcitx5 reports an empty name when no text
  field is focused, so the script caches the last non-empty IM in
  `~/.cache/arch-niri-setup/ime-last`. A fresh session has no cache and falls
  back to `keyboard-us` (the inactive English layout). Do not remove the cache
  fallback; otherwise the badge disappears whenever focus leaves a text field.
  Do not use the profile's `DefaultIM` as the fallback: fcitx5 normalizes it to
  the active Chewing method, not the startup state.
- When the badge is clicked with no input context, `ime-toggle` writes the
  target to `~/.cache/arch-niri-setup/ime-pending` and `ime-status.sh` applies
  it when a text field gains focus. Keep the queue and the cache fallback in
  sync; the badge must show the queued target immediately.
- fcitx5 saves its profile on exit and rewrites it without the managed-by
  marker. `50-extras.sh` stops fcitx5 before deploying the profile and keeps an
  existing profile that already contains both IMs.
- Keep `GTK_IM_MODULE=fcitx` for XWayland/Electron. That triggers fcitx5's
  `wayland-diagnose-other` tip on niri; it is hidden via
  `dotfiles/fcitx5/conf/notifications.conf` and `ensure_fcitx_notifications`.
  Do not blindly replace that file: fcitx5 stores the list as an indexed
  `[HiddenNotifications]` section.
- `50-extras.sh` reloads niri after deploying the full config so `Mod+Space`
  works in the current session. A fresh login also works.
- `90-validate.sh` checks the binaries, packages, profile, niri environment,
  `ime-toggle` wiring, Waybar module, JSON output and the `英`/`中` labels.
- End-to-end verification used GTK4 `zenity --entry`: type `su3`, space, `1`
  to get `你`. Electron/Chromium may need native Wayland IME flags; do not
  claim they work solely from the GTK test.

## Optional apps

- `50-extras.sh --apps` installs the repo list first, then AUR packages one at a
  time. A failed AUR build is recorded and the remaining apps continue.
- Mail is **Thunderbird**; Mailspring was removed because its AUR build failed
  against the current Node/V8.
- Docker and Tailscale services are enabled/started. The user is added to the
  `docker` group (re-login required for the graphical session).
- Flatpak is not installed; the project uses official repos + paru/AUR. If a
  Flathub-only app is needed, install Flatpak manually.
- `dotfiles/apps/app-check` is deployed to `~/.local/bin/app-check`; use
  `docker buildx version` for Buildx because it is a CLI plugin, not a PATH
  binary.
- Steam belongs to `--gaming`, not `--apps`.

## Steam / gaming

- `50-extras.sh --gaming` is official-repository only. It enables `[multilib]`
  with a backup of `/etc/pacman.conf`, runs `pacman -Syu`, then installs
  `EXTRAS_GAMING`.
- Enabling multilib requires a full `-Syu`; do not replace it with a partial
  `-Sy`. Do not reboot after install. Kernel/package updates take effect on the
  next user-approved boot.
- `GAMING_COMMANDS` must stay in sync with `EXTRAS_GAMING`; `steam-devices` is a
  udev-rules package with no command, so it is package-only.
- The module writes `~/.config/arch-niri-setup/gaming`, deploys
  `dotfiles/gaming/MangoHud.conf`, and creates `~/Games/SteamLibrary`.
  `90-validate.sh` checks gaming only when that marker exists, so a machine
  without Steam still passes.
- `tests/gaming-test.sh` is the optional read-only test. Keep it separate from
  `tests/smoke-test.sh`; core smoke must not fail when gaming is not installed.
- This VM has **no hardware Vulkan** (`VMSVGA`/`vmwgfx`). `vulkan-swrast` and
  `lib32-vulkan-swrast` provide Mesa lavapipe only. Never claim Proton/3A games
  are playable from `vulkaninfo` output alone.
- MangoHud draws on `vmwgfx`, but GPU stats and CPU temperature are unavailable
  in this VM. Treat blank/zero fields as expected, not a failure.
- `gamescope --help` works, but the real backend fails on lavapipe with
  "not a valid physical device". Do not suggest gamescope as a working wrapper
  in this VM; it is for hardware Vulkan only.
- Leave `gamemoded.service` disabled at boot. `gamemoderun` D-Bus-activates it
  on demand; in this VM it logs expected cpufreq/polkit errors but still runs.
- `steam` is XWayland; `xwayland-satellite` must be running. The login window
  reports app ID `steam` and niri floats it automatically, so no window rule is
  needed. Re-check with `niri msg windows` if a future Steam version changes
  this.
- First launch needs the user's Steam login and Steam Guard. Do not automate or
  store credentials. A GUI test may open the login window and screenshot it,
  then close Steam.
- Do not add AUR gaming packages (`lutris` is official, but Heroic, ProtonUp-Qt,
  vkBasalt, Bottles and Faugus are AUR) to `EXTRAS_GAMING`. If a later scope
  adds them, use the `--apps`-style AUR path and keep repo packages first.

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
- Greeter warning: `niri-session` calls `systemctl --user import-environment`
  without a variable list, and systemd prints a deprecation warning on the
  greeter VT. `30-niri.sh` deploys
  `dotfiles/systemd/system/greetd.service.d/90-quiet-import.conf`
  (`SYSTEMD_LOG_LEVEL=err`). Do not patch `/usr/bin/niri-session`; the drop-in
  is package-upgrade safe. `90-validate.sh` checks `greetd:quiet-import`.

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
