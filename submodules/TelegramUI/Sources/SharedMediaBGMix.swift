import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import UniversalMediaPlayer
import TelegramAudio
import AccountContext
import BeyGramMedia
import BeyGramYandexMusic

/// BG Mix as the engine of the `.music` playlist in `SharedMediaPlayer`.
///
/// Ownership: the playlist decides what is current and what is next. MediaManager keeps the lock screen, the
/// remote commands and the audio session. BG Mix mixes: it prepares the tracks and crossfades to the track the
/// playlist moves to. Nothing here touches MPNowPlayingInfoCenter or MPRemoteCommandCenter.
///
/// Rules:
/// - BG Mix runs its own scheduled crossfades (AutoMix). When it moves on to the playlist's next item, the playlist
///   follows through `onAdvanceRequested`, so the list and the lock screen show the track that plays.
/// - A change of the current item from the playlist reaches BG Mix as a queue change. A manual crossfade happens only
///   when the playlist moves to the track BG Mix has already prepared as its next track. Any other change rebuilds
///   the queue.
/// - The session is held while playback is wanted. It is released on pause, at the end of the playlist, and when
///   the session manager takes it away. BG Mix does not resume by itself after an interruption.
/// - Sources: Telegram audio files, copied into `Documents/bgmix/library` because BG Mix reads app-private files.
///   Local files and Yandex Music are not playlist sources yet; they plug in through `fileURL(for:)`.
final class SharedMediaBGMixBackend: NSObject, BGMixPlayerObserver {
    /// Main queue. The current track has finished and BG Mix has nothing left to play.
    var onItemEnded: (() -> Void)?
    /// Main queue. The playlist should move to the prepared next track.
    var onAdvanceRequested: (() -> Void)?

    private struct StatusSample {
        let key: AnyHashable?
        let status: MediaPlayerStatus
    }

    private let engine: TelegramEngine
    private let audioSession: ManagedAudioSession
    private let player: BGMixPlayer
    private let statusPromise: Promise<StatusSample>

    private var currentItem: SharedMediaPlaylistItem?
    private var nextItem: SharedMediaPlaylistItem?

    private var trackIdByKey: [AnyHashable: UInt64] = [:]
    private var keyByTrackId: [UInt64: AnyHashable] = [:]
    private var queueOrder: [AnyHashable] = []
    private var fillGeneration = 0
    private let fillDisposable = MetaDisposable()

    private var endedTrackId: UInt64?
    /// The item the playlist was last asked to move to. Cleared when the playlist's current item changes, so a later
    /// return to an earlier item is followed again.
    private var advanceRequestedTo: AnyHashable?
    private var pendingResume: (key: AnyHashable, position: Double)?
    private var wasTransitioning = false
    /// The transport of the last snapshot. Its change from playing to paused is the only sign of a pause by the system.
    private var lastTransport: BGMixTransport = .stopped

    private var wantsPlaying = false
    private var sessionDisposable: Disposable?
    private var sessionActive = false

    init(engine: TelegramEngine, audioSession: ManagedAudioSession) {
        self.engine = engine
        self.audioSession = audioSession
        self.player = BGMixPlayer.sharedPlayer()
        self.statusPromise = Promise(StatusSample(key: nil, status: SharedMediaBGMixBackend.idleStatus()))
        super.init()
        self.player.managesAudioSession = false
        self.player.addObserver(self)
    }

    /// Ends the backend when its playlist player goes away: nothing keeps sounding, the queue is emptied, and the
    /// shared player goes back to managing its own session (the BG Mix screen needs that).
    func shutdown() {
        self.player.removeObserver(self)
        self.pendingResume = nil
        self.wantsPlaying = false
        self.fillGeneration += 1
        self.fillDisposable.set(nil)
        self.releaseSession()
        self.player.stopAll()
        self.player.clearQueue()
        self.forgetTracks()
        self.currentItem = nil
        self.nextItem = nil
        self.player.managesAudioSession = true
    }

