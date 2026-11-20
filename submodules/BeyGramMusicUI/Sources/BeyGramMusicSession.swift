import Foundation
import AVFoundation
import SwiftSignalKit
import BeyGramMedia

/// Represents a track in the BeyGram Music / BG Mix queue.
public struct BeyGramMusicTrack: Equatable, Identifiable {
    public let id: UInt64
    public let url: URL
    public let title: String
    public let artist: String?
    public let duration: TimeInterval?
    public let bpm: Int?
    public let isPrepared: Bool

    public init(
        id: UInt64,
        url: URL,
        title: String,
        artist: String? = nil,
        duration: TimeInterval? = nil,
        bpm: Int? = nil,
        isPrepared: Bool = true
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.duration = duration
        self.bpm = bpm
        self.isPrepared = isPrepared
    }
}

/// Snapshot of the shared `BeyGramMusicSession` state.
public struct BeyGramMusicState: Equatable {
    public var queue: [BeyGramMusicTrack]
    public var recentTracks: [BeyGramMusicTrack]
    public var currentIndex: Int
    public var isPlaying: Bool
    public var isTransitionActive: Bool
    public var transitionDuration: Double
    public var adaptiveTransitions: Bool
    public var bassSwap: Bool

    public var currentTrack: BeyGramMusicTrack? {
        guard self.currentIndex >= 0 && self.currentIndex < self.queue.count else {
            return nil
        }
        return self.queue[self.currentIndex]
    }

    public var nextTrack: BeyGramMusicTrack? {
        let nextIndex = self.currentIndex + 1
        guard nextIndex >= 0 && nextIndex < self.queue.count else {
            return nil
        }
        return self.queue[nextIndex]
    }

    public init(
        queue: [BeyGramMusicTrack] = [],
        recentTracks: [BeyGramMusicTrack] = [],
        currentIndex: Int = 0,
        isPlaying: Bool = false,
        isTransitionActive: Bool = false,
        transitionDuration: Double = 0.0,
        adaptiveTransitions: Bool = true,
        bassSwap: Bool = true
    ) {
        self.queue = queue
        self.recentTracks = recentTracks
        self.currentIndex = currentIndex
        self.isPlaying = isPlaying
        self.isTransitionActive = isTransitionActive
        self.transitionDuration = transitionDuration
        self.adaptiveTransitions = adaptiveTransitions
        self.bassSwap = bassSwap
    }
}

/// Shared audio session owning `BGMixPlayer` independently of any view controller lifecycle.
public final class BeyGramMusicSession {
    public static let shared = BeyGramMusicSession()

    private let player: BGMixPlayer
    private let mixDirectory: URL
    private let stateValue: Atomic<BeyGramMusicState>
    private let statePromise: ValuePromise<BeyGramMusicState>
    private var transitionTimer: Timer?

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.mixDirectory = docs.appendingPathComponent("bgmix", isDirectory: true)
        let cacheDir = self.mixDirectory.appendingPathComponent("cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        self.player = BGMixPlayer(cacheDirectory: cacheDir.path)
        let initial = BeyGramMusicState()
        self.stateValue = Atomic(value: initial)
        self.statePromise = ValuePromise(initial, ignoreRepeated: true)

        self.player.setTransitionDuration(initial.transitionDuration)
        self.player.setAdaptiveTransitions(initial.adaptiveTransitions)
        self.player.setBassSwap(initial.bassSwap)
    }

    public var stateSignal: Signal<BeyGramMusicState, NoError> {
        return self.statePromise.get()
    }

    public var currentState: BeyGramMusicState {
        return self.stateValue.with { $0 }
    }

    private func mutate(_ update: (inout BeyGramMusicState) -> Void) {
        let next = self.stateValue.modify { current in
            var copy = current
            update(&copy)
            return copy
        }
        self.statePromise.set(next)
    }

