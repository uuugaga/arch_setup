# Graphical Console Test

SSH can verify packages, config syntax and services, but **not** that Wayland
renders. Run this procedure on the VirtualBox console (or via
`vbox.vm_screenshot`) after the core install.

## Preconditions

- `install/90-validate.sh` passes over SSH.
- VirtualBox 3D acceleration is on: `--accelerate3d on --vram 128`.
  Inside the guest: `sudo eglinfo -B | grep -E 'SVGA3D|No 3D enabled'`.
- A snapshot exists before changing VM settings.
- `greetd` is enabled. The graphical console is available.

## 1. Greeter test

```bash
sudo systemctl start greetd
```

Expected: tuigreet shows the clock, `Username:` prompt and `niri-session` at
the bottom. Capture a screenshot.

## 2. niri autologin test (test VM only)

> `tests/greetd-autologin.toml` logs in as `uuugaga` without a password. Never
> deploy it on a real machine. Restore the normal config immediately after.

```bash
cd ~/.local/share/arch-niri-setup
sudo cp -a /etc/greetd/config.toml /var/backups/greetd-config-before-autologin-test.toml
sudo install -m644 tests/greetd-autologin.toml /etc/greetd/config.toml
sudo systemctl restart greetd
```

Expected after ~15 seconds:

```bash
pgrep -x niri
pgrep -x waybar
pgrep -x mako
```

Then inspect the session:

```bash
export XDG_RUNTIME_DIR=/run/user/1000
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
export NIRI_SOCKET="$(ls /run/user/1000/niri.*.sock | head -n1)"

niri msg outputs          # Virtual-1, 1280x800, scale 1
niri msg workspaces       # workspace 1
niri msg action spawn -- alacritty
niri msg action spawn -- fuzzel
```

Expected screenshots:

- Waybar: launcher, workspaces, window title, clock, notifications, CPU/RAM,
  network, Bluetooth, mic, volume. The IME module is hidden until fcitx5 is
  installed.
- Alacritty window with the shell prompt and focus ring.
- Fuzzel overlay listing applications.
- mako notification in the top-right corner.

## 3. XWayland and notifications

```bash
niri msg action spawn-sh -- 'DISPLAY=:0 xprop -root > /tmp/xprop.out 2>&1'
sleep 2
head -n 5 /tmp/xprop.out
ps -ef | grep -i xwayland | grep -v grep

gdbus call --session \
  --dest org.freedesktop.Notifications \
  --object-path /org/freedesktop/Notifications \
  --method org.freedesktop.Notifications.Notify \
  "arch-niri-setup" 0 "" "Niri desktop test" "mako works" "[]" "{}" 8000
makoctl list
```

Expected: `xprop` returns X11 root properties, `xwayland-satellite` and
`Xwayland` processes exist, and `makoctl list` shows the notification.

## 4. Cleanup

```bash
export XDG_RUNTIME_DIR=/run/user/1000
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

systemctl --user stop niri.service
niri msg action quit 2>/dev/null || true

cd ~/.local/share/arch-niri-setup
sudo install -m644 dotfiles/greetd/config.toml /etc/greetd/config.toml
sudo systemctl restart greetd
```

Expected: tuigreet returns, `pgrep -x niri` is empty.

## 5. Record the result

Save a short report with:

- date, VM name, GPU/3D setting
- screenshot outcomes for greeter, Waybar, Alacritty, Fuzzel, mako
- `niri msg outputs` and `niri msg workspaces` excerpts
- XWayland and portal results
- any warnings from `journalctl --user -b`
- cleanup confirmation
