# BeyGram strings shared with Android (#51)

One source of strings: the Android resources of `Beykus-Y/BeyGram` (`app/src/main/res/values*`). iOS tables are
generated from them, never edited by hand.

- Generator and check: `tools/l10n/android_strings.py`. `--check` verifies every key in every language (ru from
  `values/`, en, de, es, fr), no empty values, and that placeholders match the Russian string. It exits 1 on a problem.
- Output: `submodules/BeyGramKit/Sources/Generated/BeyGramAndroidStrings.swift` (keys are Android resource names;
  `%1$s` becomes `%1$@`, `%1$d` becomes `%1$lld`). Plurals use CLDR categories.
- Lookup: `BeyGramAndroidStrings.shared.string("key", languageCode:, args...)` and `.quantityString(...)`. An unsupported
  language falls back to Russian, as on Android. The language is the one chosen in Telegram's native language screen: `BeyGramL10n.setLanguageCode` (called by `PresentationData`) forwards it, so there is no separate BeyGram setting; the switch applies at the next lookup.
- Tests: `BeyGramKitTests` (`BeyGramAndroidStringsTests`) repeat the coverage and placeholder checks on the generated tables.
- Which files are taken: the `FILES` list in the script. Add a file when its screen lands on iOS, then regenerate:
  `python3 tools/l10n/android_strings.py --android-res <BeyGram>/app/src/main/res`.
- Server-sent text (names, messages, URLs, file names, diagnostics) is never looked up here.

Hardcoded `isRu ? "..." : "..."` switches in BeyGram modules are counted by `tools/l10n/hardcoded_strings_check.py`
against `hardcoded_strings_baseline.txt` (a ratchet: it may only go down). Migrated so far: the sleep timer, the equalizer and the
Now Playing tab titles; the rest (Yandex, Wave, settings, queue, mix) moves screen by screen as Android keys are matched.
Not done: CI wiring of the two scripts, the manual screen matrix. `CFBundleLocalizations` is not needed: the language is Telegram's.
The older `BeyGramL10n` (en/ru) stays until its keys are moved.