    /// The playback status of `item`. BG Mix reports on its master track, so any other item reads as idle, and only
    /// the item that is really on the master track can be marked as played.
    func status(for item: SharedMediaPlaylistItem) -> Signal<MediaPlayerStatus, NoError> {
        return self.statusPromise.get()
        |> map { sample -> MediaPlayerStatus in
            if sample.key == item.stableId {
                return sample.status
            } else {
                return SharedMediaBGMixBackend.idleStatus()
            }
        }
    }

    /// The playlist's current and next item changed. Brings the queue in line with them.
    func update(current: SharedMediaPlaylistItem?, next: SharedMediaPlaylistItem?) {
        if current?.stableId != self.currentItem?.stableId {
            self.pendingResume = nil
            self.advanceRequestedTo = nil
        }
        self.currentItem = current
        self.nextItem = next
        if current == nil {
            // The playlist is empty: nothing plays, nothing is queued, and the session is let go.
            self.wantsPlaying = false
            self.fillGeneration += 1
            self.fillDisposable.set(nil)
            self.player.stopAll()
            self.player.clearQueue()
            self.forgetTracks()
            self.releaseSession()
            return
        }
        self.syncQueue()
    }

    /// The current item repeats: the queue is rebuilt from it and playback is wanted again.
    func restartCurrent() {
        self.rebuild()
        self.play()
    }

    func play() {
        self.wantsPlaying = true
        if self.sessionDisposable == nil {
            self.acquireSession()
        } else if self.sessionActive {
            self.tryPlay(self.player.snapshot)
        }
    }

    func pause() {
        self.wantsPlaying = false
        self.releaseSession()
    }

    func togglePlayPause() {
        if self.wantsPlaying {
            self.pause()
        } else {
            self.play()
        }
    }

    func seek(_ timestamp: Double) {
        // BG Mix refuses a seek during a crossfade or with nothing loaded. The refusal is not retried.
        _ = self.player.seek(toPosition: timestamp)
    }

    // MARK: - BGMixPlayerObserver

    func mixPlayer(_ mixPlayer: BGMixPlayer, didUpdateSnapshot snapshot: BGMixSnapshot) {
        let previousTransport = self.lastTransport
        self.lastTransport = snapshot.transport
        self.publish(snapshot)

        if self.wasTransitioning != snapshot.transitionActive {
            self.wasTransitioning = snapshot.transitionActive
            if !snapshot.transitionActive {
                // The crossfade is over: the incoming track is the master now, and the queue behind it is refilled.
                self.syncQueue()
            }
        }

        self.checkEnded(snapshot)

        // Only a change from playing to paused is a pause by the system (an interruption, or the route went away). A track
        // that is loaded and waits for its first play also reads as paused, and must not cancel a play request.
        if previousTransport == .playing, snapshot.transport == .paused, self.wantsPlaying, self.sessionActive, snapshot.currentTrack?.state != .played {
            // It stays paused.
            self.wantsPlaying = false
            self.releaseSession()
            return
        }

        self.applyPendingResume(snapshot)
        self.checkFollow(snapshot)
        self.tryPlay(snapshot)
    }

    // MARK: - Session

    private func acquireSession() {
        self.sessionActive = false
        self.sessionDisposable = self.audioSession.push(audioSessionType: .play(mixWithOthers: false), activate: { [weak self] _ in
            Queue.mainQueue().async {
                self?.sessionDidActivate()
            }
        }, deactivate: { [weak self] _ in
            Queue.mainQueue().async {
                self?.sessionWasTaken()
            }
            return .single(Void())
        })
    }

    private func sessionDidActivate() {
        guard self.sessionDisposable != nil else {
            return
        }
        self.sessionActive = true
        self.tryPlay(self.player.snapshot)
    }

    /// A call or a recording took the audio. The music path pauses and lets go.
    private func sessionWasTaken() {
        self.wantsPlaying = false
        self.releaseSession()
    }

    private func releaseSession() {
        self.sessionDisposable?.dispose()
        self.sessionDisposable = nil
        self.sessionActive = false
        self.player.stopEngine()
    }

