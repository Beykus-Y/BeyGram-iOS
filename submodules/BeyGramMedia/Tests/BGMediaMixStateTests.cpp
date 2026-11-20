// Host test for Sources/BGMediaMixState.hpp. Plain CHECK + main(), like the other C++ units in this repo.

#include "../Sources/BGMediaMixState.hpp"

#include <cstdio>

namespace {

int failures = 0;

#define CHECK_TRUE(cond)                                                     \
    do {                                                                     \
        if (!(cond)) {                                                       \
            std::fprintf(stderr, "%s:%d: CHECK_TRUE(%s) failed\n", __FILE__, \
                         __LINE__, #cond);                                   \
            ++failures;                                                      \
        }                                                                    \
    } while (0)

using bgmedia::mix::DeckId;
using bgmedia::mix::DeckStatus;
using bgmedia::mix::MixSnapshot;
using beygram::media::MixTransport;

// A deck holding `trackId`. A zero id leaves the deck empty.
DeckStatus deck(std::uint64_t trackId, double position, double duration, bool playing) {
    DeckStatus status;
    status.loaded = trackId != 0;
    status.trackId = trackId;
    status.positionSeconds = position;
    status.durationSeconds = duration;
    status.playing = playing;
    return status;
}

void testEmptySessionIsStopped() {
    MixSnapshot engine;
    CHECK_TRUE(beygram::media::transportOf(engine) == MixTransport::Stopped);
    CHECK_TRUE(beygram::media::currentTrackId(engine) == 0);
    CHECK_TRUE(beygram::media::nextTrackId(engine) == 0);
    CHECK_TRUE(beygram::media::masterPositionSeconds(engine) == 0.0);
    CHECK_TRUE(beygram::media::masterDurationSeconds(engine) == 0.0);
}

void testLoadedButSilentIsPaused() {
    MixSnapshot engine;
    engine.master = DeckId::A;
    engine.decks[0] = deck(7, 12.5, 200.0, false);
    CHECK_TRUE(beygram::media::transportOf(engine) == MixTransport::Paused);
    CHECK_TRUE(beygram::media::currentTrackId(engine) == 7);
    CHECK_TRUE(beygram::media::masterPositionSeconds(engine) == 12.5);
    CHECK_TRUE(beygram::media::masterDurationSeconds(engine) == 200.0);
}

void testMasterPlayingIsPlaying() {
    MixSnapshot engine;
    engine.master = DeckId::A;
    engine.decks[0] = deck(7, 1.0, 200.0, true);
    CHECK_TRUE(beygram::media::transportOf(engine) == MixTransport::Playing);
}

void testOtherDeckSoundingDuringTransitionIsPlaying() {
    MixSnapshot engine;
    engine.master = DeckId::A;
    engine.decks[0] = deck(7, 190.0, 200.0, false);
    engine.decks[1] = deck(9, 0.0, 180.0, true);
    CHECK_TRUE(beygram::media::transportOf(engine) == MixTransport::Playing);
    CHECK_TRUE(beygram::media::currentTrackId(engine) == 7);
    CHECK_TRUE(beygram::media::nextTrackId(engine) == 9);
}

void testNextIsTheLoadedOtherDeck() {
    MixSnapshot engine;
    engine.master = DeckId::B;
    engine.decks[1] = deck(3, 5.0, 100.0, true);
    CHECK_TRUE(beygram::media::currentTrackId(engine) == 3);
    // Deck A is the other deck and it is empty.
    CHECK_TRUE(beygram::media::nextTrackId(engine) == 0);
    engine.decks[0] = deck(4, 0.0, 100.0, false);
    CHECK_TRUE(beygram::media::nextTrackId(engine) == 4);
}

void testFinishedOtherDeckIsNotNext() {
    MixSnapshot engine;
    engine.master = DeckId::A;
    engine.decks[0] = deck(1, 99.0, 100.0, true);
    engine.decks[1] = deck(2, 0.0, 100.0, false);
    engine.decks[1].ended = true;
    CHECK_TRUE(beygram::media::nextTrackId(engine) == 0);
    CHECK_TRUE(beygram::media::transportOf(engine) == MixTransport::Playing);
}

void testHandoverMovesCurrentToTheOtherDeck() {
    MixSnapshot engine;
    engine.master = DeckId::A;
    engine.decks[0] = deck(1, 10.0, 100.0, true);
    engine.decks[1] = deck(2, 0.0, 100.0, true);
    // The transition completed: deck B is now the master.
    engine.master = DeckId::B;
    CHECK_TRUE(beygram::media::currentTrackId(engine) == 2);
    CHECK_TRUE(beygram::media::masterPositionSeconds(engine) == 0.0);
    CHECK_TRUE(beygram::media::nextTrackId(engine) == 1);
}

void testNextIsNeverTheCurrentTrack() {
    MixSnapshot engine;
    engine.master = DeckId::A;
    engine.decks[0] = deck(5, 1.0, 100.0, true);
    engine.decks[1] = deck(5, 0.0, 100.0, false);
    CHECK_TRUE(beygram::media::nextTrackId(engine) == 0);
}

} // namespace

int main() {
    testEmptySessionIsStopped();
    testLoadedButSilentIsPaused();
    testMasterPlayingIsPlaying();
    testOtherDeckSoundingDuringTransitionIsPlaying();
    testNextIsTheLoadedOtherDeck();
    testFinishedOtherDeckIsNotNext();
    testHandoverMovesCurrentToTheOtherDeck();
    testNextIsNeverTheCurrentTrack();
    if (failures != 0) {
        std::fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    std::printf("BGMediaMixStateTests: all checks passed\n");
    return 0;
}
