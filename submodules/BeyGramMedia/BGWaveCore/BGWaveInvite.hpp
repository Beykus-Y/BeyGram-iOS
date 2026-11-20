// BG Wave invite links for iOS. They are the two wrappers that Android uses (BgWaveLink.kt) around the BG-Media
// v1 payload. Only the BG-Media codec (bgmedia::wave::WaveSignaling) produces or reads the payload bytes.
#pragma once

#include "bgmedia/wave/WaveSignaling.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace beygram::wave {

// Internal app form and Telegram-safe https form, as in BgWaveLink.kt.
inline constexpr std::string_view kInviteUriPrefix = "bg://wave/v1/";
inline constexpr std::string_view kInviteHttpsPrefix = "https://beygram.beykus.fun/#bgwave-v1.";

// Longest accepted invite in characters (BgWaveLink.MAX_LINK_CHARS). Longer text is refused before decoding.
inline constexpr std::size_t kInviteMaxLinkChars = bgmedia::wave::kWaveMaxUriLength;

// Lifetime of a Cancel or End. The core sets the same lifetime on its own End (exp = iat + 60).
inline constexpr std::int64_t kInviteControlTtlSeconds = 60;

// True when the text has one of the two invite shapes. The payload is not decoded here.
[[nodiscard]] bool isInviteLink(std::string_view link);

// The Telegram-safe https form of an invite. An https link is returned unchanged. A bg:// link keeps its payload and
// gets the https prefix. Returns an empty string for anything else, or when the result would be too long.
[[nodiscard]] std::string inviteToHttps(std::string_view link);

// Decodes and validates an invite in either form. A non-positive nowUnixSeconds means the wall clock, so passing 0
// cannot skip the expiry and clock-skew checks. On failure `error` (optional) gets a short fixed reason.
[[nodiscard]] bool decodeInvite(std::string_view link,
                                std::int64_t nowUnixSeconds,
                                bgmedia::wave::WaveSignalMessage& outMessage,
                                std::string* error = nullptr);

// The Telegram-safe https invite for a message. Returns an empty string and sets `error` on failure.
[[nodiscard]] std::string encodeInvite(const bgmedia::wave::WaveSignalMessage& message,
                                       std::string* error = nullptr);

// The value itself when positive, otherwise the current Unix time in seconds.
[[nodiscard]] std::int64_t resolveUnixSeconds(std::int64_t nowUnixSeconds);

// Parses 32 hex digits (either case) into a 128-bit session ID. False for any other length or character.
[[nodiscard]] bool parseSessionIdHex(std::string_view hex, std::array<std::uint8_t, 16>& outSid);

// The fields of a decoded invite that the session layer acts on. The link text itself stays inside this layer.
struct BGWaveInviteFields {
    bgmedia::wave::WaveSignalType type = bgmedia::wave::WaveSignalType::Offer;
    std::string sidHex;
    std::int64_t issuedAt = 0;
    std::int64_t expiresAt = 0;
    std::uint32_t caps = 0;
    std::uint64_t nonce = 0;
    std::size_t candidateCount = 0;
};

// decodeInvite plus the fields the session layer needs, with the same checks. Empty for an invalid, expired or
// oversized link; `error` (optional) gets the same fixed reason as decodeInvite.
[[nodiscard]] std::optional<BGWaveInviteFields> decodeInviteFields(std::string_view link,
                                                                   std::int64_t nowUnixSeconds,
                                                                   std::string* error = nullptr);

// A Cancel or End (no ICE or DTLS signal, no capabilities) as a Telegram-safe https invite, issued at nowUnixSeconds (non-positive: the
// wall clock) and valid for kInviteControlTtlSeconds. Returns an empty string for any other type, or when sidHex is not
// 32 hex digits.
[[nodiscard]] std::string encodeControlInvite(bgmedia::wave::WaveSignalType type,
                                              std::string_view sidHex,
                                              std::int64_t nowUnixSeconds,
                                              std::uint64_t nonce);

}  // namespace beygram::wave
