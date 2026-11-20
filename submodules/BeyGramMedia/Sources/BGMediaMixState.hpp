#pragma once

// Pure mapping from the MixSession snapshot to the state BGMixPlayer publishes. No Foundation or
// Apple types here, so the host test (Tests/BGMediaMixStateTests.cpp) builds it with g++ or clang.

#include "bgmedia/mix/MixSession.hpp"
#include "bgmedia/mix/MixTypes.hpp"

#include <cstdint>

namespace beygram::media {

// Mirrors BGMixTransport in PublicHeaders/BeyGramMedia/BGMixPlayer.h.
enum class MixTransport : std::uint8_t { Stopped = 0, Playing, Paused };

// Index (0 = A, 1 = B) of the deck the listener hears as the current track.
[[nodiscard]] inline int masterDeckIndex(const bgmedia::mix::MixSnapshot& engine) noexcept {
    return bgmedia::mix::deckIndex(engine.master);
}

// Playing when any deck plays (a transition has two decks sounding), paused when a loaded deck is
// silent, stopped when no deck holds a track.
[[nodiscard]] inline MixTransport transportOf(const bgmedia::mix::MixSnapshot& engine) noexcept {
    bool hasLoaded = false;
    for (const bgmedia::mix::DeckStatus& deck : engine.decks) {
        if (deck.playing) {
            return MixTransport::Playing;
        }
        hasLoaded = hasLoaded || (deck.loaded && !deck.ended);
    }
    return hasLoaded ? MixTransport::Paused : MixTransport::Stopped;
}

// Track id on the master deck; 0 when that deck is empty.
[[nodiscard]] inline std::uint64_t currentTrackId(const bgmedia::mix::MixSnapshot& engine) noexcept {
    const bgmedia::mix::DeckStatus& master = engine.decks[masterDeckIndex(engine)];
    return master.loaded ? master.trackId : 0;
}

// Track id on the other deck, the one a transition hands over to. 0 when that deck is empty, has
// already finished, or holds the track that is current.
[[nodiscard]] inline std::uint64_t nextTrackId(const bgmedia::mix::MixSnapshot& engine) noexcept {
    const bgmedia::mix::DeckStatus& other =
        engine.decks[bgmedia::mix::deckIndex(bgmedia::mix::otherDeck(engine.master))];
    if (!other.loaded || other.ended || other.trackId == currentTrackId(engine)) {
        return 0;
    }
    return other.trackId;
}

// Position and length of the master deck in seconds; 0 when it is empty.
[[nodiscard]] inline double masterPositionSeconds(const bgmedia::mix::MixSnapshot& engine) noexcept {
    const bgmedia::mix::DeckStatus& master = engine.decks[masterDeckIndex(engine)];
    return master.loaded ? master.positionSeconds : 0.0;
}

[[nodiscard]] inline double masterDurationSeconds(const bgmedia::mix::MixSnapshot& engine) noexcept {
    const bgmedia::mix::DeckStatus& master = engine.decks[masterDeckIndex(engine)];
    return master.loaded ? master.durationSeconds : 0.0;
}

} // namespace beygram::media
