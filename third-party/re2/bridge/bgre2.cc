#include "bgre2.h"

#include <cstddef>
#include <string>

#include "re2/re2.h"
#include "re2/stringpiece.h"

namespace {

// The compiled expression behind the opaque C handle.
struct BgRegex {
  BgRegex(const std::string &pattern, bool case_sensitive) : re(pattern, MakeOptions(case_sensitive)) {}

  static RE2::Options MakeOptions(bool case_sensitive) {
    RE2::Options options;
    options.set_case_sensitive(case_sensitive);
    // Trigger rules never need captures, and a rejected pattern must not write to the log.
    options.set_never_capture(true);
    options.set_log_errors(false);
    return options;
  }

  RE2 re;
};

const char kEmptyText[] = "";

}  // namespace

extern "C" {

void *bgre2_compile(const char *pattern, size_t pattern_length, int case_sensitive) {
  if (pattern == nullptr) {
    return nullptr;
  }
  try {
    BgRegex *regex = new BgRegex(std::string(pattern, pattern_length), case_sensitive != 0);
    if (!regex->re.ok()) {
      delete regex;
      return nullptr;
    }
    return regex;
  } catch (...) {
    return nullptr;
  }
}

int bgre2_partial_match(const void *regex, const char *text, size_t text_length) {
  if (regex == nullptr) {
    return 0;
  }
  const BgRegex *compiled = static_cast<const BgRegex *>(regex);
  const char *data = text != nullptr ? text : kEmptyText;
  if (text == nullptr && text_length != 0) {
    return 0;
  }
  try {
    return RE2::PartialMatch(re2::StringPiece(data, text_length), compiled->re) ? 1 : 0;
  } catch (...) {
    return 0;
  }
}

void bgre2_free(void *regex) {
  delete static_cast<BgRegex *>(regex);
}

}  // extern "C"
