"""Create a Default Slurm profile only when the user has no profiles.

Blackfish's noninteractive `init` names its generated profile `default`.
Create the requested `Default` entry before init, preserving existing profile
configuration. Only Python's standard library is needed.
"""

import argparse
import configparser
import fcntl
import io
import os
from pathlib import Path


def ensure_profile(home_dir, cache_dir, user):
    home = Path(home_dir)
    if not home.is_absolute():
        raise ValueError("Home directory must be an absolute path")

    path = home / "profiles.cfg"
    descriptor = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    with os.fdopen(descriptor, "r+", encoding="utf-8") as file:
        # Serialize concurrent attempts to append our profile to this file.
        fcntl.flock(file, fcntl.LOCK_EX)
        existing = file.read()
        profiles = configparser.ConfigParser()
        profiles.read_string(existing)
        if profiles.sections():
            print("Existing profiles found; preserving their settings and default selection.")
            return

        # The admin cache is only required for first-time profile creation.
        cache = Path(cache_dir)
        if not cache.is_absolute():
            raise ValueError("Admin cache directory must be an absolute path")
        if not cache.is_dir() or not os.access(cache, os.R_OK | os.X_OK):
            raise ValueError("Admin cache directory must exist and be readable")

        # Preserve comments or INI defaults in an otherwise empty profile file.
        entry = configparser.ConfigParser()
        entry["Default"] = {
            "schema": "slurm",
            "host": "localhost",
            "user": user.replace("%", "%%"),
            "home_dir": str(home).replace("%", "%%"),
            "cache_dir": str(cache).replace("%", "%%"),
            "default": "true",
        }
        buffer = io.StringIO()
        entry.write(buffer)
        file.seek(0, os.SEEK_END)
        if existing and not existing.endswith("\n"):
            file.write("\n")
        file.write("\n" + buffer.getvalue())
        print("Created profile 'Default' using the administrator's shared cache.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home-dir", required=True)
    parser.add_argument("--cache-dir", required=True)
    parser.add_argument("--user", required=True)
    args = parser.parse_args()
    try:
        ensure_profile(args.home_dir, args.cache_dir, args.user)
    except (OSError, ValueError, configparser.Error) as error:
        parser.exit(1, "Could not prepare initial profile: {}\n".format(error))
