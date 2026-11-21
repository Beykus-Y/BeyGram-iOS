import Foundation
import UIKit
import SwiftSignalKit
import TelegramPresentationData
import BeyGramDesign
import BeyGramKit

/// Docked mini-player bar shown at the bottom of Music Center and Yandex Music screens.
/// Displays album art, real track title & artist, BPM badge, thin progress bar, and Play/Pause + Next controls.
public final class BeyGramMiniPlayerBar: UIView {
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private var progressWidthConstraint: NSLayoutConstraint?

    private let artworkView = UIImageView()
    private let titleLabel = BeyGramTypography.makeLabel(style: .subheadline, weight: .semibold, lines: 1)
    private let subtitleLabel = BeyGramTypography.makeLabel(style: .caption1, weight: .regular, lines: 1)
    private let bpmBadge = BeyGramPillBadge()
    private let playPauseButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)

    private var stateDisposable: Disposable?
    private var currentCoverURL: URL?
    private var currentPalette: BeyGramThemePalette?
    private var onOpenPlayer: (() -> Void)?

    public init(onOpenPlayer: @escaping () -> Void) {
        self.onOpenPlayer = onOpenPlayer
        super.init(frame: .zero)
        self.setupUI()
        self.observeSession()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.stateDisposable?.dispose()
    }

    private func setupUI() {
        self.layer.cornerRadius = 16
        self.layer.cornerCurve = .continuous
        self.layer.borderWidth = 1.0 / UIScreen.main.scale
        self.clipsToBounds = true

        self.progressTrack.translatesAutoresizingMaskIntoConstraints = false
        self.progressFill.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.progressTrack)
        self.progressTrack.addSubview(self.progressFill)

        self.artworkView.contentMode = .scaleAspectFill
        self.artworkView.layer.cornerRadius = 10
        self.artworkView.layer.cornerCurve = .continuous
        self.artworkView.clipsToBounds = true
        self.artworkView.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [self.titleLabel, self.subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 1

        self.playPauseButton.addTarget(self, action: #selector(self.playPauseTapped), for: .touchUpInside)
        self.nextButton.setImage(UIImage(systemName: "forward.fill"), for: .normal)
        self.nextButton.addTarget(self, action: #selector(self.nextTapped), for: .touchUpInside)

        self.playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        self.nextButton.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [self.artworkView, textStack, self.bpmBadge, self.playPauseButton, self.nextButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(row)

        let widthConstraint = self.progressFill.widthAnchor.constraint(equalToConstant: 0)
        self.progressWidthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            self.progressTrack.topAnchor.constraint(equalTo: self.topAnchor),
            self.progressTrack.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.progressTrack.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.progressTrack.heightAnchor.constraint(equalToConstant: 2.5),

            self.progressFill.topAnchor.constraint(equalTo: self.progressTrack.topAnchor),
            self.progressFill.bottomAnchor.constraint(equalTo: self.progressTrack.bottomAnchor),
            self.progressFill.leadingAnchor.constraint(equalTo: self.progressTrack.leadingAnchor),
            widthConstraint,

            self.artworkView.widthAnchor.constraint(equalToConstant: 42),
            self.artworkView.heightAnchor.constraint(equalToConstant: 42),
            self.playPauseButton.widthAnchor.constraint(equalToConstant: 36),
            self.playPauseButton.heightAnchor.constraint(equalToConstant: 36),
            self.nextButton.widthAnchor.constraint(equalToConstant: 32),
            self.nextButton.heightAnchor.constraint(equalToConstant: 32),

            row.topAnchor.constraint(equalTo: self.progressTrack.bottomAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8),
            row.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -10)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.barTapped))
        self.addGestureRecognizer(tap)
        self.isHidden = true
    }

    private func observeSession() {
        self.stateDisposable = (BeyGramMusicSession.shared.stateSignal
        |> deliverOnMainQueue).start(next: { [weak self] state in
            self?.update(with: state)
        })
    }

    public func apply(theme: PresentationTheme) {
        self.currentPalette = BeyGramThemePalette(theme: theme)
        self.update(with: BeyGramMusicSession.shared.currentState)
    }

    private func update(with state: BeyGramMusicState) {
        guard let track = state.currentTrack ?? state.queue.first else {
            self.isHidden = true
            return
        }
        self.isHidden = false
        guard let palette = self.currentPalette else { return }

        self.backgroundColor = palette.cardBackground
        self.layer.borderColor = palette.separator.withAlphaComponent(0.35).cgColor
        self.progressTrack.backgroundColor = palette.separator.withAlphaComponent(0.25)
        self.progressFill.backgroundColor = palette.accent

        self.titleLabel.text = track.title
        self.titleLabel.textColor = palette.primaryText
        if state.isTransitionActive {
            self.subtitleLabel.text = "BG Mix · Crossfading…"
            self.subtitleLabel.textColor = palette.accent
        } else if let artist = track.artist, !artist.isEmpty {
            self.subtitleLabel.text = artist
            self.subtitleLabel.textColor = palette.secondaryText
        } else {
            self.subtitleLabel.text = state.isPlaying ? "Playing" : "Paused"
            self.subtitleLabel.textColor = palette.secondaryText
        }

        if let bpm = track.bpm {
            self.bpmBadge.isHidden = false
            self.bpmBadge.configure(text: "\(bpm) BPM", textColor: palette.accent, backgroundColor: palette.accentSoft)
        } else {
            self.bpmBadge.isHidden = true
        }

        let playIcon = UIImage(systemName: state.isPlaying ? "pause.fill" : "play.fill")
        self.playPauseButton.setImage(playIcon, for: .normal)
        self.playPauseButton.tintColor = palette.primaryText
        self.playPauseButton.accessibilityLabel = state.isPlaying ? "Pause" : "Play"
        self.nextButton.tintColor = palette.primaryText
        self.nextButton.accessibilityLabel = "Next track"

        let ratio: CGFloat = state.duration > 0 ? min(1.0, max(0.0, CGFloat(state.position / state.duration))) : 0.0
        self.progressWidthConstraint?.constant = self.bounds.width * ratio

        if self.currentCoverURL != track.coverURL {
            self.currentCoverURL = track.coverURL
            self.artworkView.image = UIImage(systemName: "music.note")
            self.artworkView.tintColor = palette.accent
            self.artworkView.backgroundColor = palette.accentSoft
            BeyGramTrackMetadataStore.shared.loadCover(url: track.coverURL) { [weak self] image in
                guard let self, self.currentCoverURL == track.coverURL, let image else { return }
                UIView.transition(with: self.artworkView, duration: 0.22, options: .transitionCrossDissolve) {
                    self.artworkView.image = image
                }
            }
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let state = BeyGramMusicSession.shared.currentState
        let ratio: CGFloat = state.duration > 0 ? min(1.0, max(0.0, CGFloat(state.position / state.duration))) : 0.0
        self.progressWidthConstraint?.constant = self.bounds.width * ratio
    }

    @objc private func playPauseTapped() {
        BeyGramMusicSession.shared.togglePlayPause()
    }

    @objc private func nextTapped() {
        if BeyGramMusicSession.shared.currentWaveState.isActive {
            BeyGramMusicSession.shared.skipWaveTrack()
        } else {
            BeyGramMusicSession.shared.next()
        }
    }

    @objc private func barTapped() {
        self.onOpenPlayer?()
    }
}
