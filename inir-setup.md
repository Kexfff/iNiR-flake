# iNiR on NixOS (Niri) — setup notes

How the [iNiR](https://github.com/snowarch/iNiR) shell is wired into this repo, and
the non-obvious things that had to be fixed for it to work on NixOS. iNiR's own
docs assume running `./setup install` on Arch; on NixOS most of that has to be
reproduced declaratively, and several runtime assumptions break.

## File map

| File | Purpose |
| --- | --- |
| `flake.nix` | `inir.url = "github:snowarch/inir";` input |
| `modules/home/inir.nix` | Home Manager side: iNiR shell, palette env, config seeding |
| `modules/nixos/desktop/niri.nix` | `my.desktop.niri.enable`: Niri session, XWayland, lock-before-sleep |
| `modules/nixos/desktop/default.nix` | imports `./niri.nix` |
| `modules/home/plasma.nix` | KDE `QT_QPA_PLATFORMTHEME`, dark-scheme fallback |
| `modules/home/default.nix` | xdg-user-dirs autostart shadow, `startServices = "sd-switch"` |
| `hosts/{laptop,desktop}/default.nix` | `desktop.niri.enable = true` |

The split: **system** (`modules/nixos/...`) enables the compositor and anything that
must run as root or before login; **home** (`modules/home/inir.nix`) enables the
shell, its session environment, and seeds per-user config.

## Basic setup

1. **Flake input** — `inir.url = "github:snowarch/inir";` and pass `inputs` down
   (`specialArgs`/`extraSpecialArgs` already do this here).
2. **System module** — `modules/nixos/desktop/niri.nix`, gated by
   `my.desktop.niri.enable`; it sets `programs.niri.enable = true` and installs
   `xwayland-satellite`.
3. **Home module** — `modules/home/inir.nix` imports `inputs.inir.homeModules.inir`
   and sets:
   ```nix
   programs.inir = {
     enable = true;
     service.compositor = "niri";
     extraPackages = [ pkgs.niri ];
     configSymlink.enable = true;   # exposes the shell at ~/.config/quickshell/inir
   };
   ```
4. **Enable per host** — `my.desktop.niri.enable = true`. Plasma stays the default
   SDDM session; pick "Niri" at login.

## The fixes (why each one is needed)

### 1. Nix modules don't install iNiR's bundled Niri config

Upstream `./setup install` copies `defaults/niri/` to `~/.config/niri`. Without it
there is no `40-environment.kdl` (Qt/Wayland/`XDG_CURRENT_DESKTOP` env), no
`50-startup.kdl`, no `70-binds.kdl`, so the shell never gets its environment.

→ `home.activation.inirConfigSeed` copies `defaults/niri` → `~/.config/niri` and
`dots/.config/matugen` → `~/.config/matugen`, **only for files that don't exist**,
because iNiR rewrites `50-startup.kdl`/`70-binds.kdl` and the matugen outputs at
runtime (they must stay writable and not be clobbered on `switch`).

### 2. Palette generation needs a Python environment

`scripts/colors/generate_colors_material.py` imports `numpy`, `PIL` and
`materialyoucolor`. Upstream builds a uv venv; the Nix package ships neither, so
`INIR_VENV` pointed at a nonexistent `~/.local/state/quickshell/.venv`, the
generator died on import, and no palette/`kdeglobals` was ever produced.

→ Build the env and point iNiR at it:
```nix
inirPython = pkgs.python3.withPackages (ps: [ ps.numpy ps.pillow ps.materialyoucolor ]);
```
Set `INIR_VENV` (and the legacy `ILLOGICAL_IMPULSE_VIRTUAL_ENV`) in the
`inir.service` environment and in `home.sessionVariables`.

### 3. iNiR overwrites `PATH`

`scripts/inir` replaces the service `PATH` with the systemd user-manager `PATH`,
dropping the paths `makeWrapper` injected for the package's runtime deps. Anything
the shell spawns **by name** must be on the login/profile PATH, not just
`programs.inir.extraPackages`.

→ Add to `home.packages`: `quickshell` (`qs`), `glib` (`gsettings`), `imagemagick`
(`magick`), `libsecret` (`secret-tool`), `cliphist`, `libqalculate` (`qalc`),
`swayidle`, `swaylock`, `ddcutil`, `darkly`, plus `inirPython`.

`qs` matters specially: the shell spawns `scripts/inir settings-window` straight
from the store, bypassing the wrapper that sets `qs_bin`, so `command -v qs` must
succeed or those subcommands die with "qs not found".

### 4. `gsettings` has no schemas in a Niri session — the big one

No desktop-manager module exposes `gsettings-desktop-schemas` on `XDG_DATA_DIRS`
for Niri, so `gsettings get …` fails with *"No schemas installed"* for every user
service. iNiR's `apply-gtk-theme.sh` runs `set -euo pipefail` and its first step is
`icon_theme=$(gsettings get … | tr -d "'")`; that aborts **after**
`generate_kdeglobals > ~/.config/kdeglobals` has already truncated the file,
leaving a 0-byte `kdeglobals` → generic light theme for all KDE/Qt apps.

It works when run by hand only because an interactive shell's `XDG_DATA_DIRS` often
includes the schema store paths.

→ Point GLib at the schemas directly (no `XDG_DATA_DIRS` surgery):
```nix
gsettingsSchemas =
  "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";
```
Set `GSETTINGS_SCHEMA_DIR` in the `inir.service` environment, in
`home.sessionVariables`, and in `inir-theme-apply`.

### 5. KDE/Qt apps need both a platform theme and the `[Colors:*]` values

KDE apps read their palette from the `[Colors:*]` **values** in `~/.config/kdeglobals`
(not just `General/ColorScheme`; setting the name alone does nothing). plasma-manager
applies its look-and-feel only from inside a Plasma session
(`~/.config/autostart/plasma-manager-autostart.desktop`), which never runs under Niri.

→ Two things:
- `QT_QPA_PLATFORMTHEME = "kde"`: in `modules/home/plasma.nix`
  (`home.sessionVariables`) and appended to `inir.service`'s environment, because
  apps the shell launches inherit the service env, not Niri's `environment {}` block.
- A **non-destructive** BreezeDark fallback (`home.activation.kdeDarkScheme`) that
  only seeds `kdeglobals` when it has no `[Colors:View]`, so it never clobbers
  iNiR's generated scheme.

iNiR then generates the real wallpaper-derived scheme itself
(`apply-gtk-theme.sh` writes `ColorScheme=Darkly` plus all `[Colors:*]`, and
`~/.local/share/color-schemes/Darkly.colors`). Install `pkgs.darkly` so
`QT_STYLE_OVERRIDE=Darkly` resolves.

### 6. Re-apply the palette once the session is up

iNiR's colour pipeline runs very early at login (before dconf/gsettings are ready),
and `apply-gtk-theme.sh` truncates `kdeglobals` before failing.
→ `systemd.user.services.inir-theme-apply`, `After`/`WantedBy=graphical-session.target`,
runs `apply-gtk-theme.sh` as a fallback once the session is actually up.

### 7. XWayland: `xembedsniproxy` aborts without an X server

iNiR starts `xembedsniproxy` (an X11/Qt-xcb app) under Niri. Niri dropped built-in
XWayland, and the nixpkgs module hardcodes `enableXWayland = false`, so the xcb
platform plugin aborts and systemd dumps a core every login.
→ `environment.systemPackages = [ pkgs.xwayland-satellite ]`. Niri 25.08+ integrates
it on demand (creates the X11 socket, exports `DISPLAY`, spawns the satellite when a
client connects). Do **not** add `spawn-at-startup "xwayland-satellite"` or a manual
`DISPLAY` — niri owns those.

### 8. Lock before sleep

iNiR's swayidle `before-sleep` does not fire reliably here, and systemd **user**
managers have no `sleep.target`, so a user unit won't work.
→ `systemd.services.inir-lock-before-sleep` in `modules/nixos/desktop/niri.nix`:
`wantedBy`/`before = [ "sleep.target" ]`. `systemd-suspend.service` is
`After=sleep.target`, so this is guaranteed to run before the freeze. It runs as the
user (to reach the Quickshell IPC socket), skips when `inir.service` isn't active
(e.g. a Plasma session), and `|| true` so a lock failure can never abort suspend.

iNiR's own lock is the primary; `swaylock` is only its fallback — install it so the
fallback *locks* instead of failing open.

### 9. Don't fight Home Manager for the unit file

- Use `systemd.user.services.inir.Service.Environment = [ … ]` (the upstream list).
  Setting `systemd.user.services.inir.environment = { … }` makes HM emit an invalid
  `[environment]` section, and `sd-switch` then fails to parse the unit.
- Do **not** run `inir service install` / `uninstall` / `enable` / `disable`: it
  writes a regular `~/.config/systemd/user/inir.service`, replacing HM's symlink.
  HM then tries to back it up, finds a stale `*.hm-bak`, and aborts the whole
  activation (`backupFileExtension = "hm-bak"` in `modules/nixos/core/users.nix`).
- `xdg-user-dirs-update` similarly rewrites `~/.config/user-dirs.dirs`; it is
  shadowed with a `Hidden=true` autostart entry in `modules/home/default.nix`.

### 10. The icon-theme picker can't see Nix-installed themes

iNiR lists icon themes with `find /usr/share/icons ~/.local/share/icons -maxdepth 1 -type d`
(in `services/IconThemeService.qml`). Nix installs themes into the profile's
`share/icons`, and `-type d` does **not** match symlinks, so the picker is empty.

→ `home.activation.iconThemes` in `modules/home/default.nix` creates a real
directory for each theme under `~/.local/share/icons/<name>` and symlinks the
theme's entries (subdirs, `index.theme`, …) from the store into it. Read-only, no
copying, copy-if-missing. Sources are the packages listed in `iconThemePkgs`:
`whitesur-icon-theme`, `adwaita-icon-theme`, `kdePackages.breeze-icons`
(`WhiteSur*`, `Adwaita`, `breeze`, `breeze-dark`).

## Verify

```sh
# palette generated?
ls ~/.local/state/quickshell/user/generated/{colors,palette,app-palette}.json

# KDE scheme present and dark?
kreadconfig6 --file kdeglobals --group General --key ColorScheme   # Darkly
grep -A2 '^\[Colors:View\]' ~/.config/kdeglobals                   # dark BackgroundNormal

# gsettings works in a service environment?
systemd-run --user --wait --pipe gsettings get org.gnome.desktop.interface icon-theme
```

After `nh os switch`, log out/in once (so `home.sessionVariables` land in the user
manager) and trigger the palette once (change wallpaper or toggle dark/light in
iNiR). KDE apps cache the palette at startup, so fully quit them
(`kquitapp6 dolphin`) before reopening.

## Do / don't

- **Do** trigger palette regeneration through iNiR (wallpaper change, dark/light
  toggle) rather than editing `kdeglobals` by hand.
- **Don't** run iNiR's `./setup` or `inir service …` under NixOS — Home Manager owns
  those files.
- **Don't** add `spawn-at-startup`/`DISPLAY` for XWayland; niri manages it.