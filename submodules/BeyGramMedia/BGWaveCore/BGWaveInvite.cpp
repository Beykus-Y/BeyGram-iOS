#include "BGWaveInvite.hpp"

#include <chrono>
#include <utility>

namespace beygram::wave {
namespace {

// Base of the Telegram-safe link. The same origin as kInviteHttpsPrefix.
constexpr std::string_view kTelegramSafeBase = "https://beygram.beykus.fun/";

bool hasPrefix(std::string_view text, std::string_view prefix) {
    return text.size() >= prefix.size() && text.substr(0, prefix.size()) == prefix;
}

void setError(std::string* error, const char* reason) {
    if (error != nullptr) {
        *error = reason;
    }
}

}  // namespace

std::int64_t resolveUnixSeconds(std::int64_t nowUnixSeconds) {
    if (nowUnixSeconds > 0) {
        return nowUnixSeconds;
    }
    return std::chrono::duration_cast<std::chrono::seconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

std::string inviteToHttps(std::string_view link) {
    if (link.empty() || link.size() > kInviteMaxLinkChars) {
        return {};
    }
    if (hasPrefix(link, kInviteHttpsPrefix)) {
        return link.size() > kInviteHttpsPrefix.size() ? std::string(link) : std::string();
    }
    if (hasPrefix(link, kInviteUriPrefix) && link.size() > kInviteUriPrefix.size()) {
        std::string https(kInviteHttpsPrefix);
        https.append(link.substr(kInviteUriPrefix.size()));
        return https.size() <= kInviteMaxLinkChars ? https : std::string();
    }
    return {};
}

bool isInviteLink(std::string_view link) {
    return !inviteToHttps(link).empty();
}

bool decodeInvite(std::string_view link,
                  std::int64_t nowUnixSeconds,
                  bgmedia::wave::WaveSignalMessage& outMessage,
                  std::string* error) {
    if (link.empty()) {
        setError(error, "empty");
        return false;
    }
    if (link.size() > kInviteMaxLinkChars) {
        setError(error, "too_long");
        return false;
    }
    if (!isInviteLink(link)) {
        setError(error, "not_an_invite");
        return false;
    }
    bgmedia::wave::WaveSignalMessage message;
    std::string codecError;
    if (!bgmedia::wave::decodeWaveUri(link, message, &codecError)) {
        setError(error, "malformed");
        return false;
    }
    if (!bgmedia::wave::validateWaveSignal(message, resolveUnixSeconds(nowUnixSeconds), &codecError)) {
        setError(error, "invalid_or_expired");
        return false;
    }
    outMessage = std::move(message);
    return true;
}

std::string encodeInvite(const bgmedia::wave::WaveSignalMessage& message, std::string* error) {
    std::string codecError;
    std::string https = bgmedia::wave::encodeWaveHttpsFragmentUri(message, kTelegramSafeBase, &codecError);
    if (https.empty()) {
        setError(error, "encode_failed");
        return {};
    }
    if (https.size() > kInviteMaxLinkChars) {
        setError(error, "too_long");
        return {};
    }
    return https;
}

}  // namespace beygram::wave
