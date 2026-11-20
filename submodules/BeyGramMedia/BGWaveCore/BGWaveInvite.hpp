// BG Wave invite links for iOS. They are the two wrappers that Android uses (BgWaveLink.kt) around the BG-Media
// v1 payload. Only the BG-Media codec (bgmedia::wave::WaveSignaling) produces or reads the payload bytes.
#pragma once

#include "bgmedia/wave/WaveSignaling.hpp"

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace beygram::wave {

// Internal app form and Telegram-safe https form, as in BgWaveLink.kt.
inline constexpr std::string_view kInviteUriPrefix = "bg://wave/v1/";
inline constexpr std::string_view kInviteHttpsPrefix = "https://beygram.beykus.fun/#bgwave-v1.";

// Longest accepted invite in characters (BgWaveLink.MAX_LINK_CHARS). Longer text is refused before decoding.
inline constexpr std::size_t kInviteMaxLinkChars = bgmedia::wave::kWaveMaxUriLength;

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

}  // namespace beygram::wave
