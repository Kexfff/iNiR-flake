# iNiR flake notes

## NixOS services

Some QuickShell widgets rely on system D-Bus services that may not be enabled on a minimal NixOS setup.

Enable power profiles support to avoid QuickShell warnings like:
`org.freedesktop.UPower.PowerProfiles` not provided by any `.service` files.

Add this to your NixOS configuration:

```nix
services.power-profiles-daemon.enable = true;
services.upower.enable = true;
```
