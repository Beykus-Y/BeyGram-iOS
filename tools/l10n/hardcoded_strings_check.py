#!/usr/bin/env python3
"""Ratchet for hardcoded language switches in BeyGram modules: `isRu ? "..." : "..."` and language-code prefix checks.

New user-facing text goes to the Android resources (tools/l10n/android_strings.py) and is read with BeyGramAndroidStrings.
The count of remaining hardcoded switches is kept in tools/l10n/hardcoded_strings_baseline.txt and may only go down.
    python3 tools/l10n/hardcoded_strings_check.py            # check, exit 1 if the count grew
    python3 tools/l10n/hardcoded_strings_check.py --update   # write the baseline (after migrating strings)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASELINE = Path(__file__).with_name("hardcoded_strings_baseline.txt")
PATTERN = re.compile(r'\bisRu\s*\?|isRussian\s*\?|hasPrefix\("ru"\)')


def count() -> int:
    total = 0
    for path in sorted((ROOT / "submodules").glob("BeyGram*/Sources/**/*.swift")):
        if path.parts[-4:-1] == ("BeyGramKit", "Sources", "Generated") or "Generated" in path.parts:
            continue
        total += sum(1 for line in path.read_text(encoding="utf-8").splitlines() if PATTERN.search(line))
    return total


def main():
    current = count()
    if "--update" in sys.argv:
        BASELINE.write_text(f"{current}\n")
        print(f"baseline set to {current}")
        return
    allowed = int(BASELINE.read_text().strip())
    print(f"hardcoded language switches: {current} (baseline {allowed})")
    if current > allowed:
        print("New hardcoded strings: move them to the Android resources and BeyGramAndroidStrings.", file=sys.stderr)
        sys.exit(1)
    if current < allowed:
        print("Fewer than the baseline: run with --update to lower it.")


if __name__ == "__main__":
    main()