    private func tryPlay(_ snapshot: BGMixSnapshot) {
        guard self.wantsPlaying, self.sessionActive, snapshot.transport != .playing, let master = snapshot.currentTrack else {
            return
        }
        guard master.state == .ready || master.state == .playing else {
            return
        }
        self.player.play()
    }

    // MARK: - Transitions and the end of a track

    private func checkEnded(_ snapshot: BGMixSnapshot) {
        guard let master = snapshot.currentTrack, master.state == .played, !snapshot.transitionActive else {
            return
        }
        if self.endedTrackId == master.identifier {
            return
        }
        self.endedTrackId = master.identifier
        self.onItemEnded?()
    }

    /// BG Mix has moved on to the playlist's next item: a scheduled crossfade has started it, or the outgoing track ended
    /// and the prepared one took over. The playlist follows once per item, so the list and the lock screen show the track
    /// that plays.
    private func checkFollow(_ snapshot: BGMixSnapshot) {
        guard let currentItem = self.currentItem, let nextItem = self.nextItem,
              nextItem.stableId != currentItem.stableId,
              self.advanceRequestedTo != nextItem.stableId
        else {
            return
        }
        // During a crossfade the incoming track is on the other deck. Otherwise the master is the track in play.
        let playing: BGMixTrack? = snapshot.transitionActive ? snapshot.nextTrack : snapshot.currentTrack
        guard let track = playing, self.keyByTrackId[track.identifier] == nextItem.stableId else {
            return
        }
        // Set before the call: the playlist may answer synchronously, and that answer clears it.
        self.advanceRequestedTo = nextItem.stableId
        self.onAdvanceRequested?()
    }

    /// After a rebuild, the position the listener was at comes back once the track plays again.
    private func applyPendingResume(_ snapshot: BGMixSnapshot) {
        guard let pending = self.pendingResume, !snapshot.transitionActive, let master = snapshot.currentTrack,
              master.state == .playing, self.keyByTrackId[master.identifier] == pending.key
        else {
            return
        }
        self.pendingResume = nil
        _ = self.player.seek(toPosition: pending.position)
    }

    // MARK: - Queue

    /// Brings BG Mix in line with the playlist: keep the master, crossfade to the prepared next track, or rebuild.
    private func syncQueue() {
        guard let currentItem = self.currentItem else {
            return
        }
        let snapshot = self.player.snapshot
        if snapshot.transitionActive {
            // A crossfade is running. The queue is settled when it completes: the observer calls syncQueue then.
            return
        }
        if let master = snapshot.currentTrack, self.keyByTrackId[master.identifier] == currentItem.stableId {
            // The current track is on the master deck and keeps playing. Only the queue behind it changes.
            var keep: [AnyHashable] = [currentItem.stableId]
            if let nextItem = self.nextItem {
                keep.append(nextItem.stableId)
            }
            if !self.trimQueue(keeping: keep, snapshot: snapshot) {
                // A track that is no longer wanted is loaded on the other deck, and BG Mix does not unload a loaded deck.
                // Rebuild, and return to the position the listener was at.
                self.pendingResume = (key: currentItem.stableId, position: snapshot.position)
                self.rebuild()
                return
            }
            self.fill()
            return
        }
        if let deckB = snapshot.nextTrack, deckB.state == .ready, self.keyByTrackId[deckB.identifier] == currentItem.stableId,
           snapshot.transport == .playing, snapshot.currentTrack?.state == .playing {
            // The playlist moved to the track BG Mix has prepared (a manual Next): crossfade to it.
            self.player.next()
            return
        }
        self.rebuild()
    }

    /// Stops BG Mix, empties its queue, and queues the current and next items again.
    private func rebuild() {
        self.fillGeneration += 1
        self.fillDisposable.set(nil)
        self.player.stopAll()
        self.lastTransport = .stopped
        self.player.clearQueue()
        self.forgetTracks()
        self.endedTrackId = nil
        self.fill()
    }

