# BeyGramMedia

BG Mix (AutoMix) and BG Beat for iOS. Notes for work in this directory:

- `BGMediaCore/` is a git submodule of `Beykus-Y/BG-Media` (pure C++20 core). Do not edit it here; change the core in BG-Media and bump the pin.
- Initialise it before building: `git submodule update --init submodules/BeyGramMedia/BGMediaCore`.
- `Sources/BGMediaMixPreparation.*` is the platform-neutral track pipeline (same steps as BG-Media's desktop `prepareMixTrack`). Decoding is injected.
- `Sources/BGMixPlayer.mm` decodes with AVAudioFile and plays through AVAudioSourceNode on AVAudioEngine. `MixSession::update()` runs from a CADisplayLink on the main thread. The render block must never capture self or allocate.
- The core's C++ is verified to compile and link on Linux (g++ 13, `-std=c++20`). The Objective-C++ files and the Bazel target have not been built: they need macOS with Bazel.
