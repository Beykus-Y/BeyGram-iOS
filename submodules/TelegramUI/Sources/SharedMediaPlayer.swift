import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import UniversalMediaPlayer
import TelegramAudio
import AccountContext
import TelegramUniversalVideoContent
import DeviceProximity
import PeerMessagesMediaPlaylist
import BeyGramKit
import BeyGramMedia
import BeyGramYandexMusic

private enum SharedMediaPlaybackItem: Equatable {
    case audio(MediaPlayer)
    case instantVideo(OverlayInstantVideoNode)
    
    var playbackStatus: Signal<MediaPlayerStatus, NoError> {
        switch self {
            case let .audio(player):
                return player.status
            case let .instantVideo(node):
                return node.status |> map { status in
                    if let status = status {
                        return status
                    } else {
                        return MediaPlayerStatus(generationTimestamp: 0.0, duration: 0.0, dimensions: CGSize(), timestamp: 0.0, baseRate: 1.0, seekId: 0, status: .paused, soundEnabled: true)
                    }
                }
        }
    }
    
    static func ==(lhs: SharedMediaPlaybackItem, rhs: SharedMediaPlaybackItem) -> Bool {
        switch lhs {
            case let .audio(lhsPlayer):
                if case let .audio(rhsPlayer) = rhs, lhsPlayer === rhsPlayer {
                    return true
                } else {
                    return false
                }
            case let .instantVideo(lhsNode):
                if case let .instantVideo(rhsNode) = rhs, lhsNode === rhsNode {
                    return true
                } else {
                    return false
                }
        }
    }
    
    func setActionAtEnd(_ f: @escaping () -> Void) {
        switch self {
            case let .audio(player):
                player.actionAtEnd = .action(f)
            case let .instantVideo(node):
                node.playbackEnded = f
        }
    }
    
    func play() {
        switch self {
            case let .audio(player):
                player.play()
            case let .instantVideo(node):
                node.play()
        }
    }
    
    func pause() {
        switch self {
            case let .audio(player):
                player.pause()
            case let .instantVideo(node):
                node.pause()
        }
    }
    
    func togglePlayPause() {
        switch self {
            case let .audio(player):
                player.togglePlayPause(faded: true)
            case let .instantVideo(node):
                node.togglePlayPause()
        }
    }
    
    func seek(_ timestamp: Double) {
        switch self {
            case let .audio(player):
                player.seek(timestamp: timestamp)
            case let .instantVideo(node):
                node.seek(timestamp)
        }
    }
    
    func setSoundEnabled(_ value: Bool) {
        switch self {
            case .audio:
                break
            case let .instantVideo(node):
                node.setSoundEnabled(value)
        }
    }
    
    func setForceAudioToSpeaker(_ value: Bool) {
        switch self {
            case let .audio(player):
                player.setForceAudioToSpeaker(value)
            case let .instantVideo(node):
                node.setForceAudioToSpeaker(value)
        }
    }
}

final class SharedMediaPlayer {
    private weak var context: AccountContext?
    private weak var mediaManager: MediaManager?
    let engine: TelegramEngine
    private let audioSession: ManagedAudioSession
    private let overlayMediaManager: OverlayMediaManager
    private let playerIndex: Int32
    let playlist: SharedMediaPlaylist
    
    private var playbackRate: AudioPlaybackRate
    
    private var proximityManagerIndex: Int?
    private let controlPlaybackWithProximity: Bool
    private var forceAudioToSpeaker = false
    
    private var stateDisposable: Disposable?
    
    private var stateValue: SharedMediaPlaylistState? {
        didSet {
            if self.stateValue != oldValue {
                self.state.set(.single(self.stateValue))
            }
        }
    }
    private let state = Promise<SharedMediaPlaylistState?>(nil)
    
    private var playbackStateValueDisposable: Disposable?
    private var _playbackStateValue: SharedMediaPlayerState?
    private let playbackStateValue = Promise<SharedMediaPlayerState?>()
    var playbackState: Signal<SharedMediaPlayerState?, NoError> {
        return self.playbackStateValue.get()
    }
    
    private let audioLevelPipe = ValuePipe<Float>()
    var audioLevel: Signal<Float, NoError> {
        return self.audioLevelPipe.signal()
    }
    private let audioLevelDisposable = MetaDisposable()
    
