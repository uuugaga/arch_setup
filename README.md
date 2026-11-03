# arch-niri-setup

Reproducible Arch Linux desktop installer for **niri + Waybar + Fuzzel + Alacritty**.

This is a clean rewrite of the older `arch-niri-setup-master` scripts. The old
folder is intentionally left untouched. This project targets both VirtualBox
guests (VMSVGA/vmwgfx) and bare-metal NVIDIA/AMD/Intel machines.

- No kitty. The terminal is Alacritty.
- Official repositories first; AUR only through paru, built as the normal user.
- Idempotent steps, explicit backups, managed-config markers, Markdown reports.
- Never runs `sudo paru`.
- Never reboots, restarts the VM, or restores snapshots on its own.

## Status

Verified on 2026-11-03 in the VirtualBox guest `ArchLinux x86_64`:

- `logs/validate.md`: **100 PASS / 2 WARN / 0 FAIL**
- `logs/graphical-test.md`: niri, Waybar, Alacritty, Fuzzel, mako, XWayland
  and portals confirmed on the graphical console (3D acceleration required)
- `logs/theme-test.md`: hourly wallpaper rotation, soft palette and glass
  transparency verified with both supplied wallpapers
- `tests/smoke-test.sh`: 26 PASS / 0 FAIL

The optional `install/50-extras.sh` modules (fcitx5, apps, gaming, zsh) are
implemented and syntax-checked, but were **not** exercised in this VM run.
Wallpaper rotation and theming are part of the core install via `45-theme.sh`.

## Structure

```text
install/
  00-preflight.sh     read-only environment report -> logs/preflight.md
  10-packages.sh      official repo core packages
  20-paru.sh          build paru as user (makepkg, never root)
  30-niri.sh          niri config + greetd/tuigreet (enable only)
  40-desktop.sh       Waybar/Fuzzel/mako/Alacritty configs + services
  45-theme.sh         wallpaper rotation + dynamic theme (awww + Pillow)
  50-extras.sh        optional: fcitx5, apps, gaming, zsh
  60-gpu.sh           Mesa/Vulkan/VA-API per GPU (VM aware)
  90-validate.sh      read-only validation -> logs/validate.md
  lib/common.sh       logging, backups, deploy, package helpers
config/
  packages.conf       package manifest (core + extras)
dotfiles/
  niri/               config.kdl (core) and config.full.kdl (extras)
  waybar/             config, style, helper scripts
  theme/              theme-from-wallpaper + generated-config templates
  awww/               wallpaper-rotate
  fuzzel/ mako/ alacritty/ greetd/ fcitx5/ systemd/ zsh/
tests/
  smoke-test.sh       fast read-only checks
  greetd-autologin.toml  TEST FIXTURE ONLY (autologin for console tests)
  graphical-test.md   graphical console test procedure
logs/                 generated reports and transcripts
```

## Requirements

- Arch Linux (VM or bare metal), a normal user in `wheel` with passwordless sudo.
- Network access to `archlinux.org` and `aur.archlinux.org`.
- At least 3 GiB free on `/` (paru + desktop packages).
- A VirtualBox snapshot before the first install. Creating/restoring snapshots is
  an approval-gated action in this project.

## Quick start

Copy the folder to the target machine, then run as the desktop user:

```bash
cd arch-niri-setup

./install/00-preflight.sh
./install/10-packages.sh
./install/20-paru.sh
./install/30-niri.sh
./install/40-desktop.sh
./install/45-theme.sh
./install/60-gpu.sh
./install/90-validate.sh
./tests/smoke-test.sh
```

`30-niri.sh` enables greetd but does not start it. Start it only when you are
ready to use the graphical console:

```bash
sudo systemctl start greetd
```

Optional modules (run after the core steps; `--fcitx` must be last because it
replaces the niri config with `config.full.kdl`):

```bash
./install/50-extras.sh --fcitx
./install/50-extras.sh --apps
./install/50-extras.sh --gaming
./install/50-extras.sh --zsh
```

`45-theme.sh` already installs the wallpaper engine, so `50-extras.sh --wallpaper`
is only needed if you want to redeploy its units/scripts manually.

## Safety model

Every deployed file contains:

```text
managed-by: arch-niri-setup
```

`deploy_file` refuses to overwrite a file without that marker unless `FORCE=1`
is set. When it does replace a managed file, it backs it up first:

