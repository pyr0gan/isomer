#!/usr/bin/env python3
"""Ensure Python packages required by tools/validate.py are importable.

Installs from requirements.txt via pip when imports are missing. Safe to run
repeatedly (no-op when deps are already present).
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


REQUIRED = ("yaml", "jsonschema")


def missing_modules() -> list[str]:
    absent: list[str] = []
    for name in REQUIRED:
        try:
            __import__(name)
        except ImportError:
            absent.append(name)
    return absent


def main() -> int:
    absent = missing_modules()
    if not absent:
        return 0

    req = Path(__file__).resolve().parent.parent / "requirements.txt"
    print(
        f"Missing Python modules: {', '.join(absent)}. "
        f"Installing from {req.name} …",
        file=sys.stderr,
    )
    cmd = [
        sys.executable,
        "-m",
        "pip",
        "install",
        "--user",
        "-q",
        "-r",
        str(req),
    ]
    try:
        subprocess.check_call(cmd)
    except subprocess.CalledProcessError:
        # Some environments disallow --user; retry without it.
        cmd = [
            sys.executable,
            "-m",
            "pip",
            "install",
            "-q",
            "-r",
            str(req),
        ]
        subprocess.check_call(cmd)

    still = missing_modules()
    if still:
        print(
            "Still missing after install: "
            + ", ".join(still)
            + f". Try manually: {sys.executable} -m pip install -r requirements.txt",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
