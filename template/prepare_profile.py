"""Add the OnDemand Slurm profile without replacing the user's configuration.

Blackfish's noninteractive `init` only creates a profile named `default`.
Its profiles.cfg is an INI file; append our named entry before calling init so
Blackfish bootstraps its data without creating or replacing other profiles.
Only Python's standard library is needed, independently of Blackfish's Python.
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
        if profiles.has_section("ondemand"):
            print("OnDemand profile already exists; preserving its settings.")
            return

        # The admin cache is only required when creating the OnDemand profile.
        cache = Path(cache_dir)
        if not cache.is_absolute():
            raise ValueError("Admin cache directory must be an absolute path")
        if not cache.is_dir() or not os.access(cache, os.R_OK | os.X_OK):
            raise ValueError("Admin cache directory must exist and be readable")

        # Blackfish falls back to a section named `default`, then the first
        # section, when none has an explicit default flag. Append rather than
        # rewriting, so those selections (and comments/formatting) stay intact.
        entry = configparser.ConfigParser()
        entry["ondemand"] = {
            "schema": "slurm",
            "host": "localhost",
            "user": user.replace("%", "%%"),
            "home_dir": str(home).replace("%", "%%"),
            "cache_dir": str(cache).replace("%", "%%"),
            "default": "false" if profiles.sections() else "true",
        }
        buffer = io.StringIO()
        entry.write(buffer)
        file.seek(0, os.SEEK_END)
        if existing and not existing.endswith("\n"):
            file.write("\n")
        file.write("\n" + buffer.getvalue())
        print("Created OnDemand profile using the administrator's shared cache.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home-dir", required=True)
    parser.add_argument("--cache-dir", required=True)
    parser.add_argument("--user", required=True)
    args = parser.parse_args()
    try:
        ensure_profile(args.home_dir, args.cache_dir, args.user)
    except (OSError, ValueError, configparser.Error) as error:
        parser.exit(1, "Could not prepare OnDemand profile: {}\n".format(error))
