import Foundation
import SwiftSignalKit
import BeyGramMedia

/// Track preparation/playback state mapped from `BGMixTrackState`.
public enum BeyGramMusicTrackStatus: Equatable {
    case pending
    case preparing(Float)
    case ready
    case playing
    case played
    case failed(String?)

    init(track: BGMixTrack) {
        switch track.state {
        case .pending:
            self = .pending
        case .preparing:
            self = .preparing(track.progress)
        case .ready:
            self = .ready
        case .playing:
            self = .playing
        case .played:
            self = .played
        case .failed:
            self = .failed(track.error)
        @unknown default:
            self = .pending
        }
    }
}

/// Immutable track model projected from `BGMixTrack`.
public struct BeyGramMusicTrack: Equatable, Identifiable {
    public let id: UInt64
    public let url: URL
    public let title: String
    public let duration: TimeInterval?
    public let bpm: Int?
    public let status: BeyGramMusicTrackStatus

    public var isPrepared: Bool {
        switch self.status {
        case .ready, .playing, .played:
            return true
        case .pending, .preparing, .failed:
            return false
        }
    }

    init(track: BGMixTrack) {
        self.id = track.identifier
        self.url = track.fileURL
        let rawName = track.name
        let stripped = (rawName as NSString).deletingPathExtension
        self.title = stripped.isEmpty ? rawName : stripped
        self.duration = track.duration > 0 ? track.duration : nil
        self.bpm = track.bpm > 0 ? Int(track.bpm.rounded()) : nil
        self.status = BeyGramMusicTrackStatus(track: track)
    }
}

/// Snapshot of `BGMixPlayer.sharedPlayer()` plus local mix settings.
public struct BeyGramMusicState: Equatable {
    public var queue: [BeyGramMusicTrack]
    public var recentTracks: [BeyGramMusicTrack]
    public var currentTrack: BeyGramMusicTrack?
    public var nextTrack: BeyGramMusicTrack?
    public var position: TimeInterval
    public var duration: TimeInterval
    public var isPlaying: Bool
    public var isPaused: Bool
    public var isTransitionActive: Bool
    public var transitionProgress: Float
    public var isPreparingNext: Bool
    public var lastError: String?
    public var transitionDuration: Double
    public var adaptiveTransitions: Bool
    public var bassSwap: Bool

    public init(
        queue: [BeyGramMusicTrack] = [],
        recentTracks: [BeyGramMusicTrack] = [],
        currentTrack: BeyGramMusicTrack? = nil,
        nextTrack: BeyGramMusicTrack? = nil,
        position: TimeInterval = 0.0,
        duration: TimeInterval = 0.0,
        isPlaying: Bool = false,
        isPaused: Bool = false,
        isTransitionActive: Bool = false,
        transitionProgress: Float = 0.0,
        isPreparingNext: Bool = false,
        lastError: String? = nil,
        transitionDuration: Double = 0.0,
        adaptiveTransitions: Bool = true,
        bassSwap: Bool = true
    ) {
        self.queue = queue
        self.recentTracks = recentTracks
        self.currentTrack = currentTrack
        self.nextTrack = nextTrack
        self.position = position
        self.duration = duration
        self.isPlaying = isPlaying
        self.isPaused = isPaused
        self.isTransitionActive = isTransitionActive
        self.transitionProgress = transitionProgress
        self.isPreparingNext = isPreparingNext
        self.lastError = lastError
        self.transitionDuration = transitionDuration
        self.adaptiveTransitions = adaptiveTransitions
        self.bassSwap = bassSwap
    }
}

/// Thin Swift reactive adapter over `BGMixPlayer.sharedPlayer()` (`BGMixPlayerObserver`).
///
/// There is only one global player instance (`BGMixPlayer.sharedPlayer()`), owned by `BeyGramMedia`.
public final class BeyGramMusicSession: NSObject, BGMixPlayerObserver {
    public static let shared = BeyGramMusicSession()

    private let player: BGMixPlayer
    private let stateValue: Atomic<BeyGramMusicState>
    private let statePromise: ValuePromise<BeyGramMusicState>

    private override init() {
        self.player = BGMixPlayer.sharedPlayer()
        let initial = BeyGramMusicState()
        self.stateValue = Atomic(value: initial)
        self.statePromise = ValuePromise(initial, ignoreRepeated: true)
        super.init()

        self.player.setTransitionDuration(initial.transitionDuration)
        self.player.setAdaptiveTransitions(initial.adaptiveTransitions)
        self.player.setBassSwap(initial.bassSwap)
        self.player.addObserver(self)
    }

    deinit {
        self.player.removeObserver(self)
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

    public func mixPlayer(_ player: BGMixPlayer, didUpdate snapshot: BGMixSnapshot) {
        let mappedQueue = snapshot.queue.map(BeyGramMusicTrack.init(track:))
        let mappedCurrent = snapshot.currentTrack.map(BeyGramMusicTrack.init(track:))
        let mappedNext = snapshot.nextTrack.map(BeyGramMusicTrack.init(track:))

        self.mutate { state in
            state.queue = mappedQueue
            state.currentTrack = mappedCurrent
            state.nextTrack = mappedNext
            state.position = snapshot.position
            state.duration = snapshot.duration
            state.isPlaying = snapshot.transport == .playing
            state.isPaused = snapshot.transport == .paused
            state.isTransitionActive = snapshot.transitionActive
            state.transitionProgress = snapshot.transitionProgress
            state.isPreparingNext = snapshot.preparingNext
            state.lastError = snapshot.lastError
            if let current = mappedCurrent {
                state.recentTracks.removeAll { $0.id == current.id }
                state.recentTracks.insert(current, at: 0)
                if state.recentTracks.count > 20 {
                    state.recentTracks = Array(state.recentTracks.prefix(20))
                }
            }
        }
    }

    public func addTracks(urls: [URL]) {
        DispatchQueue.main.async {
            let mixDir = BGMixPlayer.mixDirectory()
            try? FileManager.default.createDirectory(at: mixDir, withIntermediateDirectories: true)
            for source in urls {
                let scoped = source.startAccessingSecurityScopedResource()
                let target = mixDir.appendingPathComponent("\(UUID().uuidString)-\(source.lastPathComponent)")
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
                _ = self.player.addTrack(at: target)
            }
        }
    }

    public func removeTrack(id: UInt64) {
        DispatchQueue.main.async {
            _ = self.player.removeTrack(withIdentifier: id)
        }
    }

    public func clearQueue() {
        DispatchQueue.main.async {
            self.player.stopAll()
            self.player.clearQueue()
        }
    }

    public func play() {
        DispatchQueue.main.async {
            self.player.play()
        }
    }

    public func pause() {
        DispatchQueue.main.async {
            self.player.pause()
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
            self.player.next()
        }
    }

    @discardableResult
    public func seek(to seconds: TimeInterval) -> Bool {
        return self.player.seek(toPosition: seconds)
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
}
