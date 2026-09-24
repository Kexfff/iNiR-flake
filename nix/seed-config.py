"""Seed writable defaults without replacing user configuration or following links."""
import argparse
import os
from pathlib import Path
import shutil
import tempfile


def seed(source, target, legacy=None):
    source, target = Path(source), Path(target)
    if target.is_symlink():
        print(f'inir: refusing to seed through symlink {target}')
        return
    # Upgrade only the exact, previously shipped monolithic default.
    config = target / 'niri/config.kdl'
    migrate = False
    if legacy and not config.parent.is_symlink() and config.is_file() and not config.is_symlink():
        if config.read_bytes() == Path(legacy).read_bytes():
            backup = config.with_name('config.kdl.pre-modular')
            if not backup.exists():
                shutil.copy2(config, backup)
                migrate = True
    def copy_missing(src, dst):
        if dst.is_symlink():
            return
        if src.is_dir():
            if dst.exists() and not dst.is_dir():
                return
            dst.mkdir(parents=True, exist_ok=True)
            for child in src.iterdir():
                copy_missing(child, dst / child.name)
        elif not dst.exists():
            shutil.copyfile(src, dst)
            dst.chmod((src.stat().st_mode & 0o777) | 0o200)
    copy_missing(source, target)
    if migrate:
        with tempfile.NamedTemporaryFile(dir=config.parent, delete=False) as tmp:
            tmp.write((source / 'niri/config.kdl').read_bytes())
        os.chmod(tmp.name, config.stat().st_mode & 0o777)
        os.replace(tmp.name, config)
    elif config.is_file() and config.read_bytes() != (source / 'niri/config.kdl').read_bytes():
        if b'config.d/' not in config.read_bytes():
            print(f'inir: preserved custom {config}; modular defaults are available in {config.parent / "config.d"}')
    # Keep unrelated KDE settings and back up an incomplete palette before repair.
    kde = target / 'kdeglobals'
    if kde.is_file() and not kde.is_symlink():
        text = kde.read_text()
        if '[Colors:View]' not in text:
            backup = kde.with_name('kdeglobals.pre-inir')
            if not backup.exists():
                shutil.copy2(kde, backup)
            import configparser
            current = configparser.RawConfigParser(strict=False)
            current.optionxform = str
            fallback = configparser.RawConfigParser(strict=False)
            fallback.optionxform = str
            try:
                current.read_string(text)
                fallback.read(source / 'kdeglobals')
            except configparser.Error:
                print(f'inir: cannot parse {kde}; leaving it unchanged')
                return
            for section in fallback.sections():
                if section.startswith('Colors:'):
                    if not current.has_section(section):
                        current.add_section(section)
                    for key, value in fallback.items(section):
                        if not current.has_option(section, key):
                            current.set(section, key, value)
            with tempfile.NamedTemporaryFile(mode='w', dir=target, delete=False) as tmp:
                current.write(tmp, space_around_delimiters=False)
            os.chmod(tmp.name, kde.stat().st_mode & 0o777)
            os.replace(tmp.name, kde)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source')
    parser.add_argument('--target', default=os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config')))
    parser.add_argument('--legacy')
    args = parser.parse_args()
    seed(args.source, args.target, args.legacy)
