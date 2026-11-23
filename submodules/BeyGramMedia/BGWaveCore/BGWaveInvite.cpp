#include "BGWaveInvite.hpp"

#include <chrono>
#include <utility>

namespace beygram::wave {
namespace {

// Base of the Telegram-safe link. The same origin as kInviteHttpsPrefix.
constexpr std::string_view kTelegramSafeBase = "https://beygram.beykus.fun/";

int hexValue(char c) {
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }
    if (c >= 'A' && c <= 'F') {
        return c - 'A' + 10;
    }
    return -1;
}

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

std::optional<BGWaveInviteFields> decodeInviteFields(std::string_view link,
                                                     std::int64_t nowUnixSeconds,
                                                     std::string* error) {
    bgmedia::wave::WaveSignalMessage message;
    if (!decodeInvite(link, nowUnixSeconds, message, error)) {
        return std::nullopt;
    }
    BGWaveInviteFields fields;
    fields.type = message.type;
    fields.sidHex = bgmedia::wave::formatSessionIdHex(message.sid);
    fields.issuedAt = message.iat;
    fields.expiresAt = message.exp;
    fields.caps = message.caps;
    fields.nonce = message.nonce;
    fields.candidateCount = message.signal.candidates.size();
    return fields;
}

std::string encodeControlInvite(bgmedia::wave::WaveSignalType type,
                                std::string_view sidHex,
                                std::int64_t nowUnixSeconds,
                                std::uint64_t nonce) {
    if (type != bgmedia::wave::WaveSignalType::Cancel && type != bgmedia::wave::WaveSignalType::End) {
        return {};
    }
    bgmedia::wave::WaveSignalMessage message;
    message.type = type;
    if (!parseSessionIdHex(sidHex, message.sid)) {
        return {};
    }
    message.iat = resolveUnixSeconds(nowUnixSeconds);
    message.exp = message.iat + kInviteControlTtlSeconds;
    // Control messages carry no capabilities, as the canonical BG-Media fixtures for Cancel and End do.
    message.caps = static_cast<std::uint32_t>(bgmedia::wave::kWaveCapNone);
    message.nonce = nonce;
    return encodeInvite(message);
}

bool parseSessionIdHex(std::string_view hex, std::array<std::uint8_t, 16>& outSid) {
    if (hex.size() != outSid.size() * 2) {
        return false;
    }
    std::array<std::uint8_t, 16> parsed{};
    for (std::size_t i = 0; i < parsed.size(); ++i) {
        const int high = hexValue(hex[2 * i]);
        const int low = hexValue(hex[2 * i + 1]);
        if (high < 0 || low < 0) {
            return false;
        }
        parsed[i] = static_cast<std::uint8_t>((high << 4) | low);
    }
    outSid = parsed;
    return true;
}

}  // namespace beygram::wave
