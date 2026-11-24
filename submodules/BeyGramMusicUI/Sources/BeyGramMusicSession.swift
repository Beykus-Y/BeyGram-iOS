import Foundation
import SwiftSignalKit
import BeyGramKit
import BeyGramMedia
import BeyGramYandexMusic
import BGWaveSessionController

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
    public let artist: String?
    public let coverURL: URL?
    public let yandexTrackId: String?
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
        let meta = BeyGramTrackMetadataStore.shared.metadata(for: track.fileURL, fallbackName: track.name)
        self.title = meta.title
        self.artist = meta.artist
        self.coverURL = meta.coverURL
        self.yandexTrackId = meta.yandexTrackId
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
public final class BeyGramMusicSession: NSObject, BGMixPlayerObserver, BGYandexWavePlayerAdapter {
    public static let shared = BeyGramMusicSession()

    private let player: BGMixPlayer
    public let waveSessionController = BGWaveSessionController()
    private let stateValue: Atomic<BeyGramMusicState>
    private let statePromise: ValuePromise<BeyGramMusicState>
    private let waveStateValue: Atomic<BGYandexWaveState>
    private let waveStatePromise: ValuePromise<BGYandexWaveState>
    private var waveCoordinator: BGYandexWavePlaybackCoordinator!
    private var nowPlayingCenter: BeyGramNowPlayingCenter!
    private var metadataObserver: NSObjectProtocol?
    private var externalAudioObserver: NSObjectProtocol?
    private let sleepTimer = BeyGramSleepTimer(accountId: 0)
    private let sleepTimerPromise = ValuePromise<BeyGramSleepTimerState>(.off, ignoreRepeated: true)
    private var sleepTimerTicker: Foundation.Timer?
    private let equalizerPromise: ValuePromise<BeyGramEqualizerSettings>
    private var equalizerSettings: BeyGramEqualizerSettings

