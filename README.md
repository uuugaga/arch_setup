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

Verified on 2026-11-04 in the VirtualBox guest `ArchLinux x86_64`:

- `logs/validate.md`: **196 PASS / 2 WARN / 0 FAIL** (with an active niri session; logged-out runs add the no-niri warning)
- `logs/graphical-test.md`: niri, Waybar, Alacritty, Fuzzel, mako, XWayland
  and portals confirmed on the graphical console (3D acceleration required)
- `logs/theme-test.md`: hourly wallpaper rotation, soft palette and glass
  transparency verified with both supplied wallpapers
- `logs/display-test.md`: nwg-displays GUI detected niri and the Virtual-1 output
- `logs/ime-test.md`: fcitx5 + Chewing English/Chinese switching, Waybar badge
  and a GTK4 end-to-end input test
- `tests/smoke-test.sh`: 50 PASS / 0 FAIL
- `tests/gaming-test.sh`: 29 PASS / 0 FAIL

The optional `install/50-extras.sh` modules:

- `--apps` is installed and verified on this VM (see `logs/apps-test.md`).
- `--fcitx` is installed and verified on this VM (see `logs/ime-test.md`).
- `--gaming` is installed and verified on this VM (see `logs/gaming-test.md`);
  Vulkan is software-only because the VM has no hardware Vulkan device.
- `--zsh` is installed and verified on this VM (see `logs/zsh-test.md`). The
  login shell remains Bash; only the optional zsh environment was deployed.

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
  55-snapshots.sh     manual-only Snapper + Btrfs Assistant
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
  apps/               app-check helper
  gaming/             MangoHud configuration
  fuzzel/ mako/ alacritty/ greetd/ fcitx5/ systemd/ zsh/
tests/
  smoke-test.sh       fast read-only checks
  gaming-test.sh      optional Steam/gaming checks
  greetd-autologin.toml  TEST FIXTURE ONLY (autologin for console tests)
  graphical-test.md   graphical console test procedure
logs/                 generated reports and transcripts
```

## Requirements

- Arch Linux (VM or bare metal), a normal user in `wheel`.
- VM/test hosts: passwordless sudo (`sudo -n true` must succeed).
- Bare metal/production hosts: normal interactive sudo. Run the installer from
  a terminal so sudo can prompt; the project never creates a NOPASSWD rule.
- Network access to `archlinux.org` and `aur.archlinux.org`.
- At least 3 GiB free on `/` (paru + desktop packages).
- A VirtualBox snapshot before the first install (VM only). Creating/restoring
  snapshots is an approval-gated action in this project.

### Test/VM vs production/bare metal

`install/lib/common.sh` detects the host with `systemd-detect-virt`. Override
with `INSTALL_ENV=vm` or `INSTALL_ENV=baremetal`.

- `vm`: unattended runs. `require_sudo` requires passwordless sudo and uses
  `sudo -n`.
- `baremetal`: production. `require_sudo` uses the caller's normal sudo,
  prompts once with `sudo -v`, and all privileged helpers go through `as_root`.
  No NOPASSWD rule is written. The scripts must run in an interactive terminal;
  a non-interactive SSH run fails before changing anything.

`00-preflight.sh` reports the detected environment and the sudo policy.
`90-validate.sh` never prompts: sudo-only checks report WARN until you run
`sudo -v` in the same terminal first.

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
./install/55-snapshots.sh
./install/60-gpu.sh
./install/90-validate.sh
./tests/smoke-test.sh
```

On bare metal, run these from an interactive terminal: the scripts prompt for
sudo and never create a NOPASSWD rule. VM/test hosts with passwordless sudo can
run the same steps unattended.

`30-niri.sh` enables greetd but does not start it. Start it only when you are
ready to use the graphical console:

```bash
sudo systemctl start greetd
```

Optional modules (run after the core steps; `--fcitx` must run after
`30-niri.sh` because it replaces the niri config with `config.full.kdl`):