    private var playbackItem: SharedMediaPlaybackItem? {
        didSet {
            if playbackItem != oldValue {
                switch playbackItem {
                case let .audio(player):
                    let audioLevelPipe = self.audioLevelPipe
                    self.audioLevelDisposable.set((player.audioLevelEvents.startStrict(next: { [weak audioLevelPipe] value in
                        audioLevelPipe?.putNext(value)
                    })))
                default:
                    self.audioLevelDisposable.set(nil)
                }
            }
        }
    }
    private var currentPlayedToEnd = false
    private var scheduledPlaybackAction: SharedMediaPlayerPlaybackControlAction?
    private var scheduledStartTime: Double?
    
    private let markItemAsPlayedDisposable = MetaDisposable()
    
    var playedToEnd: (() -> Void)?
    var cancelled: (() -> Void)?
    
    private var inForegroundDisposable: Disposable?
    
    private var currentPrefetchItems: (SharedMediaPlaybackDataSource, SharedMediaPlaybackDataSource)?
    private let prefetchDisposable = MetaDisposable()
    
    let type: MediaManagerPlayerType
    // BG Mix backend is created lazily ONLY for non-Telegram sources (.yandexTrack / .localFile).
    // Standard Telegram .telegramFile music always uses Telegram's native MediaPlayer.
    private var bgMix: SharedMediaBGMixBackend?
    private var bgMixPlaybackStartedObserver: NSObjectProtocol?
    /// The item the playlist was asked to leave, for BG Mix. If the list settles on that same item, short of its end, BG Mix starts it again.
    private var bgMixAdvanceFrom: AnyHashable?
    /// Items in a row that BG Mix could not play. Reaching the limit pauses playback rather than cycling through the list.
    private var bgMixFailureStreak = BGMixFailureStreak()
    
    init(context: AccountContext, mediaManager: MediaManager, inForeground: Signal<Bool, NoError>, engine: TelegramEngine, audioSession: ManagedAudioSession, overlayMediaManager: OverlayMediaManager, playlist: SharedMediaPlaylist, initialOrder: MusicPlaybackSettingsOrder, initialLooping: MusicPlaybackSettingsLooping, initialPlaybackRate: AudioPlaybackRate, playerIndex: Int32, controlPlaybackWithProximity: Bool, type: MediaManagerPlayerType, continueInstantVideoLoopAfterFinish: Bool) {
        self.context = context
        self.mediaManager = mediaManager
        self.engine = engine
        self.audioSession = audioSession
        self.overlayMediaManager = overlayMediaManager
        playlist.setOrder(initialOrder)
        playlist.setLooping(initialLooping)
        self.playlist = playlist
        self.playerIndex = playerIndex
        self.playbackRate = initialPlaybackRate
        self.controlPlaybackWithProximity = controlPlaybackWithProximity
        self.type = type
        
        if controlPlaybackWithProximity {
            self.forceAudioToSpeaker = !DeviceProximityManager.shared().currentValue()
        } else {
            self.forceAudioToSpeaker = true
        }
        
        playlist.currentItemDisappeared = { [weak self] in
            self?.cancelled?()
        }

        self.bgMixPlaybackStartedObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.BGMixPlayerDidStartPlayback, object: nil, queue: .main) { [weak self] _ in
            guard let strongSelf = self, strongSelf.bgMix == nil else {
                return
            }
            if let playbackItem = strongSelf.playbackItem {
                switch playbackItem {
                    case .audio:
                        playbackItem.pause()
                    case let .instantVideo(node):
                        node.setSoundEnabled(false)
                }
            }
        }

