<div align="center">

# ❄️ inir-flake

**A batteries-included, zero-headache NixOS flake & Home Manager module for [iNiR](https://github.com/snowarch/iNiR)**  
*Complete desktop shell for Niri built on Quickshell, Material You dynamic theming, and full system integration.*

[![NixOS](https://img.shields.io/badge/NixOS-unstable-blue?logo=nixos&logoColor=white&style=flat-square)](https://nixos.org)
[![Niri](https://img.shields.io/badge/Compositor-Niri-purple?style=flat-square)](https://github.com/YaLTeR/niri)
[![Quickshell](https://img.shields.io/badge/UI_Framework-Quickshell-7aa2f7?style=flat-square)](https://quickshell.outfoxxed.me/)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-green.svg?style=flat-square)](https://www.gnu.org/licenses/gpl-3.0.html)

[Overview](#-overview) • [Why This Flake?](#-why-this-flake) • [Quick Start](#-quick-start) • [Installation Methods](#-installation-methods) • [Configuration Reference](#-configuration-reference) • [Configuration Modes: dotsmode](#-configuration-modes-dotsmode) • [Keybinds](#-keybinds) • [Troubleshooting](#-troubleshooting)

</div>

---

## 📖 Overview

[iNiR](https://github.com/snowarch/iNiR) is an exceptional, full-featured desktop environment shell for the [Niri](https://github.com/YaLTeR/niri) scrollable-tiling Wayland compositor. It features three panel families (**Material ii**, **Waffle**, and **iRiS**), automatic Material You wallpaper color generation, modular widgets, an overview, clipboard manager, screen recording, OCR, and rich media controls.

While upstream provides an experimental flake, it leaves crucial system-level plumbing unaddressed—resulting in broken font paths, missing PAM rules, failing Python virtual environments in read-only store paths, absent Polkit agents, missing XDG portals, and hardware access permission errors.

**`inir-flake` provides the NixOS integration for these components.** It maps the entire [Arch package reference](https://github.com/snowarch/iNiR/wiki/PACKAGES) directly onto `nixpkgs`, wires every user and system service, provisions a closed Python environment for wallpaper theming and InnerTube playback, configures PAM and Polkit, and provides sane default dotfiles out of the box.

```nix
# That's literally all you need in your NixOS configuration:
programs.inir = {
  enable = true;
  users = [ "yourusername" ]; # grants ydotool, ddcutil & evdev hardware access
};
```

---

## ⚡ Why This Flake?

Here is what happens with upstream's packaging vs. what `inir-flake` does:

| Feature / Subsystem | Upstream Flake Issue | `inir-flake` Solution |
| :--- | :--- | :--- |
| **🔤 Font System** | Sets `FONTCONFIG_FILE` strictly to Material Symbols, which hides all system and user fonts from the shell and causes text rendering failure. | Installs all required fonts (`Roboto Flex`, `Gabarito`, `Oxanium`, `Readex Pro`, `Rubik`, `Space Grotesk`, `JetBrainsMono Nerd`, `Twemoji`, `Material Symbols`) via `fonts.packages` and configures Fontconfig fallback rules. |
| **🐍 Python Environment** | Upstream tries to build an unmanaged `uv` venv in `~/.local/state/quickshell/.venv` at runtime, which fails in pure Nix setups. | Provisions a hermetic `python3.withPackages` containing `materialyoucolor`, `ytmusicapi`, `yt-dlp`, `secretstorage`, `evdev`, `pillow`, `dbus-python`, and exports `INIR_VENV` and `ILLOGICAL_IMPULSE_VIRTUAL_ENV`. |
| **🔒 Lock Screen / PAM** | Suspending or locking fails to unlock because `security.pam.services.swaylock` is absent. | Automatically enables `security.pam.services.swaylock = {}` and binds `gnome-keyring` to PAM authentication. |
| **🛡️ Polkit & Secrets** | Upstream spawns Arch `/usr/lib/mate-polkit/...` which doesn't exist on NixOS. | Runs `polkit-gnome` as a dedicated systemd user unit bounded to `niri.service` and activates `gnome-keyring`. |
| **🌐 XDG Desktop Portals** | Missing screensharing, file chooser, and Secret portal coordination. | Configures `xdg.portal` with GTK & GNOME portals prioritized for Niri with explicit Secret and FileChooser routing. |
| **⌨️ Input & Hardware** | Virtual typing (`ydotool`), DDC/CI monitor brightness (`ddcutil`), and evdev fail with permission denied. | Enables `programs.ydotool`, `hardware.i2c`, and automatically adds configured users to `input`, `video`, `i2c`, `ydotool`, and `networkmanager` groups. |
| **🎨 Qt & GTK Theming** | Qt apps don't match Material You colors because `plasma-integration`, `Darkly`, and `kdeglobals` aren't wired. | Sets `qt.platformTheme = "kde"` (reads generated `kdeglobals`), injects `QT_STYLE_OVERRIDE = "Darkly"`, and sets up Kvantum, breeze-icons, and GTK 3/4 themes. |
| **🧩 Niri Configuration** | Upstream niri config has hardcoded Arch paths (`/usr/bin/qs`, `qs -c inir ...`, `launch-terminal.sh`). | Packages the complete `defaults/niri/` tree and seeds writable configuration before Niri starts, with Nix-compatible helper paths. |
| **📦 Missing Tools** | Crashes when running OCR, video recording, or equalizers. | Bundles `tesseract` with 9 language datasets (eng, spa, rus, jpn, chi), `mpv` with MPRIS script, `wf-recorder`, `easyeffects` + `lsp-plugins`, `hyprpicker`, `swappy`, etc. |
| **🐱 Kira Mascot Pack** | Upstream's `inir-with-mascot` uses a `symlinkJoin` that the wrapper script ignores. | Extracts the verified v3 mascot art pack into the derivation's runtime asset directory so `mascot.enable = true` works instantly. |

---

## 🚀 Quick Start

### 1. Add Flake Input

In your system `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # Add inir-flake
    inir.url = "github:YOUR_USER_OR_REPO/inir-flake";
    inir.inputs.nixpkgs.follows = "nixpkgs"; # Ensures a single shared Qt/KDE closure
  };

  outputs = { self, nixpkgs, inir, ... }: {
    nixosConfigurations.myhostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        inir.nixosModules.default
      ];
    };
  };
}
```

### 2. Enable in your `configuration.nix`

```nix
{ pkgs, ... }: {
  programs.inir = {
    enable = true;
    users = [ "alice" ]; # Replace with your username
    
    # Optional: If you don't have a display manager (GDM/SDDM), enable greetd
    greeter.enable = true;
    
    # Optional features:
    # mascot.enable = true;      # Include Kira desktop mascot artwork
    # fingerprint.enable = true; # Enable fprintd for biometric unlock
    # ai.ollama.enable = true;   # Enable local Ollama for the AI sidebar
  };
}
```

### 3. Rebuild and Launch

```bash
sudo nixos-rebuild switch --flake .#myhostname
```

If using greetd, log in; if starting manually from a TTY:
```bash
niri-session
```
The iNiR shell will start automatically through `inir.service` upon compositor launch!

---

## 💻 Installation Methods

### Method A: NixOS System Module (Recommended)

Importing `inir.nixosModules.default` configures both the system requirements (PAM, udev, groups, portals, PipeWire) and the user-level systemd service.

```nix
{ inputs, pkgs, ... }: {
  imports = [ inputs.inir.nixosModules.default ];

  programs.inir = {
    enable = true;
    users = [ "alice" ];

    # Extra CLI / TUI tools to make available inside inir's environment:
    extraPackages = with pkgs; [
      whisper-cpp      # Local speech-to-text
      cloudflare-warp  # Cloudflare WARP quick toggle
    ];
  };
}
```

---

### Method B: Home Manager Module

You can also manage iNiR on a per-user basis with Home Manager.

> **Note:** If running Home Manager on NixOS, it is recommended to also enable `inir.nixosModules.default` (or configure `programs.ydotool`, `hardware.i2c`, and `security.pam.services.swaylock = {}` on the NixOS side).

```nix
# home.nix
{ inputs, pkgs, ... }: {
  imports = [ inputs.inir.homeManagerModules.default ];

  programs.inir = {
    enable = true;
    
    # Writable dotfiles; "symlink" links only the Matugen template directory
    dots.mode = "copy";
    
    # Keep ~/.config/quickshell/inir symlink active for scripts
    configSymlink.enable = true;

    # Set cursor theme in GTK and user session
    pointerCursor.enable = true;
  };
}
```

---

### Method C: Run without Installing (`nix run`)

You can test iNiR directly inside an existing Niri session without altering your system configuration:

```bash
# Launch the iNiR shell directly
nix run github:YOUR_USER_OR_REPO/inir-flake -- run

# Run the health check diagnostic
nix run github:YOUR_USER_OR_REPO/inir-flake -- doctor

# Open the settings GUI
nix run github:YOUR_USER_OR_REPO/inir-flake -- settings
```

---

## ⚙️ Configuration Reference

### All Available Options (`programs.inir.*`)

| Option | Type | Default | Scope | Description |
| :--- | :--- | :--- | :--- | :--- |
| `enable` | `bool` | `false` | Both | Enable the iNiR desktop shell, wrapper, fonts, and services. |
| `package` | `package` | *auto* | Both | The iNiR package to use. Built against your system's `pkgs` set. |
| `users` | `listOf str` | `[ ]` | NixOS | Usernames to add to `input`, `video`, `i2c`, `ydotool`, and `networkmanager` groups. |
| `dots.enable` | `bool` | `true` | Both | Provide default configurations for Niri, Darkly, Kvantum, GTK, Fuzzel, Kitty, and Foot. |
| `dots.mode` | `enum [ "copy" "symlink" ]` | `"copy"` | HM | `"copy"` seeds writable files; `"symlink"` links Matugen templates while keeping runtime configuration writable. |
| `configSymlink.enable`| `bool` | `true` | HM | Exposes `~/.config/quickshell/inir` pointing to the packaged runtime. |
| `fonts.enable` | `bool` | `true` | Both | Installs and configures all required fonts and Fontconfig presets. |
| `installRuntimePackages` | `bool` | `true` | Both | Installs kitty, nautilus, fuzzel, wl-clipboard, cliphist, grim, slurp, playerctl into system PATH. |
| `mascot.enable` | `bool` | `false` | Both | Bundles the official Kira desktop mascot art pack into the runtime package. |
| `polkitAgent.enable` | `bool` | `true` | Both | Runs `polkit-gnome` as a systemd user service bound to `niri.service`. |
| `extraPackages` | `listOf pkg` | `[ ]` | Both | Extra packages made available to `inir.service` (e.g. `whisper-cpp`, `cava`). |
| `environment` | `attrsOf str` | `{ }` | Both | Additional environment variables passed into `inir.service`. |
| `service.enable` | `bool` | `true` | Both | Creates the `inir.service` systemd user unit. |
| `service.compositor`| `nullOr (enum ["niri"])` | `"niri"` | Both | Sets systemd `WantedBy` unit. Set to `null` to disable auto-start. |
| `niri.enable` | `bool` | `true` | NixOS | Enables `programs.niri` from nixpkgs. |
| `audio.enable` | `bool` | `true` | NixOS | Enables PipeWire, WirePlumber, ALSA/Pulse compatibility, and RealtimeKit (`rtkit`). |
| `network.enable` | `bool` | `true` | NixOS | Enables NetworkManager for the status bar Wi-Fi / Ethernet applet. |
| `bluetooth.enable` | `bool` | `true` | NixOS | Enables `hardware.bluetooth` and `services.blueman`. |
| `greeter.enable` | `bool` | `false` | NixOS | Enables `greetd` + `tuigreet` auto-configured for `niri-session`. |
| `fingerprint.enable`| `bool` | `false` | NixOS | Enables `services.fprintd` for biometric lock screen unlocking. |
| `ai.ollama.enable` | `bool` | `false` | NixOS | Enables `services.ollama` for local LLM inference in the left sidebar AI chat. |
| `pointerCursor.enable`| `bool`| `true` | HM | Configures `capitaine-cursors-light` (24px) for Home Manager with GTK sync. |

---

## 📂 Configuration Modes: `dots.mode`

The package ships the complete upstream `defaults/niri/` tree, including all nine
`config.d/*.kdl` files, and the Matugen templates. Home Manager seeds writable
files during activation. Both modules also install `inir-config.service`, ordered
before `niri.service`, so the NixOS-only installation gets per-user configuration
on first login. NixOS additionally provides the complete `/etc/niri` fallback.

Existing custom files are preserved. An exact match for the old packaged
monolithic Niri config is backed up as `config.kdl.pre-modular` and upgraded.
Modified monolithic configs are left alone, with a message pointing to the seeded
`config.d` directory; merge your changes into the modular config manually.
`90-user-extra.kdl` is the place for personal overrides.

`dots.mode = "copy"` is the default. With `dots.mode = "symlink"`, only the
Matugen template directory is linked to the store. Niri, KDE, GTK, terminal and
other runtime configuration stays writable in both modes because iNiR edits it.
This changes the older behavior that linked those writable files. Home Manager
removes its old managed links during activation before seeding replacements.
Existing unmanaged symlinks are left untouched.

If `kdeglobals` lacks `[Colors:View]`, seeding backs it up as
`kdeglobals.pre-inir` and fills missing color values without discarding unrelated
settings. Theme generation uses an explicit GSettings schema directory and
replaces the palette only after successful generation. There is no theme-reapply
service.

List every iNiR login user in `programs.inir.users` on the NixOS side. Each gets a
system lock-before-sleep unit, which skips inactive iNiR sessions and invokes
`inir lock prepareSleep` on every sleep. Lock errors remain visible in the journal;
this ordering hook does not guarantee that systemd will cancel suspend on failure.
Home Manager alone cannot install this system-level hook.

The package preserves runtime dependencies when importing the login PATH and
includes `secret-tool` and the Python environment in session tools. NixOS installs
XWayland satellite even when `installRuntimePackages` is disabled. The icon picker
searches XDG data directories and follows Nix profile links.

Home Manager shadows the XDG user-directory autostart when it owns user dirs;
the NixOS module does not run a competing updater. Do not run upstream `./setup`.
`inir service install/uninstall/enable/disable` are rejected by this package;
manage service ownership through NixOS/Home Manager. Start, stop, restart, status,
and logs remain available without rewriting the managed unit.

---

## ⌨️ Keybinds

The bundled Niri configuration comes pre-mapped with all iNiR shortcuts:

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| <kbd>Super</kbd> + <kbd>Space</kbd> | **Toggle Overview** | Material ii / iRiS search, workspace matrix, and calculator. |
| <kbd>Super</kbd> + <kbd>V</kbd> | **Clipboard History** | Searchable clipboard history with image thumbnail previews. |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>S</kbd> | **Region Screenshot** | Interactive region screenshot with Swappy editor integration. |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>X</kbd> | **Region OCR** | Snips a screen region and copies extracted text via Tesseract. |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>A</kbd> | **Region Search** | Snips a screen region and performs reverse image search. |
| <kbd>Super</kbd> + <kbd>,</kbd> | **Settings GUI** | Opens the live iNiR preferences and style studio window. |
| <kbd>Super</kbd> + <kbd>/</kbd> | **Cheatsheet** | Visual overlay displaying active Niri keybinds. |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>W</kbd> | **Cycle Panel Family** | Instantly switches between **iRiS**, **Material ii**, and **Waffle**. |
| <kbd>Super</kbd> + <kbd>Alt</kbd> + <kbd>L</kbd> | **Lock Screen** | Engages the Quickshell / Swaylock secure lock screen. |
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>T</kbd> | **Wallpaper Selector**| Opens the Wallhaven & local wallpaper browser. |
| <kbd>Alt</kbd> + <kbd>Tab</kbd> | **Window Switcher** | Smooth animated Material Alt-Tab window switcher. |
| <kbd>Super</kbd> + <kbd>T</kbd> | **Terminal** | Launches the configured terminal emulator (default: Kitty). |
| <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>E</kbd> | **Quit Niri** | Exits the compositor session. |

---

## 🛠️ Troubleshooting & Management

### Useful CLI Commands

The `inir` CLI wrapper is fully available in your shell:

```bash
# Check runtime health and diagnose missing optional backends
inir doctor

# Tail full live logs with error category grouping
inir logs --full

# Restart the shell service
inir restart

# Open the settings panel
inir settings

# View current shell status, active panel family, and scale
inir status

# Inspect the resolved runtime store path
inir path
```

### Updating iNiR on NixOS

> ⚠️ **Important:** Do **not** run `inir update` or `./setup update` inside a Nix system! The Nix store is immutable.

To update iNiR to the latest upstream release:

```bash
# 1. Update the flake input lockfile
nix flake lock --update-input inir-src

# 2. Rebuild your NixOS system
sudo nixos-rebuild switch --flake .#myhostname
```

### Common Issues & Solutions

1. **"My wallpaper is black on first login"**  
   Open the wallpaper selector (<kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>T</kbd>) or run `inir wallpaperSelector toggle` and choose a wallpaper. Material You will extract the color palette and propagate it across all UI elements.
2. **"Wi-Fi toggle doesn't show any networks"**  
   Ensure `networking.networkmanager.enable = true` is on and your user is listed in `programs.inir.users`.
3. **"Virtual typing or brightness slider doesn't respond"**  
   Ensure your username is passed to `programs.inir.users = [ "yourusername" ];` so your user is granted `uinput` (`ydotool`) and `i2c` (`ddcutil`) permissions.

---

## 📦 Project Structure

```
.
├── flake.nix              # Flake entrypoint (packages, apps, modules, overlays)
└── nix/
    ├── deps.nix           # Arch package reference -> nixpkgs attribute mapping
    ├── package.nix        # Hermetic stdenv derivation & launcher wrapper
    ├── mascot-pack.nix    # Pinned Kira mascot release fetcher
    ├── options.nix        # Common NixOS & Home Manager option declarations
    ├── nixos-module.nix   # NixOS system module (PAM, portals, polkit, services)
    └── home-module.nix    # Home Manager user module (activation, dotfiles, symlinks)
```

---

<div align="center">

Made with ❄️ for the **NixOS** and **Niri** community.  
Upstream iNiR project: [github.com/snowarch/iNiR](https://github.com/snowarch/iNiR)

</div>