```bash
./install/50-extras.sh --fcitx
./install/50-extras.sh --apps
./install/50-extras.sh --gaming
./install/50-extras.sh --zsh
```

`--gaming` enables `[multilib]` and runs `pacman -Syu` before installing Steam.
It does not reboot the machine. `45-theme.sh` already installs the wallpaper
engine, so `50-extras.sh --wallpaper` is only needed if you want to redeploy
its units/scripts manually.

## Common apps (`50-extras.sh --apps`)

Installs the old project's common-app set, using official repositories where
possible:

| Category | Packages |
|---|---|
| Browser / communication | Zen Browser (AUR), Discord, Spotify Launcher, Bitwarden, qBittorrent, Tailscale |
| Mail / remote / transfer | Thunderbird, Parsec (AUR), LocalSend (AUR) |
| Development / containers | VS Code (AUR `visual-studio-code-bin`), Docker, Compose, Buildx, Lazydocker |
| Media / files | Nautilus, mpv, OBS Studio, imv, Tauon Music Box |

Notes:

- Mailspring was removed in favour of **Thunderbird** (the Mailspring AUR build
  failed against the current Node/V8 in this VM).
- AUR packages are installed one at a time; a single failure does not block the
  rest. Rerun `./install/50-extras.sh --apps` after fixing the failure.
- `docker.service` and `tailscaled.service` are enabled and started. The user is
  added to the `docker` group; log out/in before using Docker without sudo.
- Flatpak is intentionally **not** installed. The app set uses official repos
  and paru/AUR only. Install `flatpak` manually if you later need a
  Flathub-only application.
- Run `~/.local/bin/app-check` to verify the app set.
- Tailscale still needs `sudo tailscale up` for account login.
- Spotify Launcher downloads the actual Spotify client on first launch.

## GPU drivers (`60-gpu.sh`)

`60-gpu.sh` detects VMware/VirtualBox, NVIDIA, AMD and Intel from `lspci` and
installs the matching stack. It supports exactly one kernel: the standard Arch
`linux` package. `linux-lts`, `linux-zen`, `linux-hardened`, DKMS and any
multi-kernel setup are intentionally unsupported.

| Platform | Packages / behavior |
|---|---|
| VMware / VirtualBox | Mesa + `vmwgfx` + `libva`; no vendor driver |
| NVIDIA | `nvidia-open`, `nvidia-utils`, `nvidia-settings`, `libva-nvidia-driver`, `vulkan-icd-loader`, `libxnvctrl`; `nvidia_drm.modeset=1` + `fbdev=1`; initramfs rebuild; `nvidia-prime` on hybrids |
| AMD | `vulkan-radeon`, `libva-utils`, `linux-firmware-amdgpu` / `linux-firmware-radeon`; Mesa provides the VA-API driver |
| Intel | `vulkan-intel`, `intel-media-driver`, `libva-intel-driver` (older i965), `libva-utils`, `linux-firmware-intel` |

Notes:

- `nvidia-open` supports Turing (RTX 20xx / GTX 16xx) and newer. Pascal,
  Maxwell and Kepler need a legacy out-of-tree driver; the official repos no
  longer ship the old proprietary `nvidia` packages. `60-gpu.sh` stops with
  an error rather than installing an unsupported open module.
- AMD's `mesa-vdpau` package has been removed from Arch. The supported path is
  VA-API (provided by `mesa`); `vulkan-radeon` provides RADV Vulkan.
- 32-bit libraries are opt-in for the GPU step:
  `WANT_32BIT=1 ./install/60-gpu.sh` adds `lib32-mesa`, the loader and the
  vendor ICD.
- Bare-metal NVIDIA/AMD/Intel paths are implemented and package-checked, but
  only the VMware path has been exercised in this VM.

## Steam / gaming (`50-extras.sh --gaming`)

Steam is in Arch's `[multilib]` repository. The module enables it
automatically (with a backup of `/etc/pacman.conf`), runs a full
`pacman -Syu`, and installs the official-repository gaming stack:

