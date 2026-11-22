// C interface to google/re2 for the BeyGram trigger words.
//
// This header is the whole interface Swift sees: no C++ types cross it. A pattern is compiled once, when a
// trigger rule is created or changed, and the handle is reused for every message. RE2 matches in time linear in
// the text, so a pattern cannot stall the app the way a backtracking engine can.

#ifndef BEYGRAM_RE2_BRIDGE_H
#define BEYGRAM_RE2_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Compiles `pattern`, which is UTF-8 and `pattern_length` bytes long (it need not be NUL-terminated).
// `case_sensitive` is nonzero for exact case; zero folds case with Unicode rules, as RE2's (?i) does.
// Returns an opaque handle, or NULL when RE2 rejects the pattern. Release it with bgre2_free.
void *bgre2_compile(const char *pattern, size_t pattern_length, int case_sensitive);

// Returns 1 when the pattern matches somewhere in `text` (UTF-8, `text_length` bytes), 0 otherwise. The match
// is unanchored, like java.util.regex Matcher.find, which the Android client uses.
int bgre2_partial_match(const void *regex, const char *text, size_t text_length);

// Releases a handle returned by bgre2_compile. NULL is ignored.
void bgre2_free(void *regex);

#ifdef __cplusplus
}
#endif

#endif  // BEYGRAM_RE2_BRIDGE_H