    /// Removes queued tracks that are no longer the current or the next item. Returns false when a track that still has
    /// to play is loaded on a deck, which BG Mix does not allow to remove. A played track is unloaded and pruned by BG Mix.
    private func trimQueue(keeping keys: [AnyHashable], snapshot: BGMixSnapshot) -> Bool {
        let stale = self.queueOrder.filter { !keys.contains($0) }
        var settled = true
        for key in stale {
            if let trackId = self.trackIdByKey[key] {
                if !self.player.removeTrack(withIdentifier: trackId) {
                    let played = snapshot.queue.first(where: { $0.identifier == trackId })?.state == .played
                    if !played {
                        settled = false
                    }
                }
                self.keyByTrackId[trackId] = nil
            }
            self.trackIdByKey[key] = nil
        }
        self.queueOrder.removeAll(where: { stale.contains($0) })
        return settled
    }

    private func forgetTracks() {
        self.trackIdByKey.removeAll()
        self.keyByTrackId.removeAll()
        self.queueOrder.removeAll()
    }

    /// Resolves the files of the current and next items that are not queued yet, then queues them in order.
    private func fill() {
        guard let currentItem = self.currentItem else {
            return
        }
        let nextItem = self.nextItem
        let needsCurrent = self.trackIdByKey[currentItem.stableId] == nil
        let needsNext = nextItem.map { self.trackIdByKey[$0.stableId] == nil } ?? false
        guard needsCurrent || needsNext else {
            return
        }

        self.fillGeneration += 1
        let generation = self.fillGeneration

        let currentSignal: Signal<URL?, NoError>
        if needsCurrent {
            currentSignal = self.fileURL(for: currentItem)
        } else {
            currentSignal = .single(nil)
        }
        let nextSignal: Signal<URL?, NoError>
        if needsNext, let nextItem = nextItem {
            nextSignal = self.fileURL(for: nextItem)
        } else {
            nextSignal = .single(nil)
        }
        let neededCurrent: SharedMediaPlaylistItem? = needsCurrent ? currentItem : nil
        let neededNext: SharedMediaPlaylistItem? = needsNext ? nextItem : nil

        self.fillDisposable.set((currentSignal
        |> mapToSignal { currentURL -> Signal<(URL?, URL?), NoError> in
            return nextSignal
            |> map { nextURL -> (URL?, URL?) in
                return (currentURL, nextURL)
            }
        }
        |> deliverOnMainQueue).startStrict(next: { [weak self] urls in
            self?.commitFill(generation: generation, current: neededCurrent, currentURL: urls.0, next: neededNext, nextURL: urls.1)
        }))
    }

    private func commitFill(generation: Int, current: SharedMediaPlaylistItem?, currentURL: URL?, next: SharedMediaPlaylistItem?, nextURL: URL?) {
        guard generation == self.fillGeneration else {
            return
        }
        if let current = current {
            guard let currentURL = currentURL, self.addToQueue(current, url: currentURL) else {
                // The current track cannot be queued (its file is missing, or BG Mix refused it): move on.
                self.onItemEnded?()
                return
            }
        }
        if let next = next, let nextURL = nextURL {
            _ = self.addToQueue(next, url: nextURL)
        }
        self.tryPlay(self.player.snapshot)
    }

    private func addToQueue(_ item: SharedMediaPlaylistItem, url: URL) -> Bool {
        if self.trackIdByKey[item.stableId] != nil {
            return true
        }
        let trackId = self.player.addTrack(at: url)
        if trackId == 0 {
            return false
        }
        self.trackIdByKey[item.stableId] = trackId
        self.keyByTrackId[trackId] = item.stableId
        self.queueOrder.append(item.stableId)
        return true
    }

