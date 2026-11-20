# BeyGramMedia

BG Mix (AutoMix) and BG Beat for iOS. Notes for work in this directory:

- `BGMediaCore/` is a git submodule of `Beykus-Y/BG-Media` (pure C++20 core). Do not edit it here; change the core in BG-Media and bump the pin.
- Initialise it before building: `git submodule update --init submodules/BeyGramMedia/BGMediaCore`.
- `Sources/BGMediaMixPreparation.*` is the platform-neutral track pipeline (same steps as BG-Media's desktop `prepareMixTrack`). Decoding is injected.
- `Sources/BGMixPlayer.mm` decodes with AVAudioFile and plays through AVAudioSourceNode on AVAudioEngine. `MixSession::update()` runs from a CADisplayLink on the main thread. The render block must never capture self or allocate.
- The core's C++ is verified to compile and link on Linux (g++ 13, `-std=c++20`). The Objective-C++ files and the Bazel target have not been built: they need macOS with Bazel.
- `Sources/BGMixViewController.mm` is a minimal BG Mix screen (queue, play, next, clear, in a bottom toolbar). `BGMixFeatureEnabled()` reads `beygram.feature.musicLibrary` from UserDefaults (the key BeyGramKit writes; off by default). The entry is the BG Music settings page (`submodules/BeyGramMusicUI`), shown in the Settings advanced list and pushed through `BeyGramHostedViewController`.
- `Sources/BGWaveViewController.mm` is the BG Wave invite screen. It only checks pasted `bg://wave/v1/` links (shape and length). It does not join sessions: host audio capture and the WebRTC stack are not built for iOS (issue #50). Gated by `beygram.feature.bgMedia`.
- `BGWaveCore/` is the transport-independent BG Wave session layer, in portable C++20 with no ObjC or UIKit. `BGWaveInvite` decodes and encodes invites in both forms (`bg://wave/v1/` and the https wrapper, as Android's `BgWaveLink.kt`), and refuses a link over 4096 characters before decoding. A non-positive time means the wall clock. `BGWaveSession` runs a Host or Listener over `bgmedia::wave::WaveAudioPipeline` with an injected codec and transport. Production will inject Opus and a P2P transport in later stages; tests use `Pcm16WaveCodec` and `SimulatedWaveTransport`. It needs the BG-Media core at the dev pin (`src/wave/*`), the same commit as Android. Host test: `./build-input/bazel-9.2.0-darwin-arm64 test //submodules/BeyGramMedia/BGWaveCore:BGWaveCoreTests --test_output=all`. Stages and what is verified: `docs/bg-wave-ios.md`.
