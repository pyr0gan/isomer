#!/usr/bin/env python3
"""Fail if content YAML/Markdown contains non-Latin letters (e.g. CJK).

Typographic punctuation already used in the corpus (em dash, arrows, etc.)
is allowed. LLM drafts have previously leaked CJK into gap notes; this check
catches that class of corruption without forcing ASCII-only prose.
"""

from __future__ import annotations

import os
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SCAN_DIRS = (
    "frameworks",
    "mappings",
    "rulesets",
    "rubrics",
    "questions",
    "templates",
    "vocab",
    "schemas",
)
SCAN_SUFFIXES = {".yaml", ".yml", ".md", ".json"}

# Common typography already present in the corpus / docs.
ALLOWED_NON_ASCII = set("—–…→←⟨⟩''""•×")


def is_disallowed(ch: str) -> bool:
    if ord(ch) < 128:
        return False
    if ch in ALLOWED_NON_ASCII or ch.isspace():
        return False
    if unicodedata.category(ch).startswith("L"):
        name = unicodedata.name(ch, "")
        # Allow Latin letters (incl. accented); reject CJK/Hangul/Cyrillic/etc.
        return "LATIN" not in name
    return False


def iter_content_files():
    for dirname in SCAN_DIRS:
        base = ROOT / dirname
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*")):
            if path.is_file() and path.suffix in SCAN_SUFFIXES:
                yield path


def main() -> int:
    errors: list[str] = []
    for path in iter_content_files():
        text = path.read_text(encoding="utf-8")
        for lineno, line in enumerate(text.splitlines(), 1):
            for col, ch in enumerate(line, 1):
                if is_disallowed(ch):
                    rel = os.path.relpath(path, ROOT)
                    name = unicodedata.name(ch, f"U+{ord(ch):04X}")
                    errors.append(
                        f"{rel}:{lineno}:{col}: disallowed non-Latin letter "
                        f"{ch!r} ({name})"
                    )
                    break  # one finding per line is enough
    for e in errors:
        print(f"ERROR {e}")
    print(f"{len(errors)} charset error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