| Category | Packages |
|---|---|
| Steam | `steam`, `steam-devices` |
| 32-bit graphics | `lib32-mesa`, `lib32-vulkan-icd-loader`, plus the detected vendor ICD (`lib32-nvidia-utils`, `lib32-vulkan-radeon` or `lib32-vulkan-intel`) |
| 32-bit audio | `lib32-libpulse`, `lib32-alsa-plugins`, `lib32-alsa-lib` |
| Performance / overlay | `gamemode`, `lib32-gamemode`, `mangohud`, `lib32-mangohud`, `gamescope` |
| Diagnostics / Proton | `vulkan-tools`, `protontricks`; `vulkan-swrast` only on VMs/unknown GPUs |
| UI font | `ttf-liberation` |

`--gaming` selects the 32-bit Vulkan ICD from `lspci`; it only installs
`vulkan-swrast` / `lib32-vulkan-swrast` when no hardware vendor is recognized.
On NVIDIA, run `60-gpu.sh` for the kernel module; `--gaming` already installs
the 32-bit userspace ICD.

It also deploys `~/.config/MangoHud/MangoHud.conf`, creates
`~/Games/SteamLibrary`, and writes `~/.config/arch-niri-setup/gaming` so
`90-validate.sh` can check the module only on machines where it was selected.

First launch:

```bash
steam
```

- Log in with your Steam account. The first start downloads the Steam runtime.
- In **Settings -> Compatibility**, enable Steam Play for all other titles and
  select a Proton version.
- In **Settings -> Storage**, add `~/Games/SteamLibrary`.
- Per-game launch options: `gamemoderun mangohud %command%`.
- On hardware Vulkan, a fixed 1280x800 fullscreen window can use
  `gamescope -W 1280 -H 800 -r 60 -f -- %command%`. On this VM gamescope
  cannot initialize: it rejects lavapipe as "not a valid physical device".
- Controller udev rules come from `steam-devices`; reconnect the controller
  after the first install.

### VM limitation

The VirtualBox guest uses `VMSVGA` / `vmwgfx`, which has **no hardware Vulkan
driver**. `vulkan-swrast` supplies Mesa's `lavapipe` software Vulkan device, so
Steam and Proton can enumerate a device and start, but modern 3D games will be
very slow. After the Steam runtime, the disk has about 19 GB free, which is
enough for the Steam client, Proton and a few small games, not a large
library.

If the Windows host has a gaming GPU, use **Steam Remote Play** from the host
instead of running 3D games inside this VM. Real local gaming needs bare metal
or GPU passthrough.

MangoHud starts and draws its overlay, but `vmwgfx` has no GPU stats and the
VM exposes no CPU temperature sensor, so those fields are blank/zero. GameMode
is D-Bus-activated by `gamemoderun`; it is not enabled at boot and logs
expected cpufreq/polkit warnings in this VM. `gamescope` installs and its help
works, but its Vulkan backend fails on lavapipe, so do not use it in this VM.
Steam's CEF login/store UI also renders through lavapipe and can use a lot of
CPU.

Validation:

```bash
./install/90-validate.sh
./tests/smoke-test.sh
./tests/gaming-test.sh
vulkaninfo --summary
```

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
  PipeWire, NetworkManager, BlueZ, greetd + tuigreet, Noto fonts (including CJK
  and color emoji), screenshot tools.
- Everyday CLI tools (installed with the core set): `less`, `vim`, `nano`,
  `htop`, `btop`, `fastfetch`, `tree`, `wget`, `unzip`, `zip`, `tmux`, `zsh`,
  `cmake`.
- Wallpaper rotation: `awww`; palette extraction: `python-pillow`; desktop
  notifications: `libnotify`.
- The desktop uses Alacritty. kitty is not installed.
- `paru` is built from the AUR with `makepkg -si` as the normal user.
- `xdg-desktop-portal-gnome` and `-gtk` are both installed because niri's
  screencast/file-picker support depends on the portal backend available.
- GPU drivers are delegated to `60-gpu.sh`; the VM uses Mesa + vmwgfx.
- Gaming is optional and official-repository only (`--gaming`); no AUR gaming
  packages are required for the base Steam stack.

