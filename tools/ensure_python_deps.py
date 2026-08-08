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


def pip_install(req: Path, *extra_args: str) -> bool:
    cmd = [
        sys.executable,
        "-m",
        "pip",
        "install",
        "-q",
        *extra_args,
        "-r",
        str(req),
    ]
    try:
        subprocess.check_call(cmd)
        return True
    except subprocess.CalledProcessError:
        return False


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

    # Prefer env/interpreter install (venv, setup-python/CI). Fall back to
    # --user for local machines, then --break-system-packages for PEP 668 hosts.
    # Important: pip --user can exit 0 while leaving modules unimportable
    # (e.g. user site disabled), so always re-check after each attempt.
    strategies = (
        (),
        ("--user",),
        ("--break-system-packages",),
    )
    for extra in strategies:
        label = " ".join(extra) if extra else "(default)"
        if not pip_install(req, *extra):
            print(f"pip install {label} failed; trying next strategy …", file=sys.stderr)
            continue
        if not missing_modules():
            return 0
        print(
            f"pip install {label} finished but modules still missing; "
            "trying next strategy …",
            file=sys.stderr,
        )

    still = missing_modules()
    print(
        "Still missing after install: "
        + ", ".join(still)
        + f". Try manually: {sys.executable} -m pip install -r requirements.txt",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