- user files: `~/.local/share/arch-niri-setup/backups/<timestamp>/...`
- system files: `/var/backups/arch-niri-setup/<timestamp>/...`

This prevents an unknown existing desktop config from being silently clobbered.

`FORCE=1` is intentionally opt-in:

```bash
FORCE=1 ./install/40-desktop.sh
```

## Package policy

- Core: niri, Waybar, Fuzzel, mako, Alacritty, portals, XWayland satellite,
  PipeWire, NetworkManager, BlueZ, greetd + tuigreet, fonts, screenshot tools.
- Wallpaper rotation: `awww`; palette extraction: `python-pillow`; desktop
  notifications: `libnotify`.
- The desktop uses Alacritty. kitty is not installed.
- `paru` is built from the AUR with `makepkg -si` as the normal user.
- `xdg-desktop-portal-gnome` and `-gtk` are both installed because niri's
  screencast/file-picker support depends on the portal backend available.
- GPU drivers are delegated to `60-gpu.sh`; the VM uses Mesa + vmwgfx.

## Waybar UI

- Right-side icons are 18px (the rest of the bar stays at 14px).
- `spacing` is `0`; every module gets the same `padding: 0 7px` and
  `margin: 4px 4px`. This keeps the gaps equal and lets the hidden IME module
  collapse to zero width instead of reserving a gap.
- Volume is a `group/volume` drawer: normally only the speaker icon is shown.
  Hovering it reveals the slider. `transition-left-to-right` is `true` so the
  drawer expands leftwards from the right edge instead of off-screen.
- CPU/RAM remain text modules with the same outer spacing; their content width
  naturally differs from icon-only modules.
- The three bar pills use `rgba(bg, 0.62)`, a 1px accent border, a 14px radius
  and a soft shadow. They are semi-transparent but **not blurred**: Waybar's
  layer surface spans the full screen width, so a niri layer-rule would blur
  the transparent gaps between the pills as well. Blur is applied to Fuzzel
  and mako, whose layer surfaces are the visible blocks.

## Wallpaper and dynamic theme

Put wallpapers in `~/Pictures/Wallpapers` on the target machine. The two images
used for this run live in the host folder `C:\Users\uuugaga\ArchLinux\wallpaper`
and were copied into the guest. Supported formats: jpg, jpeg, png, webp.

`install/45-theme.sh` installs:

- `awww` (wallpaper daemon and transitions)
- `python-pillow` (palette extraction)
- `libnotify` (`notify-send` feedback)
- `~/.local/bin/wallpaper-rotate`
- `~/.local/bin/theme-from-wallpaper`
- templates under `~/.config/arch-niri-setup/templates/`
- `wallpaper-rotate.timer` (hourly) and `.service`

Behaviour:

- niri starts `wallpaper-rotate --start` at login, which applies the current
  image and regenerates the theme.
- `wallpaper-rotate.timer` runs `--next` at the top of every hour
  (`OnCalendar=hourly`). The index is stored in
  `~/.local/state/arch-niri-setup/wallpaper.index`; file order is forced with
  `LC_ALL=C` so the service and an SSH shell always pick the same image.
- `wallpaper-rotate` discovers the niri Wayland socket itself, so it also works
  from the systemd user timer where `WAYLAND_DISPLAY` may be stale.

Manual commands (`~/.local/bin` is not necessarily in the login PATH):

```bash
~/.local/bin/wallpaper-rotate --start       # reapply the current image
~/.local/bin/wallpaper-rotate --next        # switch to the next image now
~/.local/bin/wallpaper-rotate --theme-only  # regenerate theme without touching awww
~/.local/bin/wallpaper-rotate --status      # print index, count and current file
```

Theme scope:

| Target | How |
|---|---|
| Waybar | full generated `style.css` (background, text, accents, slider) |
| mako | background, text and border colors |
| Fuzzel | background, text, match, selection and border |
| Alacritty | background, foreground, cursor and selection |
| niri | focus-ring and border active/inactive/urgent colors |
| GTK / libadwaita | `prefer-dark` + nearest GNOME `accent-color` |

The palette is derived from the wallpaper: a soft dark background from the
dominant hue (raised value, capped saturation), a near-white tinted foreground,
a vivid but softened accent blended from the prominent colorful clusters, and a
contrasting urgent color. Foreground/background contrast is checked
(target >= 7:1) and the accent is kept above 3:1.

Glass / transparency:

| Surface | Setting |
|---|---|
| Waybar pills | `rgba(bg, 0.62)` + accent border + shadow (no blur) |
| Alacritty | `opacity = 0.62` |
| niri terminal rule | `draw-border-with-background false` + `background-effect { blur true; xray false; }` |
| Fuzzel | background alpha 0.80 + layer-rule blur |
| mako | background alpha 0.87 + layer-rule blur |
| GTK apps | opaque Adwaita surfaces with the matching accent color |

niri 26.04 supports background effects on both windows and layer-shell
surfaces. The terminal rule also needs `draw-border-with-background false`:
otherwise niri paints the focus ring/border as a solid accent rectangle behind
the window, and a transparent terminal shows that solid color instead of the
wallpaper.

Waybar is deliberately not blurred. Its layer surface is the full 1280px-wide
strip, so a layer-rule blur affects the transparent gaps between the pills too,
not just the pills. Stock Waybar has no shaped/blur-region API; per-pill blur
would require a different bar architecture. The pills remain semi-transparent
with sharp wallpaper visible in the gaps.

GTK applications cannot be reliably made transparent without a custom theme.

Generated files are **not** edited by hand. The source of truth is
`dotfiles/theme/templates/`; `theme-from-wallpaper` writes the deployed configs
and keeps matching copies in `~/.config/arch-niri-setup/rendered/`. GTK
applications receive the dark scheme and accent color, but their full surface
colors remain Adwaita dark. The niri "Important Hotkeys" overlay is drawn by
niri itself and is not themed.

## VirtualBox 3D acceleration (important)

niri 26.04 **skips software EGL renderers**. On a VirtualBox guest using VMSVGA,
if 3D acceleration is off, niri starts but the console stays black and the log
contains:

```text
software EGL renderers are skipped
no allocator available for device
```

The VM settings must be changed while it is powered off (approval-gated):

```powershell
VBoxManage modifyvm "ArchLinux x86_64" --accelerate3d on --vram 128
```

Verify inside the guest:

```bash
sudo eglinfo -B | grep -E 'SVGA3D|No 3D enabled'
```

`SVGA3D` means the hardware renderer is available. `install/90-validate.sh`
reports this as `gpu:egl`; a missing 3D device is a FAIL, software-only EGL is a
WARN.

## Validation limits

`90-validate.sh` proves that packages exist, configs parse (`niri validate`,
JSON(C), TOML) and services are enabled. It **cannot** prove that a Wayland
session renders. Over SSH, `XDG_SESSION_TYPE=tty` and no `niri` process is
expected.

The graphical console test is mandatory before calling the desktop usable:

1. `sudo systemctl start greetd`
2. Switch to the VM console (VirtualBox window or screenshot).
3. Log in through tuigreet.
4. Confirm niri starts, Waybar appears, `Mod+T` opens Alacritty, `Mod+D` opens
   Fuzzel, notifications render, and audio/network modules are sane.

Snapshot restore, VM shutdown/reboot and disk reset always require explicit
approval.

## Logs

Every step writes a timestamped transcript plus a stable report:

- `logs/preflight.md`
- `logs/validate.md`
- `logs/graphical-test.md`
- `logs/theme-test.md`
- `logs/preflight.env`
- `logs/<step>-<timestamp>.log`

`logs/latest-<step>.log` points at the newest run of each step.

## Differences from the old scripts

- Shared library instead of nine copies of the same helpers.
- `set -Eeuo pipefail`, ERR traps, per-step logs.
- Idempotent package installs (`pacman --needed`, paru `--needed`).
- Backups before replacing managed files; refuses unmanaged files.
- One owner for fcitx5 (niri autostart), no systemd-user + niri + Waybar triple
  start.
- Single Waybar config that hides the IME module until fcitx5 is installed.
- Explicit VM vs bare-metal GPU detection.
- No `sudo paru`, no `makepkg` as root.
- No full system upgrade hidden inside every module script; upgrade happens
  once in `10-packages.sh` and can be skipped with `SKIP_UPGRADE=1`.

## Troubleshooting

- `niri validate -c ~/.config/niri/config.kdl` shows the exact line for syntax
  errors.
- `journalctl --user -b` (after login) and `journalctl -b -u greetd` show
  session failures.
- If Waybar has no niri workspaces, check that Waybar was built with the niri
  module and that `niri msg workspaces` works inside the session.
- If `greetd` shows a black screen, check `/etc/greetd/config.toml` and
  `journalctl -u greetd -b`.