## Everyday CLI tools

`10-packages.sh` installs these in the same pacman transaction as the core
desktop packages:

| Category | Tools |
|---|---|
| Pager / editor | `less`, `vim`, `nano` |
| Monitoring | `htop`, `btop`, `fastfetch` |
| Files / archives | `tree`, `unzip`, `zip` |
| Network / sessions | `wget`, `tmux` |
| Shell | `zsh` (installed, **not** made the default) |
| Build | `cmake` |

They are listed separately from `CORE_PKGS` in `config/packages.conf` as
`CLI_PKGS`, so the desktop package set stays minimal. `90-validate.sh` checks
both the package and the command for each entry. `zsh` is available as
`/usr/bin/zsh`; the login shell remains Bash unless you change it yourself with
`chsh -s /usr/bin/zsh`. `50-extras.sh --zsh` additionally installs Starship and
the zsh plugins and deploys the sample `~/.zshrc`. The sample runs `compinit`
with `zsh-completions` on `fpath`, loads autosuggestions, and sources
`zsh-syntax-highlighting` last so its ZLE wrappers stay active. It does not run
`chsh`; changing the login shell remains a manual, explicit choice.

## Waybar UI

- Right-side icons are 18px (the rest of the bar stays at 14px). The IME badge
  is an intentional exception: a 16px bold CJK glyph inside a fixed 22px box.
- `spacing` is `0`. The right-side cluster uses `padding: 0 5px` and
  `margin: 4px 3px` (24px minimum width for icon modules) for a tighter icon
  rhythm; left/center modules keep `padding: 0 9px` and `margin: 4px 4px`.
  The hidden IME module still collapses to zero width instead of reserving a
  gap.
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

## Window borders

niri draws a **1px gradient border** around every window and no separate focus
ring. The gradient is a glass rim light: translucent white at the top fading
into a very faint theme-accent tint at the bottom. The active window uses a
brighter gradient and a deeper shadow; inactive windows use a dimmer gradient
and a lighter shadow. The corner radius stays at 12px.

```kdl
layout {
    focus-ring { off }

    border {
        width 1
        active-gradient from="#ffffff5c" to="#89b4fa40" angle=180
        inactive-gradient from="#ffffff24" to="#89b4fa1f" angle=180
        urgent-color "#f38ba8cc"
    }

    shadow {
        on
        softness 24
        spread 0
        offset x=0 y=5
        color "#00000055"
        inactive-color "#00000030"
    }
}
```

The white rim and the alpha levels are design constants. `theme-from-wallpaper`
rewrites only the gradient's `to` endpoint (accent at 25% / 12% alpha) and the
urgent color (80% alpha), so the edge follows the wallpaper without becoming a
solid colored frame. niri 26.04 accepts `#rrggbbaa` colors and
`linear-gradient`-style gradients; the border width can be fractional, but 1
logical pixel is the intended hairline at scale 1.

## Input method (fcitx5 + Chewing)

`./install/50-extras.sh --fcitx` installs fcitx5, the Chewing (注音) engine,
the GTK/Qt IM modules and the config tool, then deploys the full niri config
with the required environment and autostart:

```kdl
environment {
    GTK_IM_MODULE "fcitx"
    QT_IM_MODULE "fcitx"
    XMODIFIERS "@im=fcitx"
    SDL_IM_MODULE "fcitx"
    GLFW_IM_MODULE "ibus"
}

spawn-at-startup "sh" "-lc" "sleep 1; fcitx5 -d --replace"
```

The profile contains two input methods:

```text
keyboard-us  (English, first/inactive layout)
chewing      (Chinese, 注音, active input method)
```

fcitx5 normalizes `DefaultIM` to the second item, so `DefaultIM=chewing` after
the first save. The session still starts in the inactive English layout; the
first toggle activates Chewing.

### Switching

