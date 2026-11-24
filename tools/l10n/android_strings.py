#!/usr/bin/env python3
"""Generates BeyGram's iOS string tables from the Android BeyGram resources (one source of strings).

    python3 tools/l10n/android_strings.py --android-res ../BeyGram/app/src/main/res          # write the Swift file
    python3 tools/l10n/android_strings.py --android-res ../BeyGram/app/src/main/res --check  # verify only, write nothing

Keys are the Android resource names. Languages: ru (Android `values/`, the default), en, de, es, fr.
Placeholders are converted for Swift's String(format:): %1$s -> %1$@, %1$d -> %1$lld, %s -> %@, %d -> %lld.
Only the files in FILES are taken: the strings of features that exist on iOS. Add a file to FILES when its screen lands.
Checks (exit 1 on failure): every key exists in every language, no empty values, placeholders match the Russian string.
"""
import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

LANGUAGES = [("ru", "values"), ("en", "values-en"), ("de", "values-de"), ("es", "values-es"), ("fr", "values-fr")]
FILES = [
    "strings_bgwave", "strings_bgmusic", "strings_profile_music", "strings_yandex_music",
    "strings_yandex_wave_settings", "strings_music_attach", "strings_music_radio_dislike",
    "strings_stealth", "strings_stealth_actions", "strings_stealth_risky", "strings_stealth_schedule",
    "strings_privacy", "strings_delayed_send", "strings_triggers", "strings_equalizer",
]
CATEGORIES = ["zero", "one", "two", "few", "many", "other"]
PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?([-#+ 0,(]*\d*(?:\.\d+)?)([sdf%])")
DEFAULT_OUT = Path(__file__).resolve().parents[2] / "submodules/BeyGramKit/Sources/Generated/BeyGramAndroidStrings.swift"


def unescape(text: str) -> str:
    """Android resource text: surrounding quotes, backslash escapes, collapsed whitespace outside quotes."""
    text = text.strip()
    if len(text) >= 2 and text[0] == '"' and text[-1] == '"':
        text = text[1:-1]
    else:
        text = re.sub(r"\s+", " ", text)
    out, i = [], 0
    while i < len(text):
        c = text[i]
        if c == "\\" and i + 1 < len(text):
            n = text[i + 1]
            if n == "n":
                out.append("\n")
            elif n == "t":
                out.append("\t")
            elif n == "u" and re.fullmatch(r"[0-9a-fA-F]{4}", text[i + 2:i + 6] or ""):
                out.append(chr(int(text[i + 2:i + 6], 16)))
                i += 4
            else:
                out.append(n)
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def element_text(el: ET.Element) -> str:
    """Inner text with child markup (xliff:g, b, i) flattened to its text."""
    return "".join(el.itertext())


def parse(path: Path):
    strings, plurals = {}, {}
    if not path.exists():
        return strings, plurals
    for el in ET.parse(path).getroot():
        if el.get("translatable") == "false":
            continue
        name = el.get("name")
        if el.tag == "string":
            strings[name] = unescape(element_text(el))
        elif el.tag == "plurals":
            plurals[name] = {i.get("quantity"): unescape(element_text(i)) for i in el.findall("item")}
    return strings, plurals


def signature(text: str):
    """Placeholders as (argument index or position, conversion), order independent."""
    result, position = [], 0
    for m in PLACEHOLDER.finditer(text):
        if m.group(3) == "%":
            continue
        position += 1
        result.append((int(m.group(1)) if m.group(1) else position, m.group(3)))
    return sorted(result)


def to_swift_format(text: str) -> str:
    def convert(m):
        if m.group(3) == "%":
            return m.group(0)
        conv = {"s": "@", "d": "lld", "f": "f"}[m.group(3)]
        index = f"{m.group(1)}$" if m.group(1) else ""
        return f"%{index}{m.group(2)}{conv}"
    return PLACEHOLDER.sub(convert, text)


def swift_literal(text: str) -> str:
    text = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")
    return '"' + text + '"'


def load(res: Path):
    data = {}
    for lang, folder in LANGUAGES:
        strings, plurals = {}, {}
        for f in FILES:
            s, p = parse(res / folder / f"{f}.xml")
            strings.update(s)
            plurals.update(p)
        data[lang] = (strings, plurals)
    return data


def check(data) -> list:
    problems = []
    base_s, base_p = data["ru"]
    for lang, (strings, plurals) in data.items():
        for key, ru in base_s.items():
            value = strings.get(key)
            if value is None:
                problems.append(f"{lang}: missing string {key}")
            elif not value.strip():
                problems.append(f"{lang}: empty string {key}")
            elif signature(value) != signature(ru):
                problems.append(f"{lang}: placeholders of {key} differ from ru: {signature(value)} vs {signature(ru)}")
        for key, forms in base_p.items():
            other = plurals.get(key)
            if other is None:
                problems.append(f"{lang}: missing plurals {key}")
                continue
            if "other" not in other:
                problems.append(f"{lang}: plurals {key} has no 'other'")
            for q, v in other.items():
                if not v.strip():
                    problems.append(f"{lang}: empty plural {key}/{q}")
                elif signature(v) != signature(forms["other"]):
                    problems.append(f"{lang}: placeholders of {key}/{q} differ from ru")
    return problems


def render(data) -> str:
    lines = [
        "// GENERATED by tools/l10n/android_strings.py from the Android BeyGram resources. Do not edit.",
        "// Keys are Android resource names; placeholders are converted for String(format:).",
        "",
        "enum BeyGramAndroidStringsData {",
        "    /// Per language: alternating key, value.",
        "    static let strings: [String: [String]] = [",
    ]
    for lang, _ in LANGUAGES:
        strings, _p = data[lang]
        lines.append(f'        "{lang}": [')
        for key in sorted(data["ru"][0]):
            lines.append(f"            {swift_literal(key)}, {swift_literal(to_swift_format(strings[key]))},")
        lines.append("        ],")
    lines += ["    ]", "", "    /// Per language: alternating key, then `category=template` entries joined by a unit separator (U+001F).", "    static let plurals: [String: [String]] = ["]
    for lang, _ in LANGUAGES:
        _s, plurals = data[lang]
        lines.append(f'        "{lang}": [')
        for key in sorted(data["ru"][1]):
            forms = plurals[key]
            joined = "\x1f".join(f"{q}={to_swift_format(forms[q])}" for q in CATEGORIES if q in forms)
            lines.append(f"            {swift_literal(key)}, {swift_literal(joined).replace(chr(0x1f), chr(92) + 'u{1F}')},")
        lines.append("        ],")
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--android-res", required=True, type=Path)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    data = load(args.android_res)
    problems = check(data)
    for p in problems:
        print(p, file=sys.stderr)
    if problems:
        sys.exit(1)
    if not args.check:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(render(data), encoding="utf-8")
        print(f"wrote {args.out}: {len(data['ru'][0])} strings, {len(data['ru'][1])} plurals, {len(LANGUAGES)} languages")


if __name__ == "__main__":
    main()