    /// A file BG Mix can read, or nil for a track that cannot be played (BG Mix then skips it). A local file is read from
    /// the BG Mix folder. A Yandex track gives the file its service keeps in the app's folder. A Telegram audio file gives
    /// an app-private copy, made once; it is downloaded first if it is not on disk yet.
    private func fileURL(for item: SharedMediaPlaylistItem) -> Signal<URL?, NoError> {
        if let playbackData = item.playbackData, case let .localFile(rowKey) = playbackData.source {
            // The row key is `local:` followed by the file name in the BG Mix folder. A name that is not a plain file name
            // (a path, a hidden file) is refused, so the key cannot reach outside that folder.
            guard rowKey.hasPrefix("local:") else {
                return .single(nil)
            }
            let fileName = String(rowKey.dropFirst("local:".count))
            guard !fileName.isEmpty, !fileName.hasPrefix("."), (fileName as NSString).lastPathComponent == fileName else {
                return .single(nil)
            }
            let url = BGMixPlayer.mixDirectory().appendingPathComponent(fileName)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                return .single(url)
            }
            return .single(nil)
        }
        if let playbackData = item.playbackData, case let .yandexTrack(rowKey) = playbackData.source {
            // Emits once: the file when it is on disk, or nil when the track cannot be played. Nothing is emitted while it downloads.
            return Signal<URL?, NoError> { subscriber in
                BGYandexRuntime.shared.playableFile(rowKey: rowKey) { result in
                    switch result {
                    case let .success(url):
                        subscriber.putNext(url)
                    case .failure:
                        subscriber.putNext(nil)
                    }
                    subscriber.putCompletion()
                }
                return EmptyDisposable
            }
        }
        guard let playbackData = item.playbackData, case let .telegramFile(reference, _, _) = playbackData.source else {
            return .single(nil)
        }
        let media = reference.media
        let libraryDirectory = BGMixPlayer.mixDirectory().appendingPathComponent("library", isDirectory: true)
        var fileName = "\(media.fileId.namespace)-\(media.fileId.id)"
        if let name = media.fileName {
            let fileExtension = (name as NSString).pathExtension
            if !fileExtension.isEmpty {
                fileName += "." + fileExtension
            }
        }
        let target = libraryDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: target.path) {
            return .single(target)
        }

        let complete = self.engine.resources.data(resource: EngineMediaResource(media.resource))
        |> filter { data -> Bool in
            return data.isComplete
        }
        |> take(1)
        |> deliverOn(Queue.concurrentDefaultQueue())
        |> map { data -> URL? in
            let source = URL(fileURLWithPath: data.path)
            do {
                try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true, attributes: nil)
                if !FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.copyItem(at: source, to: target)
                }
                return target
            } catch {
                return nil
            }
        }
        |> deliverOnMainQueue

        // The fetch ends with the file on disk (`true`) or with a failed download (`false`). After a failed download the file
        // never completes, so waiting for it would hang. A failed fetch answers nil at once, and BG Mix skips the track.
        let fetchSucceeded: Signal<Bool, NoError> = self.engine.resources.fetch(reference: reference.resourceReference(media.resource), userLocation: .other, userContentType: .audio)
        |> ignoreValues
        |> map { _ -> Bool in return true }
        |> then(.single(true))
        |> `catch` { _ -> Signal<Bool, NoError> in
            return .single(false)
        }
        return fetchSucceeded |> mapToSignal { succeeded -> Signal<URL?, NoError> in
            if succeeded {
                return complete
            } else {
                return .single(nil)
            }
        }
    }

    // MARK: - Published state

    private func publish(_ snapshot: BGMixSnapshot) {
        var playbackStatus: MediaPlayerPlaybackStatus = snapshot.transport == .playing ? .playing : .paused
        if let master = snapshot.currentTrack, master.state == .pending || master.state == .preparing {
            playbackStatus = .buffering(initial: true, whilePlaying: false, progress: master.progress, display: true)
        }
        let masterKey: AnyHashable? = snapshot.currentTrack.flatMap { self.keyByTrackId[$0.identifier] }
        let status = MediaPlayerStatus(generationTimestamp: CFAbsoluteTimeGetCurrent(), duration: snapshot.duration, dimensions: CGSize(), timestamp: snapshot.position, baseRate: 1.0, seekId: 0, status: playbackStatus, soundEnabled: true)
        self.statusPromise.set(.single(StatusSample(key: masterKey, status: status)))
    }

    private static func idleStatus() -> MediaPlayerStatus {
        return MediaPlayerStatus(generationTimestamp: CFAbsoluteTimeGetCurrent(), duration: 0.0, dimensions: CGSize(), timestamp: 0.0, baseRate: 1.0, seekId: 0, status: .paused, soundEnabled: true)
    }
}