- Click the **英 / 中** badge in the top-right Waybar cluster.
- Press **Mod+Space** (Super+Space).
- Right-click the badge to open `fcitx5-configtool`.
- Middle-click switches directly to English.
- With a text field focused, fcitx5's own `Ctrl+Space` trigger also works.

fcitx5 only has an input context while a text field is focused. When no field
is focused (state 0), `fcitx5-remote -s` cannot apply the switch immediately.
The click still updates the badge and queues the target in
`~/.cache/arch-niri-setup/ime-pending`; `ime-status.sh` applies it as soon as a
text field gains focus (within about one second). The icon therefore works
from the empty desktop too.

`fcitx5-remote -t` only toggles fcitx5's active/inactive state; it is **not** a
language switch. The project deploys `~/.local/bin/ime-toggle`, which uses
`fcitx5-remote -s keyboard-us` / `-s chewing`.

### Equal-size indicator

The badge deliberately uses two single CJK characters, **英** and **中**, from
the same font (`Noto Sans CJK TC`) at the same 16px bold size. Both use pure
white (`#ffffff`); `中` is **not** tinted with the accent. It also has a fixed
minimum 22×22 box with 5px side padding and a rounded background. This
guarantees both states have the same visual size and color; `EN`/`ZH`,
`EN`/`中`, or mixed Latin/CJK labels do not.

`fcitx5-remote -n` returns an empty name when no text field is focused (state
0). `ime-status.sh` caches the last non-empty state in
`~/.cache/arch-niri-setup/ime-last`; a fresh session has no cache and falls
back to the inactive English layout. It also consumes
`~/.cache/arch-niri-setup/ime-pending`, the target queued by an icon click made
while no text field was focused. The badge remains stable and switches
immediately; the actual IM is applied when the next input context appears.

### fcitx5 config ownership

fcitx5 rewrites `~/.config/fcitx5/profile` and
`~/.config/fcitx5/conf/notifications.conf` without the project marker. The
installer:

- stops fcitx5 before deploying the profile (it saves state on exit);
- keeps an existing profile that already contains `keyboard-us` and `chewing`;
- hides the fcitx5 `wayland-diagnose-other` tip with `HiddenNotifications`.

The diagnostic tip would otherwise appear on every start because the project
keeps `GTK_IM_MODULE=fcitx` for XWayland/Electron compatibility.

### Verified

A GTK4 `zenity --entry` test typed the Chewing sequence `su3`, selected the
first candidate, and returned `你` (UTF-8 `e4 bd a0`). The Waybar badge and
`Mod+Space` were both verified in the live niri session.

Limitations:

- Electron/Chromium apps may need native Wayland flags
  (`--enable-wayland-ime --ozone-platform=wayland`) for the best IME
  experience; otherwise they run under XWayland and use `GTK_IM_MODULE=fcitx`.
- Alacritty/terminal IME support depends on its winit text-input support; the
  GTK4 test is the authoritative desktop input test.
- The VM was not rebooted and the niri session was not restarted during the
  test; the config was applied with `niri msg action load-config-file`.

## Display scaling and multi-monitor

The VM currently has one output, `Virtual-1`, running at 1280x800 with
`scale 1.0`. No automatic resolution/scale detection is applied.

`nwg-displays` (official repo, part of the core package set) provides the GUI.
It detects niri and writes output settings to:

```text
~/.config/niri/monitor.kdl
```

`~/.config/niri/config.kdl` includes it:

```kdl
include "monitor.kdl"
```

The project creates an empty `monitor.kdl` on first install and **never
overwrites it** afterwards. Launch the GUI from Fuzzel or a terminal:

```bash
nwg-displays
```

The GUI exposes position, scale, resolution, refresh rate and DPMS for each
output. Multiple monitors appear as separate draggable blocks; applying writes
`monitor.kdl` and niri reloads it automatically. Niri uses dynamic workspaces,
so nwg-displays does not assign workspaces to outputs.

Windows-to-niri scale examples:

| Windows setup | niri per-output scale |
|---|---|
| 1080p @ 100% | `1.0` |
| 1440p @ 150% | `1.5` |
| 4K @ 200% | `2.0` |