        self.stateDisposable = (playlist.state
        |> deliverOnMainQueue).startStrict(next: { [weak self] state in
            if let strongSelf = self {
                let previousPlaybackItem = strongSelf.playbackItem
                strongSelf.updatePrefetchItems(item: state.item, previousItem: state.previousItem, nextItem: state.nextItem, ordering: state.order)
                let shouldUseBGMix = strongSelf.type == .music
                    && BeyGramSettings.shared.isEnabled(.musicLibrary)
                    && SharedMediaPlayer.requiresBGMix(for: state.item)
                if shouldUseBGMix {
                    if let playbackItem = strongSelf.playbackItem {
                        switch playbackItem {
                            case .audio:
                                playbackItem.pause()
                            case let .instantVideo(node):
                                node.setSoundEnabled(false)
                                strongSelf.overlayMediaManager.controller?.removeNode(node, customTransition: false)
                        }
                        strongSelf.playbackItem = nil
                    }
                    let bgMix = strongSelf.ensureBGMixBackend()
                    if let scheduledAction = strongSelf.scheduledPlaybackAction {
                        strongSelf.scheduledPlaybackAction = nil
                        strongSelf.scheduledStartTime = nil
                        switch scheduledAction {
                            case .play:
                                bgMix.play()
                            case .pause:
                                bgMix.pause()
                            case .togglePlayPause:
                                bgMix.togglePlayPause()
                        }
                    }
                    strongSelf.applyBGMixState(state, bgMix: bgMix)
                    return
                }
                if let oldBGMix = strongSelf.bgMix {
                    oldBGMix.shutdown()
                    strongSelf.bgMix = nil
                }
                if state.item?.playbackData != strongSelf.stateValue?.item?.playbackData {
                    if let playbackItem = strongSelf.playbackItem {
                        switch playbackItem {
                            case .audio:
                                playbackItem.pause()
                            case let .instantVideo(node):
                               node.setSoundEnabled(false)
                               strongSelf.overlayMediaManager.controller?.removeNode(node, customTransition: false)
                        }
                    }
                    strongSelf.playbackItem = nil
                    if let item = state.item, let playbackData = item.playbackData {
                        let rateValue: Double
                        if case .music = playbackData.type {
                            rateValue = 1.0
                        } else {
                            rateValue = strongSelf.playbackRate.doubleValue
                        }
                        
                        switch playbackData.type {
                            case .voice, .music:
                                switch playbackData.source {
                                    case let .telegramFile(fileReference, _, _):
                                    strongSelf.playbackItem = .audio(MediaPlayer(audioSessionManager: strongSelf.audioSession, postbox: strongSelf.engine.account.postbox, userLocation: .other,  userContentType: .audio, resourceReference: fileReference.resourceReference(fileReference.media.resource), streamable: playbackData.type == .music ? .conservative : .none, video: false, preferSoftwareDecoding: false, enableSound: true, baseRate: rateValue, fetchAutomatically: true, playAndRecord: controlPlaybackWithProximity, isAudioVideoMessage: playbackData.type == .voice))
                                    case .yandexTrack, .localFile:
                                        // A Yandex track or a local file has no Telegram resource for MediaPlayer. BG Mix plays it (see fileResult(for:)).
                                        break
                                }
                            case .instantVideo:
                                if let mediaManager = strongSelf.mediaManager, let context = strongSelf.context, let item = item as? MessageMediaPlaylistItem {
                                    switch playbackData.source {
                                        case let .telegramFile(fileReference, _, _):
                                        let videoNode = OverlayInstantVideoNode(context: context, audioSession: strongSelf.audioSession, manager: mediaManager.universalVideoManager, content: NativeVideoContent(id: .message(item.message.stableId, fileReference.media.fileId), userLocation: .peer(item.message.id.peerId), fileReference: fileReference, enableSound: false, baseRate: rateValue, isAudioVideoMessage: true, captureProtected: item.message.isCopyProtected(), storeAfterDownload: nil), close: { [weak mediaManager] in
                                                mediaManager?.setPlaylist(nil, type: .voice, control: .playback(.pause))
                                            })
                                            strongSelf.playbackItem = .instantVideo(videoNode)
                                            videoNode.setSoundEnabled(true)
                                        videoNode.setBaseRate(rateValue)
                                    case .yandexTrack, .localFile:
                                        break
                                    }
                                }
                        }
                    }
                    if let playbackItem = strongSelf.playbackItem {
                        playbackItem.setForceAudioToSpeaker(strongSelf.forceAudioToSpeaker)
                        playbackItem.setActionAtEnd({
                            Queue.mainQueue().async {
                                if let strongSelf = self {
                                    switch strongSelf.playlist.looping {
                                        case .item:
                                            strongSelf.playbackItem?.seek(0.0)
                                            strongSelf.playbackItem?.play()
                                        default:
                                            strongSelf.scheduledPlaybackAction = .play
                                            strongSelf.control(.next)
                                    }
                                }
                            }
                        })
                        switch playbackItem {
                            case .audio:
                                break
                            case let .instantVideo(node):
                                strongSelf.overlayMediaManager.controller?.addNode(node, customTransition: false)
                        }
                        
                        if let scheduledPlaybackAction = strongSelf.scheduledPlaybackAction {
                            strongSelf.scheduledPlaybackAction = nil
                            let scheduledStartTime = strongSelf.scheduledStartTime
                            strongSelf.scheduledStartTime = nil
                            
                            switch scheduledPlaybackAction {
                                case .play:
                                    BGMixPlayer.stopSharedEngineIfRunning()
                                    switch playbackItem {
                                        case let .audio(player):
                                            if let scheduledStartTime = scheduledStartTime {
                                                player.seek(timestamp: scheduledStartTime)
                                                player.play()
                                            } else {
                                                player.play()
                                            }
                                        case let .instantVideo(node):
                                            if let scheduledStartTime = scheduledStartTime {
                                                node.seek(scheduledStartTime)
                                                node.playOnceWithSound(playAndRecord: controlPlaybackWithProximity)
                                            } else {
                                                node.playOnceWithSound(playAndRecord: controlPlaybackWithProximity)
                                            }
                                    }
                                case .pause:
                                    playbackItem.pause()
                                case .togglePlayPause:
                                    BGMixPlayer.stopSharedEngineIfRunning()
                                    playbackItem.togglePlayPause()
                            }
                        }
                    }
                }
                
                if strongSelf.currentPlayedToEnd != state.playedToEnd {
                    strongSelf.currentPlayedToEnd = state.playedToEnd
                    if state.playedToEnd {
                        if let playbackItem = strongSelf.playbackItem {
                            switch playbackItem {
                                case let .audio(player):
                                    player.pause()
                                case let .instantVideo(node):
                                    if continueInstantVideoLoopAfterFinish {
                                        node.setSoundEnabled(false)
                                    } else {
                                        node.pause()
                                    }
                            }
                        }
                        strongSelf.playedToEnd?()
                    }
                }
                
                let updatePlaybackState = strongSelf.stateValue != state || strongSelf.playbackItem != previousPlaybackItem
                strongSelf.stateValue = state
                
                if updatePlaybackState {
                    let playlistId = strongSelf.playlist.id
                    let playlistLocation = strongSelf.playlist.location
                    let playerIndex = strongSelf.playerIndex
                    if let playbackItem = strongSelf.playbackItem, let item = state.item {
                        strongSelf.playbackStateValue.set(playbackItem.playbackStatus
                        |> map { itemStatus in
                            return .item(SharedMediaPlayerItemPlaybackState(playlistId: playlistId, playlistLocation: playlistLocation, item: item, previousItem: state.previousItem, nextItem: state.nextItem, status: itemStatus, order: state.order, looping: state.looping, playerIndex: playerIndex))
                        })
                    strongSelf.markItemAsPlayedDisposable.set((playbackItem.playbackStatus
                        |> filter { status in
                            if case .playing = status.status {
                                return true
                            } else {
                                return false
                            }
                        }
                        |> take(1)
                        |> deliverOnMainQueue).startStrict(next: { next in
                            if let strongSelf = self {
                                strongSelf.playlist.onItemPlaybackStarted(item)
                            }
                        }))
                    } else {
                        if state.item != nil || state.loading {
                            strongSelf.playbackStateValue.set(.single(.loading))
                        } else {
                            strongSelf.playbackStateValue.set(.single(nil))
                            if !state.loading {
                                if let proximityManagerIndex = strongSelf.proximityManagerIndex {
                                    DeviceProximityManager.shared().remove(proximityManagerIndex)
                                }
                            }
                        }
                    }
                }
            }
        })
        