    public func addTracks(urls: [URL]) {
        DispatchQueue.main.async {
            try? FileManager.default.createDirectory(at: self.mixDirectory, withIntermediateDirectories: true)
            var added: [BeyGramMusicTrack] = []
            for source in urls {
                let scoped = source.startAccessingSecurityScopedResource()
                let target = self.mixDirectory.appendingPathComponent("\(UUID().uuidString)-\(source.lastPathComponent)")
                let copied: Bool
                do {
                    try FileManager.default.copyItem(at: source, to: target)
                    copied = true
                } catch {
                    copied = false
                }
                if scoped {
                    source.stopAccessingSecurityScopedResource()
                }
                guard copied else { continue }

                let identifier = self.player.addTrack(at: target)
                guard identifier != 0 else { continue }

                let asset = AVURLAsset(url: target)
                let durationSeconds = CMTimeGetSeconds(asset.duration)
                let duration = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : nil
                let fallbackTitle = source.deletingPathExtension().lastPathComponent
                let track = BeyGramMusicTrack(
                    id: identifier,
                    url: target,
                    title: fallbackTitle.isEmpty ? source.lastPathComponent : fallbackTitle,
                    artist: nil,
                    duration: duration,
                    bpm: nil,
                    isPrepared: true
                )
                added.append(track)
            }

            if !added.isEmpty {
                self.mutate { state in
                    state.queue.append(contentsOf: added)
                    for track in added.reversed() {
                        state.recentTracks.removeAll { $0.id == track.id }
                        state.recentTracks.insert(track, at: 0)
                    }
                    if state.recentTracks.count > 20 {
                        state.recentTracks = Array(state.recentTracks.prefix(20))
                    }
                }
            }
        }
    }

    public func removeTrack(id: UInt64) {
        DispatchQueue.main.async {
            self.player.removeTrack(withIdentifier: id)
            self.mutate { state in
                state.queue.removeAll { $0.id == id }
                if state.queue.isEmpty {
                    state.currentIndex = 0
                    state.isPlaying = false
                    state.isTransitionActive = false
                } else if state.currentIndex >= state.queue.count {
                    state.currentIndex = max(0, state.queue.count - 1)
                }
            }
        }
    }

    public func moveTrack(from sourceIndex: Int, to destinationIndex: Int) {
        DispatchQueue.main.async {
            self.mutate { state in
                guard sourceIndex >= 0, sourceIndex < state.queue.count,
                      destinationIndex >= 0, destinationIndex < state.queue.count,
                      sourceIndex != destinationIndex else {
                    return
                }
                let item = state.queue.remove(at: sourceIndex)
                state.queue.insert(item, at: destinationIndex)
                if state.currentIndex == sourceIndex {
                    state.currentIndex = destinationIndex
                }
            }
        }
    }

    public func clearQueue() {
        DispatchQueue.main.async {
            self.player.stopAll()
            self.player.clearQueue()
            self.stopTransitionPolling()
            self.mutate { state in
                state.queue.removeAll()
                state.currentIndex = 0
                state.isPlaying = false
                state.isTransitionActive = false
            }
        }
    }

    public func play() {
        DispatchQueue.main.async {
            guard !self.currentState.queue.isEmpty else { return }
            self.player.play()
            self.mutate { state in
                state.isPlaying = true
                state.isTransitionActive = self.player.isTransitionActive()
            }
            self.startTransitionPolling()
        }
    }

    public func pause() {
        DispatchQueue.main.async {
            self.player.pause()
            self.stopTransitionPolling()
            self.mutate { state in
                state.isPlaying = false
                state.isTransitionActive = false
            }
        }
    }

    public func togglePlayPause() {
        if self.currentState.isPlaying {
            self.pause()
        } else {
            self.play()
        }
    }

    public func next() {
        DispatchQueue.main.async {
            guard !self.currentState.queue.isEmpty else { return }
            self.player.next()
            self.mutate { state in
                if state.currentIndex + 1 < state.queue.count {
                    state.currentIndex += 1
                }
                state.isTransitionActive = self.player.isTransitionActive()
            }
        }
    }

    public func setTransitionDuration(_ seconds: Double) {
        DispatchQueue.main.async {
            self.player.setTransitionDuration(seconds)
            self.mutate { state in
                state.transitionDuration = seconds
            }
        }
    }

    public func setAdaptiveTransitions(_ enabled: Bool) {
        DispatchQueue.main.async {
            self.player.setAdaptiveTransitions(enabled)
            self.mutate { state in
                state.adaptiveTransitions = enabled
            }
        }
    }

    public func setBassSwap(_ enabled: Bool) {
        DispatchQueue.main.async {
            self.player.setBassSwap(enabled)
            self.mutate { state in
                state.bassSwap = enabled
            }
        }
    }

    private func startTransitionPolling() {
        self.stopTransitionPolling()
        self.transitionTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            let active = self.player.isTransitionActive()
            if self.currentState.isTransitionActive != active {
                self.mutate { state in
                    state.isTransitionActive = active
                }
            }
        }
    }

    private func stopTransitionPolling() {
        self.transitionTimer?.invalidate()
        self.transitionTimer = nil
    }
}