Runtime CLI examples:

```bash
niri msg outputs                       # list output names and modes
niri msg output Virtual-1 scale 1.5    # temporary scale change
niri msg output Virtual-1 mode 1920x1200
niri msg output Virtual-1 position 0 0
```

Notes:

- `niri msg output` changes are temporary; use nwg-displays (or an `output`
  block in `monitor.kdl`) to persist them.
- Fractional scaling (1.25/1.5) works for Wayland-native apps. XWayland apps
  may look blurry; prefer Wayland-native versions where possible.
- The VM has only one virtual output, so the GUI was verified with a single
  `Virtual-1` block. Multi-monitor arrangement uses the same nwg-displays GUI
  and cannot be physically tested without a second output.

## Snapper manual snapshots

The VM uses Btrfs with `@`, `@home`, `@log` and `@pkg`. `55-snapshots.sh`
installs **snapper** and **btrfs-assistant** for manual-only snapshots:

- timeline snapshots are disabled (`TIMELINE_CREATE=no`)
- `snapper-timeline.timer`, `snapper-cleanup.timer`, `snapper-boot.timer` are
  disabled
- `snap-pac` is **not** installed (no automatic pacman pre/post snapshots)
- `grub-btrfs` is **not** installed (no GRUB snapshot menu / `grub-btrfsd`)
- one `baseline-manual` snapshot is created on the first run; reruns keep it
  and do not create duplicates

Commands:

```bash
sudo snapper -c root list
sudo snapper -c root create --description "before update"
sudo snapper -c root delete <number>
btrfs-assistant          # GUI: create/list/delete/restore
```

`NUMBER_LIMIT=5` and `NUMBER_LIMIT_IMPORTANT=3` are set, but the automatic
cleanup timer is disabled; delete old snapshots manually or via Btrfs Assistant.

Why manual:

- frequent updates would otherwise create a large number of timeline/pacman
  snapshots
- a large snapshot set makes GRUB regeneration and Btrfs metadata maintenance
  heavier
- manual snapshots are taken only before major updates (kernel, systemd, mesa,
  niri, GPU drivers)

Limitations:

- no GRUB snapshot boot entries; restore with Btrfs Assistant or from a live
  environment (`snapper rollback`)
- snapshots are not backups; use `btrbk` to an external disk for that
- root snapshots cover `@` (including `/boot`) but not `@home`
- `@log` and `@pkg` are separate subvolumes and are not included

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
| niri | glass border gradient accent endpoint and urgent color |
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
| niri window edge | 1px top-to-bottom gradient (36% white -> 25% accent) + soft shadow |
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
- `logs/display-test.md`
- `logs/ime-test.md`
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
- IME toggle uses explicit `-s keyboard-us` / `-s chewing`; `fcitx5-remote -t`
  only toggles fcitx5 active/inactive.
- The English/Chinese badge uses same-font single CJK glyphs and a fixed box.
- Explicit VM vs bare-metal GPU detection.
- No `sudo paru`, no `makepkg` as root.
- No full system upgrade hidden inside every module script; upgrade happens
  once in `10-packages.sh` and can be skipped with `SKIP_UPGRADE=1`.

## Troubleshooting

- A red `Calling import-environment without a list of variable names is
  deprecated.` line on the greeter VT is a systemd warning from
  `niri-session`. `30-niri.sh` deploys
  `/etc/systemd/system/greetd.service.d/90-quiet-import.conf` with
  `SYSTEMD_LOG_LEVEL=err`, which suppresses the warning for the greeter session
  while still showing errors.
- `niri validate -c ~/.config/niri/config.kdl` shows the exact line for syntax
  errors.
- `journalctl --user -b` (after login) and `journalctl -b -u greetd` show
  session failures.
- If Waybar has no niri workspaces, check that Waybar was built with the niri
  module and that `niri msg workspaces` works inside the session.
- If `greetd` shows a black screen, check `/etc/greetd/config.toml` and
  `journalctl -u greetd -b`.
