"""Small, checked adaptations of the pinned upstream runtime for NixOS."""
from pathlib import Path
import sys

root = Path(sys.argv[1])

def replace(file, old, new):
    path = root / file
    text = path.read_text()
    if old not in text:
        raise RuntimeError(f'Upstream changed: {file}: {old!r}')
    path.write_text(text.replace(old, new))

# Retain the dependency closure while incorporating login-specific tools.
replace('scripts/inir', 'local _qs_merged="$_qs_sys_path"',
        'local _qs_merged="$PATH:$_qs_sys_path"')
# Both wrapped and directly invoked launchers must respect declarative ownership.
replace('scripts/inir', 'run_service_command() {', '''run_service_command() {
    case "${1:-status}" in
        install|uninstall|remove|enable|disable)
            echo "inir: service ownership is declarative; use your NixOS/Home Manager configuration" >&2
            return 1
            ;;
    esac''')
# Search XDG locations and follow profile symlinks, including preview paths.
replace('services/IconThemeService.qml', '    property var availableThemes: []', '''    readonly property var iconRoots: [
        (Quickshell.env("XDG_DATA_HOME") || FileUtils.trimFileProtocol(Directories.home) + "/.local/share") + "/icons",
        ...((Quickshell.env("XDG_DATA_DIRS") || "/usr/local/share:/usr/share").split(":").filter(p => p).map(p => p + "/icons"))
    ]
    property var availableThemes: []''')
replace('services/IconThemeService.qml', '''            "/usr/share/icons",
            `${FileUtils.trimFileProtocol(Directories.home)}/.local/share/icons`,''', '''            "-L",
            ...root.iconRoots,''')
# Never truncate a working KDE palette if generation fails.
replace('scripts/colors/apply-gtk-theme.sh', '    generate_kdeglobals > "$KDEGLOBALS"', '''    kde_tmp=$(mktemp "${KDEGLOBALS}.XXXXXX")
    if generate_kdeglobals > "$kde_tmp"; then
        mv -f "$kde_tmp" "$KDEGLOBALS"
    else
        rm -f "$kde_tmp"
        exit 1
    fi''')
replace('scripts/colors/apply-gtk-theme.sh', 'KDEGLOBALS="$HOME/.config/kdeglobals"',
        'KDEGLOBALS="$XDG_CONFIG_HOME/kdeglobals"')
# Functions called in an if condition do not inherit errexit behavior.
for setting in ['icon-theme', 'font-name', 'monospace-font-name']:
    path = root / 'scripts/colors/apply-gtk-theme.sh'
    text = path.read_text()
    start = text.index('generate_kdeglobals() {')
    end = text.index('\n}', start) + 2
    lines = text[start:end].splitlines(keepends=True)
    path.write_text(text[:start] + ''.join(line.rstrip('\n') + ' || return 1\n'
        if '=$(gsettings get org.gnome.desktop.interface ' + setting in line else line
        for line in lines) + text[end:])

# Match the complete candidate array, not an arbitrary `return [` substring:
# the absolute-path guard above it also contains `return []`.
replace('services/IconThemeService.qml', """        return [
            `file://${home}/.local/share/icons/${theme}/apps/scalable/${iconName}.svg`,
            `file:///usr/share/icons/${theme}/apps/scalable/${iconName}.svg`,
            `file://${home}/.local/share/icons/${theme}/scalable/apps/${iconName}.svg`,
            `file:///usr/share/icons/${theme}/scalable/apps/${iconName}.svg`,
            `file://${home}/.local/share/icons/${theme}/apps/256x256/${iconName}.png`,
            `file:///usr/share/icons/${theme}/apps/256x256/${iconName}.png`,
            `file://${home}/.local/share/icons/${theme}/256x256/apps/${iconName}.png`,
            `file:///usr/share/icons/${theme}/256x256/apps/${iconName}.png`,
        ]""", """        return root.iconRoots.flatMap(base => [
            `file://${base}/${theme}/apps/scalable/${iconName}.svg`,
            `file://${base}/${theme}/scalable/apps/${iconName}.svg`,
            `file://${base}/${theme}/apps/256x256/${iconName}.png`,
            `file://${base}/${theme}/256x256/apps/${iconName}.png`
        ])""")
replace('scripts/inir', '    install_user_service >/dev/null', '''    if ! systemctl --user cat inir.service >/dev/null 2>&1; then
        echo "inir: enable the NixOS or Home Manager service first" >&2
        return 1
    fi''')
replace('scripts/inir', "run 'inir service install' to fix", "rebuild your NixOS/Home Manager configuration to fix")