        self.playbackStateValueDisposable = (self.playbackState
        |> deliverOnMainQueue).startStrict(next: { [weak self] value in
            self?._playbackStateValue = value
        })
        
        if controlPlaybackWithProximity {
            self.proximityManagerIndex = DeviceProximityManager.shared().add { [weak self] value in
                let forceAudioToSpeaker = !value
                if let strongSelf = self, strongSelf.forceAudioToSpeaker != forceAudioToSpeaker {
                    strongSelf.forceAudioToSpeaker = forceAudioToSpeaker
                    strongSelf.playbackItem?.setForceAudioToSpeaker(forceAudioToSpeaker)
                    if !forceAudioToSpeaker {
                        // A voice or video message is being recorded: the sensor is covered by the user's face
                        // while speaking, not to ask for playback on the ear speaker. Resuming would push a
                        // playback audio session on top of the recorder's, and the recorder stops as soon as
                        // its session is deactivated.
                        //
                        // Only the resume is skipped, and the state above is tracked either way. This block is
                        // edge-triggered on forceAudioToSpeaker, so returning before the assignment would
                        // strand it at its old value for good: the sensor and the stored value would disagree
                        // from then on, and the next playback would take the wrong route - the ear speaker
                        // with the phone in hand, i.e. inaudible. The assignment is safe here because the
                        // playback holder is inactive while a recorder holds the session, so setOutputMode
                        // only records the intended mode instead of touching the live session.
                        if strongSelf.audioSession.getIsRecordingActive() {
                            return
                        }
                        if let playbackStateValue = strongSelf._playbackStateValue, case let .item(item) = playbackStateValue, item.status.timestamp < 1.5 {
                            strongSelf.control(.seek(0.0))
                        }
                        strongSelf.control(.playback(.play))
                    } else {
                        strongSelf.control(.playback(.pause))
                    }
                }
            }
        }
    }
    
    deinit {
        if let observer = self.bgMixPlaybackStartedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        self.bgMix?.shutdown()
        self.stateDisposable?.dispose()
        self.markItemAsPlayedDisposable.dispose()
        self.inForegroundDisposable?.dispose()
        self.playbackStateValueDisposable?.dispose()
        self.prefetchDisposable.dispose()
        self.audioLevelDisposable.dispose()
        
        if let proximityManagerIndex = self.proximityManagerIndex {
            DeviceProximityManager.shared().remove(proximityManagerIndex)
        }
        
        if let playbackItem = self.playbackItem {
            switch playbackItem {
                case .audio:
                    playbackItem.pause()
                case let .instantVideo(node):
                    node.setSoundEnabled(false)
                    self.overlayMediaManager.controller?.removeNode(node, customTransition: false)
            }
        }
    }
    
    func control(_ action: SharedMediaPlayerControlAction) {
        if let bgMix = self.bgMix {
            // A control from the user or the system starts the count of failures in a row again.
            self.bgMixFailureStreak.reset()
            switch action {
                case .next:
                    bgMix.play()
                    self.playlist.control(.next)
                    return
                case .previous:
                    let threshold: Double = 5.0
                    if let playbackStateValue = self._playbackStateValue, case let .item(item) = playbackStateValue, item.status.duration > threshold, item.status.timestamp > threshold {
                        bgMix.seek(0.0)
                    } else {
                        bgMix.play()
                        self.playlist.control(.previous)
                    }
                    return
                case let .playback(playbackAction):
                    switch playbackAction {
                        case .play:
                            bgMix.play()
                        case .pause:
                            bgMix.pause()
                        case .togglePlayPause:
                            bgMix.togglePlayPause()
                    }
                    return
                case let .seek(timestamp):
                    bgMix.seek(timestamp)
                    return
                default:
                    break
            }
        }
        switch action {
            case .next:
                self.scheduledPlaybackAction = .play
                self.playlist.control(.next)
            case .previous:
                let threshold: Double = 5.0
                if let playbackStateValue = self._playbackStateValue, case let .item(item) = playbackStateValue, item.status.duration > threshold, item.status.timestamp > threshold {
                    self.control(.seek(0.0))
                } else {
                    self.scheduledPlaybackAction = .play
                    self.playlist.control(.previous)
                }
            case let .playback(action):
                if let playbackItem = self.playbackItem {
                    switch action {
                        case .play:
                            BGMixPlayer.stopSharedEngineIfRunning()
                            playbackItem.play()
                        case .pause:
                            playbackItem.pause()
                        case .togglePlayPause:
                            BGMixPlayer.stopSharedEngineIfRunning()
                            playbackItem.togglePlayPause()
                    }
                } else {
                    self.scheduledPlaybackAction = action
                }
            case let .seek(timestamp):
                if let playbackItem = self.playbackItem {
                    playbackItem.seek(timestamp)
                } else {
                    self.scheduledPlaybackAction = .play
                    self.scheduledStartTime = timestamp
                }
            case let .setOrder(order):
                self.playlist.setOrder(order)
            case let .setLooping(looping):
                self.playlist.setLooping(looping)
            case let .setBaseRate(baseRate):
                self.playbackRate = baseRate
                if let playbackItem = self.playbackItem {
                    let rateValue: Double = baseRate.doubleValue
                    switch playbackItem {
                        case let .audio(player):
                            player.setBaseRate(rateValue)
                        case let .instantVideo(node):
                            node.setBaseRate(rateValue)
                    }
                }
        }
    }
    
    func stop() {
        if let bgMix = self.bgMix {
            bgMix.pause()
            return
        }
        if let playbackItem = self.playbackItem {
            switch playbackItem {
                case let .audio(player):
                    player.pause()
                case let .instantVideo(node):
                    node.setSoundEnabled(false)
            }
        }
    }
    
    /// Only non-Telegram music sources (.yandexTrack, .localFile) require BG Mix; standard Telegram
    /// audio files always use Telegram's native MediaPlayer for full codec/streaming parity.
    private static func requiresBGMix(for item: SharedMediaPlaylistItem?) -> Bool {
        guard let source = item?.playbackData?.source else {
            return false
        }
        switch source {
            case .yandexTrack, .localFile:
                return true
            case .telegramFile:
                return false
        }
    }

    private func ensureBGMixBackend() -> SharedMediaBGMixBackend {
        if let existing = self.bgMix {
            return existing
        }
        let backend = SharedMediaBGMixBackend(engine: self.engine, audioSession: self.audioSession)
        backend.onItemEnded = { [weak self] in
            self?.handleBGMixItemEnded()
        }
        backend.onAdvanceRequested = { [weak self] in
            self?.playlist.control(.next)
        }
        backend.onCurrentItemFailed = { [weak self] failure in
            self?.handleBGMixItemFailed(failure)
        }
        self.bgMix = backend
        return backend
    }

    /// A BG Mix track has finished. As on the MediaPlayer path, a repeated item plays again, and anything else moves
    /// the playlist on.
    private func handleBGMixItemEnded() {
        switch self.playlist.looping {
            case .item:
                self.bgMix?.restartCurrent()
            default:
                self.advanceBGMix()
        }
    }

    /// BG Mix could not play the current item. The playlist moves on. A refusal that holds for the whole Yandex account
    /// stops playback at once, because the next Yandex track would fail the same way. After a run of other failures
    /// playback stops at the limit, so a list of broken items does not cycle forever.
    private func handleBGMixItemFailed(_ failure: SharedMediaBGMixFailure) {
        let failureCount = self.bgMixFailureStreak.recordFailure()
        Logger.shared.log("SharedMediaPlayer", "BG Mix could not play the current item (\(failureCount) in a row): \(failure)")
        if SharedMediaPlayer.stopsBGMixAtOnce(failure) || failureCount >= BGMixFailureStreak.limit {
            self.bgMixFailureStreak.reset()
            self.bgMix?.pause()
            return
        }
        self.advanceBGMix()
    }

    /// A refusal that holds for the whole account: nobody is signed in to Yandex, or the account has no subscription.
    private static func stopsBGMixAtOnce(_ failure: SharedMediaBGMixFailure) -> Bool {
        guard case let .yandex(error) = failure else {
            return false
        }
        switch error {
        case .notSignedIn, .subscriptionRequired:
            return true
        default:
            return false
        }
    }

    /// Moves the playlist on and remembers the item it leaves. If the list settles on that same item, short of its end, BG Mix
    /// starts it again (see `applyBGMixState`): a single item on repeat-all, or a failed item that gets another try.
    private func advanceBGMix() {
        self.bgMixAdvanceFrom = self.stateValue?.item?.stableId
        self.playlist.control(.next)
    }

    /// Publishes the playlist state while BG Mix plays it. The item's status comes from BG Mix in the same shape
    /// MediaPlayer gives, so the lock screen and the player UI see no difference.
    private func applyBGMixState(_ state: SharedMediaPlaylistState, bgMix: SharedMediaBGMixBackend) {
        if self.currentPlayedToEnd != state.playedToEnd {
            self.currentPlayedToEnd = state.playedToEnd
            if state.playedToEnd {
                bgMix.pause()
                self.playedToEnd?()
            }
        }
        let stateChanged = self.stateValue != state
        self.stateValue = state
        var restartsItem = false
        if let advanceFrom = self.bgMixAdvanceFrom, !state.loading {
            self.bgMixAdvanceFrom = nil
            // The list settled on the item it left, short of its end: a single item on repeat-all, or a failed item that gets
            // another try. Its state does not change, so BG Mix starts the item here.
            restartsItem = BGMixPlaybackRecovery.shouldRestartItem(
                advanceFrom: advanceFrom,
                currentItem: state.item?.stableId,
                isLoading: state.loading,
                playedToEnd: state.playedToEnd
            )
        }
        if stateChanged {
            // Repeat-one queues only the current item, so AutoMix cannot crossfade on into another track.
            bgMix.update(current: state.item, next: state.looping == .item ? nil : state.nextItem)
        }
        if restartsItem {
            bgMix.restartCurrent()
        }
        guard stateChanged else {
            return
        }

        let playlistId = self.playlist.id
        let playlistLocation = self.playlist.location
        let playerIndex = self.playerIndex
        if let item = state.item {
            self.playbackStateValue.set(bgMix.status(for: item)
            |> map { itemStatus in
                return .item(SharedMediaPlayerItemPlaybackState(playlistId: playlistId, playlistLocation: playlistLocation, item: item, previousItem: state.previousItem, nextItem: state.nextItem, status: itemStatus, order: state.order, looping: state.looping, playerIndex: playerIndex))
            })
            self.markItemAsPlayedDisposable.set((bgMix.status(for: item)
            |> filter { status in
                if case .playing = status.status {
                    return true
                } else {
                    return false
                }
            }
            |> take(1)
            |> deliverOnMainQueue).startStrict(next: { [weak self] _ in
                // An item that plays starts the count of failures in a row again.
                self?.bgMixFailureStreak.reset()
                self?.playlist.onItemPlaybackStarted(item)
            }))
        } else {
            if state.loading {
                self.playbackStateValue.set(.single(.loading))
            } else {
                self.playbackStateValue.set(.single(nil))
            }
        }
    }

    private func updatePrefetchItems(item: SharedMediaPlaylistItem?, previousItem: SharedMediaPlaylistItem?, nextItem: SharedMediaPlaylistItem?, ordering: MusicPlaybackSettingsOrder) {
        var prefetchItems: (SharedMediaPlaybackDataSource, SharedMediaPlaybackDataSource)?
        if let playbackData = item?.playbackData {
            switch ordering {
                case .regular:
                    if let previousItem = previousItem?.playbackData {
                        prefetchItems = (playbackData.source, previousItem.source)
                    }
                case .reversed:
                    if let nextItem = nextItem?.playbackData {
                        prefetchItems = (playbackData.source, nextItem.source)
                    }
                case .random:
                    break
            }
        }
        if self.currentPrefetchItems?.0 != prefetchItems?.0 || self.currentPrefetchItems?.1 != prefetchItems?.1 {
            self.currentPrefetchItems = prefetchItems
            if let (current, next) = prefetchItems {
                let fetchedCurrentSignal: Signal<Never, NoError>
                let fetchedNextSignal: Signal<Never, NoError>
                switch current {
                    case let .telegramFile(file, _, _):
                        fetchedCurrentSignal = self.engine.resources.data(resource: EngineMediaResource(file.media.resource))
                        |> mapToSignal { data -> Signal<Void, NoError> in
                            if data.isComplete {
                                return .single(Void())
                            } else {
                                return .complete()
                            }
                        }
                        |> take(1)
                        |> ignoreValues
                    case .yandexTrack, .localFile:
                        // A Yandex track or a local file has no Telegram resource to fetch. BG Mix asks for its file when it needs it.
                        fetchedCurrentSignal = .complete()
                }
                switch next {
                    case let .telegramFile(file, _, _):
                        fetchedNextSignal = self.engine.resources.fetch(reference: file.resourceReference(file.media.resource), userLocation: .other, userContentType: .audio)
                        |> ignoreValues
                        |> `catch` { _ -> Signal<Never, NoError> in
                            return .complete()
                        }
                    case .yandexTrack, .localFile:
                        // Same as the current track: the file is asked for when BG Mix needs it.
                        fetchedNextSignal = .complete()
                }
                self.prefetchDisposable.set((fetchedCurrentSignal |> then(fetchedNextSignal)).startStrict())
            } else {
                self.prefetchDisposable.set(nil)
            }
        }
    }
}
