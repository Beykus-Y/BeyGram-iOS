# Localization parity with Android (#51), step 1: measurements

Run `python3 tools/l10n_android_report.py <BeyGram repo> .` (read-only, needs only Python 3).

Measured 2026-11-24 against Android `DEV`:

| | Android | iOS (`BeyGramLocalizationTables`) |
|---|---|---|
| Languages | ru (default), en, de, es, fr | ru, en |
| Strings | 4727 per language (de, es, fr: 4723) | 284 (ru and en) |
| Placeholder mismatches between languages | 0 | not checked |
| Strings whose text equals an Android string | | 78 (ru), 76 (en) |

Findings:
- `docs/i18n-qa.md` in Android is out of date: de, es and fr exist and are 4 keys short of ru and en.
- iOS keys are dotted names (`common.back`), Android keys are resource names (`common_back`). Step 2 of #51 asks for the Android names as iOS identifiers, so a mapping or a rename is needed.
- Equal text is not equal meaning (`commonDelete` matches `chat_send_failure_discard` in ru). The script output is a starting point for the mapping, not the mapping.

Not done: the mapping table, the XML to Swift converter, de, es and fr tables, the language picker. Decision needed first: keep the Swift tables (generated from Android XML) or move to `.strings` files.
