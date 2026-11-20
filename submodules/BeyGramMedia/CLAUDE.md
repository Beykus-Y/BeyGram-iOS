# BeyGramMedia

BG Mix (AutoMix) and BG Beat for iOS. Notes for work in this directory:

- `BGMediaCore/` is a git submodule of `Beykus-Y/BG-Media` (pure C++20 core). Do not edit it here; change the core in BG-Media and bump the pin. The pin follows BG-Media `dev` (the commit the Android app builds), not `main`; bump it together with the source list in `BUILD`.
- Initialise it before building: `git submodule update --init submodules/BeyGramMedia/BGMediaCore`.
- `Sources/BGMediaMixPreparation.*` is the platform-neutral track pipeline (same steps as BG-Media's desktop `prepareMixTrack` on dev). Decoding is injected: the decoder must refuse before allocating past `maxDecodedBytes` and call the checkpoint between chunks. Limits and the reserve-and-interleave helper live in `Sources/BGMediaPcmLimits.hpp` (host test: `Tests/BGMediaPcmLimitsTests.cpp`).
- `Sources/BGMixPlayer.mm` decodes with AVAudioFile and plays through AVAudioSourceNode on AVAudioEngine. `MixSession::update()` runs from a CADisplayLink on the main thread. The render block must never capture self or allocate.
- The pinned core and the platform-neutral pipeline were compiled and run on Linux (g++ 13, `-std=c++20`). The Objective-C++ files and the Bazel target have not been built: they need macOS with Bazel.
- `Sources/BGMixViewController.mm` is a minimal BG Mix screen (queue, play, next, clear, in a bottom toolbar). `BGMixFeatureEnabled()` reads `beygram.feature.musicLibrary` from UserDefaults (the key BeyGramKit writes; off by default). The entry is the BG Music settings page (`submodules/BeyGramMusicUI`), shown in the Settings advanced list and pushed through `BeyGramHostedViewController`.
- `Sources/BGWaveViewController.mm` is the BG Wave invite screen. It only checks pasted `bg://wave/v1/` links (shape and length). It does not join sessions: host audio capture and the WebRTC stack are not built for iOS (issue #50). Gated by `beygram.feature.bgMedia`.
