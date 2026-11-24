#!/usr/bin/env python3
"""Compare Android BeyGram string resources with the iOS BeyGramL10n tables (#51).

Usage: l10n_android_report.py <BeyGram android repo> [<BeyGram-iOS repo>]
Prints: languages found in Android, per-language key counts, placeholder
mismatches between languages, and which iOS strings have an Android string
with the same ru or en text (a starting point for the key mapping).
"""
import re, sys, glob, os
import xml.etree.ElementTree as ET

PH = re.compile(r"%(?:\d+\$)?[sdf@]|%%|%lld")

def load(res, folder):
    out = {}
    for f in sorted(glob.glob(os.path.join(res, folder, "*.xml"))):
        try:
            root = ET.parse(f).getroot()
        except ET.ParseError:
            continue
        for e in root.findall("string"):
            if e.get("translatable") == "false":
                continue
            out[e.get("name")] = "".join(e.itertext())
    return out

def ph(s):
    return sorted(PH.findall(s))

def ios_pairs(root, lang):
    text = open(os.path.join(root, "submodules/BeyGramKit/Sources/BeyGramLocalizationTables.swift"), encoding="utf-8").read()
    name = "englishStrings" if lang == "en" else "russianStrings"
    i = text.index("let " + name)
    body = text[i:text.index("\n    ]", i)]
    return {k: v for k, v in re.findall(r"\.(\w+):\s*\"((?:[^\"\\]|\\.)*)\"", body)}

def main():
    android = sys.argv[1]
    ios = sys.argv[2] if len(sys.argv) > 2 else "."
    res = os.path.join(android, "app/src/main/res")
    langs = {"ru": "values", "en": "values-en", "de": "values-de", "es": "values-es", "fr": "values-fr"}
    tables = {l: load(res, d) for l, d in langs.items()}
    base = tables["ru"]
    print("Android keys per language:", {l: len(t) for l, t in tables.items()})
    for l in ("en", "de", "es", "fr"):
        miss = [k for k in base if k not in tables[l]]
        extra = [k for k in tables[l] if k not in base]
        bad = [k for k in base if k in tables[l] and ph(base[k]) != ph(tables[l][k])]
        print(f"{l}: missing {len(miss)}, not in ru {len(extra)}, placeholder mismatch {len(bad)}")
        for k in bad[:10]:
            print("   ", k, ph(base[k]), ph(tables[l][k]))
    for l in ("ru", "en"):
        rev = {}
        for k, v in tables[l].items():
            rev.setdefault(v.strip(), []).append(k)
        pairs = ios_pairs(ios, l)
        hit = {ik: rev[v.strip()] for ik, v in pairs.items() if v.strip() in rev}
        print(f"iOS {l}: {len(pairs)} strings, {len(hit)} equal an Android string")
        for ik, ak in list(hit.items())[:15]:
            print("   ", ik, "->", ak[0])

if __name__ == "__main__":
    main()