    private override init() {
        self.player = BGMixPlayer.shared()
        let initial = BeyGramMusicState()
        self.stateValue = Atomic(value: initial)
        self.statePromise = ValuePromise(initial, ignoreRepeated: true)
        let initialWave = BGYandexWaveState()
        self.waveStateValue = Atomic(value: initialWave)
        self.waveStatePromise = ValuePromise(initialWave, ignoreRepeated: true)
        let storedEqualizer = BeyGramEqualizerStore.read()
        self.equalizerSettings = storedEqualizer
        self.equalizerPromise = ValuePromise(storedEqualizer, ignoreRepeated: true)
        super.init()
        self.applyEqualizer()

        self.waveSessionController.hostTapHandler = { [weak self] tap in
            self?.player.setPcmTap(tap)
        }

        let coordinator = BGYandexWavePlaybackCoordinator(
            makeQueue: {
                let session = BGYandexRuntime.shared.makeWave(seeds: ["user:onyourwave"])
                return BGYandexWaveQueue(source: session, prepare: { track in
                    BeyGramTrackMetadataStore.shared.registerYandexTrack(track)
                    BGYandexRuntime.shared.localFile(trackId: track.trackId) { result in
                        if case let .success(url) = result {
                            BeyGramTrackMetadataStore.shared.associate(localURL: url, with: track)
                        }
                    }
                })
            },
            player: self,
            onLikeTrack: { trackId, liked in
                BGYandexRuntime.shared.setLiked(trackId: trackId, liked: liked) { _ in }
            }
        )
        coordinator.onStateChanged = { [weak self] waveState in
            guard let self else { return }
            _ = self.waveStateValue.swap(waveState)
            self.waveStatePromise.set(waveState)
        }
        self.waveCoordinator = coordinator
        self.nowPlayingCenter = BeyGramNowPlayingCenter(session: self)

        self.sleepTimer.onChange = { [weak self] state in
            self?.sleepTimerPromise.set(state)
            self?.updateSleepTimerTicker(active: state != .off)
        }
        self.sleepTimer.onFire = { [weak self] in
            self?.player.pause()
            self?.waveCoordinator?.stop()
        }

        self.player.setTransitionDuration(initial.transitionDuration)
        self.player.setAdaptiveTransitions(initial.adaptiveTransitions)
        self.player.setBassSwap(initial.bassSwap)
        self.player.add(self)
        self.metadataObserver = NotificationCenter.default.addObserver(forName: BeyGramTrackMetadataStore.didUpdateNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.mixPlayer(self.player, didUpdate: self.player.snapshot)
        }
        self.externalAudioObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.BGMixPlayerDidStopForExternalAudio, object: nil, queue: .main) { [weak self] _ in
            self?.nowPlayingCenter?.relinquishForExternalAudio()
        }
    }

    deinit {
        if let metadataObserver {
            NotificationCenter.default.removeObserver(metadataObserver)
        }
        if let externalAudioObserver {
            NotificationCenter.default.removeObserver(externalAudioObserver)
        }
        self.nowPlayingCenter?.relinquish()
        self.player.remove(self)
    }

    public var stateSignal: Signal<BeyGramMusicState, NoError> {
        return self.statePromise.get()
    }

    public var currentState: BeyGramMusicState {
        return self.stateValue.with { $0 }
    }

    public var waveStateSignal: Signal<BGYandexWaveState, NoError> {
        return self.waveStatePromise.get()
    }

    public var currentWaveState: BGYandexWaveState {
        return self.waveStateValue.with { $0 }
    }

    // MARK: Equalizer

    /// Bands of the player's equalizer: the preset anchors, so Android's curves map one to one.
    public static let equalizerFrequenciesHz = BeyGramEqualizer.presetAnchorFrequenciesHz
    /// The lowest band level, in millibels.
    public static let equalizerMinLevelMb = -1_200

    public var equalizerSignal: Signal<BeyGramEqualizerSettings, NoError> {
        return self.equalizerPromise.get()
    }

    public var currentEqualizer: BeyGramEqualizerSettings {
        return self.equalizerSettings
    }

    /// The levels the settings stand for, per band, before headroom.
    public func equalizerLevelsMb(for settings: BeyGramEqualizerSettings) -> [Int] {
        return BeyGramEqualizer.levels(for: settings, frequenciesHz: BeyGramMusicSession.equalizerFrequenciesHz, minLevelMb: BeyGramMusicSession.equalizerMinLevelMb, hardwareMaxLevelMb: BeyGramEqualizer.maxBoostMb)
    }

    public func setEqualizerEnabled(_ enabled: Bool) {
        self.updateEqualizer { $0.enabled = enabled }
    }

    public func selectEqualizerPreset(_ preset: BeyGramEqualizerPreset) {
        self.updateEqualizer { $0.selectedPreset = preset }
    }

    /// Sets one band of the custom curve and selects the custom preset. The first edit starts from the curve heard now.
    public func setEqualizerBand(index: Int, levelMb: Int, persist: Bool) {
        let frequencies = BeyGramMusicSession.equalizerFrequenciesHz
        guard index >= 0, index < frequencies.count else {
            return
        }
        self.updateEqualizer(persist: persist) { settings in
            var levels = self.equalizerLevelsMb(for: settings)
            levels[index] = min(max(levelMb, BeyGramMusicSession.equalizerMinLevelMb), BeyGramEqualizer.maxBoostMb)
            var custom: [Int: Int] = [:]
            for (band, frequency) in frequencies.enumerated() {
                custom[frequency] = levels[band]
            }
            settings.customLevelsMb = custom
            settings.selectedPreset = .custom
        }
    }

    public func resetEqualizer() {
        self.updateEqualizer { $0.selectedPreset = .flat }
    }

    private func updateEqualizer(persist: Bool = true, _ update: @escaping (inout BeyGramEqualizerSettings) -> Void) {
        DispatchQueue.main.async {
            var settings = self.equalizerSettings
            update(&settings)
            self.equalizerSettings = settings
            self.equalizerPromise.set(settings)
            if persist {
                BeyGramEqualizerStore.write(settings)
            }
            self.applyEqualizer()
        }
    }

    private func applyEqualizer() {
        let settings = self.equalizerSettings
        let levels = BeyGramEqualizer.withHeadroom(self.equalizerLevelsMb(for: settings), minLevelMb: BeyGramMusicSession.equalizerMinLevelMb)
        self.player.setEqualizerEnabled(settings.enabled,
                                        frequenciesHz: BeyGramMusicSession.equalizerFrequenciesHz.map { NSNumber(value: $0) },
                                        gainsDb: levels.map { NSNumber(value: Float($0) / 100.0) })
    }

    // MARK: Sleep timer

    public var sleepTimerSignal: Signal<BeyGramSleepTimerState, NoError> {
        return self.sleepTimerPromise.get()
    }

    public var sleepTimerState: BeyGramSleepTimerState {
        return self.sleepTimer.state
    }

    public func setSleepTimer(minutes: Int) {
        DispatchQueue.main.async {
            self.sleepTimer.setMinutes(minutes)
        }
    }

    public func setSleepTimerUntilTrackEnd() {
        DispatchQueue.main.async {
            self.sleepTimer.setUntilTrackEnd()
        }
    }

    public func extendSleepTimer() {
        DispatchQueue.main.async {
            self.sleepTimer.extend()
        }
    }

    public func cancelSleepTimer() {
        DispatchQueue.main.async {
            self.sleepTimer.cancel()
        }
    }

    /// Switching the account drops a timer set for another one.
    public func sleepTimerAccountChanged(to accountId: Int64) {
        DispatchQueue.main.async {
            self.sleepTimer.accountChanged(to: accountId)
        }
    }

    private func updateSleepTimerTicker(active: Bool) {
        if active, self.sleepTimerTicker == nil {
            self.sleepTimerTicker = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.sleepTimer.tick()
            }
        } else if !active {
            self.sleepTimerTicker?.invalidate()
            self.sleepTimerTicker = nil
        }
    }

    /// Feeds the timer with the player's track, and ends a track-end timer when its track ends, is left, or starts its fade into the next.
    private func updateSleepTimer(snapshot: BGMixSnapshot) {
        let currentId = snapshot.currentTrack.map { String($0.identifier) }
        let position = snapshot.position
        let duration = snapshot.duration
        let transitionActive = snapshot.transitionActive
        // The timer is main-queue only; the player reports from its own queue.
        DispatchQueue.main.async {
            self.sleepTimer.trackChanged(to: currentId)
            guard case let .untilTrackEnd(armedTrack, _) = self.sleepTimer.state, let armed = armedTrack else {
                return
            }
            let nearEnd = duration > 0 && position >= duration - 0.4
            if currentId != armed || nearEnd || transitionActive {
                self.sleepTimer.trackEnded(trackId: armed)
            }
        }
    }

    public func startOrToggleWave() {
        DispatchQueue.main.async {
            self.waveCoordinator.startOrTogglePlay()
        }
    }

    public func skipWaveTrack() {
        DispatchQueue.main.async {
            self.waveCoordinator.skip()
        }
    }

    public func toggleWaveLike() {
        DispatchQueue.main.async {
            self.waveCoordinator.toggleLike()
        }
    }

    public func stopWave() {
        DispatchQueue.main.async {
            self.waveCoordinator.stop()
        }
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

        self.updateSleepTimer(snapshot: snapshot)

        let currentTrack = snapshot.currentTrack
        let nextReady = snapshot.nextTrack?.state == .ready
        self.waveCoordinator?.handlePlaybackUpdate(
            currentItemId: currentTrack?.identifier,
            currentItemFailed: currentTrack?.state == .failed,
            currentItemPlayed: currentTrack?.state == .played,
            nextItemReady: nextReady,
            transitionActive: snapshot.transitionActive,
            isStopped: snapshot.transport == .stopped,
            position: snapshot.position,
            duration: snapshot.duration
        )

        self.nowPlayingCenter?.update(
            state: self.currentState,
            managesAudioSession: self.player.managesAudioSession,
            waveActive: self.currentWaveState.isActive
        )
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
            if self.player.tryStartNextTransition() {
                return
            }
            if let nextTrack = self.player.snapshot.nextTrack {
                _ = self.player.replaceQueueAndPlayTrack(at: nextTrack.fileURL)
            }
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

    /// Resolves a Yandex Music track through `BGYandexRuntime.shared`, registers its real title/artist/cover, and plays or enqueues it.
    public func playYandexTrack(_ track: BGYandexTrack, replaceQueue: Bool = false, completion: ((Result<Void, BGYandexPlaybackError>) -> Void)? = nil) {
        if replaceQueue {
            self.stopWave()
        }
        self.resolveAndQueueYandexTrack(track, replaceQueue: replaceQueue) { result in
            switch result {
            case .success:
                completion?(.success(()))
            case let .failure(error):
                completion?(.failure(error))
            }
        }
    }

    // MARK: - BGYandexWavePlayerAdapter

    public func playWaveTrack(_ track: BGYandexTrack, replaceQueue: Bool, completion: @escaping (Result<UInt64, BGYandexPlaybackError>) -> Void) {
        self.resolveAndQueueYandexTrack(track, replaceQueue: replaceQueue, completion: completion)
    }

    public func skipToPreparedNextWaveTrack() -> Bool {
        return self.player.tryStartNextTransition()
    }

    public func toggleWavePlayPause() {
        self.togglePlayPause()
    }

    private func resolveAndQueueYandexTrack(_ track: BGYandexTrack, replaceQueue: Bool, completion: @escaping (Result<UInt64, BGYandexPlaybackError>) -> Void) {
        BeyGramTrackMetadataStore.shared.registerYandexTrack(track)
        BGYandexRuntime.shared.playableFile(rowKey: "ym:\(track.trackId)") { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(fileURL):
                BeyGramTrackMetadataStore.shared.associate(localURL: fileURL, with: track)
                DispatchQueue.main.async {
                    self.player.managesAudioSession = true
                    let itemId: UInt64
                    if replaceQueue {
                        itemId = self.player.replaceQueueAndPlayTrack(at: fileURL)
                    } else {
                        itemId = self.player.addTrack(at: fileURL)
                        if itemId != 0 && !self.currentState.isPlaying {
                            self.player.play()
                        }
                    }
                    guard itemId != 0 else {
                        completion(.failure(.unavailable))
                        return
                    }
                    completion(.success(itemId))
                }
            case let .failure(error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}

/// Device-local equalizer preferences, as on Android (not per account).
enum BeyGramEqualizerStore {
    private static let enabledKey = "beygram.equalizer.enabled"
    private static let presetKey = "beygram.equalizer.preset"
    private static let customKey = "beygram.equalizer.customLevels"

    static func read() -> BeyGramEqualizerSettings {
        let defaults = UserDefaults.standard
        let preset = defaults.string(forKey: self.presetKey).flatMap { BeyGramEqualizerPreset(rawValue: $0) } ?? .flat
        return BeyGramEqualizerSettings(
            enabled: defaults.bool(forKey: self.enabledKey),
            selectedPreset: preset,
            customLevelsMb: BeyGramEqualizer.decodeLevels(defaults.string(forKey: self.customKey))
        )
    }

    static func write(_ settings: BeyGramEqualizerSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.enabled, forKey: self.enabledKey)
        defaults.set(settings.selectedPreset.rawValue, forKey: self.presetKey)
        defaults.set(BeyGramEqualizer.encodeLevels(settings.customLevelsMb), forKey: self.customKey)
    }
}
