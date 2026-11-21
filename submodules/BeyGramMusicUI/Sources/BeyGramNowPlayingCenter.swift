import Foundation
import UIKit
import MediaPlayer

/// Publishes the active audible BeyGram Music (Yandex / BG Mix) track to iOS Lock Screen & Control Center
/// (`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`) while avoiding ownership conflicts with Telegram's `MediaManager`.
///
/// Ownership rules:
/// - Claims system Now Playing & remote commands ONLY when `BGMixPlayer` owns the audio session
///   (`managesAudioSession == true`) and has a confirmed track on the master deck.
/// - Stores every `MPRemoteCommandCenter` target token and removes ONLY its own targets on relinquish,
///   never interfering with Telegram's `MediaManager` handlers.
/// - Clears `MPNowPlayingInfoCenter.default().nowPlayingInfo` only when relinquishing its own session.
final class BeyGramNowPlayingCenter {
    private weak var session: BeyGramMusicSession?
    private var ownsRemoteControls: Bool = false
    private var relinquishedForExternalAudio: Bool = false
    private var commandTokens: [(MPRemoteCommand, Any)] = []
    private var activeTrackId: UInt64?
    private var activeCoverURL: URL?
    private var cachedArtwork: MPMediaItemArtwork?
    private var baseInfo: [String: Any] = [:]

    init(session: BeyGramMusicSession) {
        self.session = session
    }

    deinit {
        self.relinquish()
    }

    func update(state: BeyGramMusicState, managesAudioSession: Bool, waveActive: Bool) {
        if state.isPlaying {
            self.relinquishedForExternalAudio = false
        }
        guard managesAudioSession,
              !self.relinquishedForExternalAudio,
              let track = state.currentTrack,
              (state.isPlaying || (state.isPaused && self.ownsRemoteControls)) else {
            if self.ownsRemoteControls {
                self.relinquish(clearSystemInfo: !self.relinquishedForExternalAudio)
            }
            return
        }

        if !self.ownsRemoteControls {
            self.registerRemoteCommands()
            self.ownsRemoteControls = true
        }

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = waveActive || state.nextTrack != nil
        commandCenter.previousTrackCommand.isEnabled = state.duration > 0
        commandCenter.changePlaybackPositionCommand.isEnabled = state.duration > 0 && !state.isTransitionActive

        let trackChanged = self.activeTrackId != track.id
        if trackChanged {
            self.activeTrackId = track.id
            if self.activeCoverURL != track.coverURL {
                self.activeCoverURL = track.coverURL
                self.cachedArtwork = nil
                if let coverURL = track.coverURL {
                    let expectedTrackId = track.id
                    BeyGramTrackMetadataStore.shared.loadCover(url: coverURL) { [weak self] image in
                        guard let self,
                              self.ownsRemoteControls,
                              self.activeTrackId == expectedTrackId,
                              let image else {
                            return
                        }
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        self.cachedArtwork = artwork
                        self.baseInfo[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = self.baseInfo
                    }
                }
            }
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyPlaybackDuration: NSNumber(value: max(0.0, state.duration)),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: NSNumber(value: max(0.0, state.position)),
            MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: state.isPlaying ? 1.0 : 0.0)
        ]
        if let artist = track.artist, !artist.isEmpty {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let artwork = self.cachedArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        self.baseInfo = info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func relinquishForExternalAudio() {
        self.relinquishedForExternalAudio = true
        self.relinquish(clearSystemInfo: false)
    }

    func relinquish(clearSystemInfo: Bool = true) {
        guard self.ownsRemoteControls else {
            return
        }
        self.ownsRemoteControls = false
        for (command, token) in self.commandTokens {
            command.removeTarget(token)
        }
        self.commandTokens.removeAll()
        self.activeTrackId = nil
        self.activeCoverURL = nil
        self.cachedArtwork = nil
        self.baseInfo.removeAll()
        if clearSystemInfo {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        let playToken = center.playCommand.addTarget { [weak self] _ in
            guard let session = self?.session else { return .commandFailed }
            session.play()
            return .success
        }
        let pauseToken = center.pauseCommand.addTarget { [weak self] _ in
            guard let session = self?.session else { return .commandFailed }
            session.pause()
            return .success
        }
        let toggleToken = center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let session = self?.session else { return .commandFailed }
            session.togglePlayPause()
            return .success
        }
        let nextToken = center.nextTrackCommand.addTarget { [weak self] _ in
            guard let session = self?.session else { return .commandFailed }
            if session.currentWaveState.isActive {
                session.skipWaveTrack()
            } else {
                session.next()
            }
            return .success
        }
        let prevToken = center.previousTrackCommand.addTarget { [weak self] _ in
            guard let session = self?.session else { return .commandFailed }
            _ = session.seek(to: 0.0)
            return .success
        }
        let seekToken = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let session = self?.session,
                  let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            _ = session.seek(to: posEvent.positionTime)
            return .success
        }
        self.commandTokens = [
            (center.playCommand, playToken),
            (center.pauseCommand, pauseToken),
            (center.togglePlayPauseCommand, toggleToken),
            (center.nextTrackCommand, nextToken),
            (center.previousTrackCommand, prevToken),
            (center.changePlaybackPositionCommand, seekToken)
        ]
    }
}
