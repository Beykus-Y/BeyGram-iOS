import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import UniformTypeIdentifiers
import BeyGramDesign
import BeyGramKit
import BeyGramMedia
import BeyGramYandexMusic

/// Full-screen Now Playing, Queue, Lyrics, and BG Mix Player sheet.
public final class BeyGramNowPlayingViewController: BeyGramScrollViewController, UIDocumentPickerDelegate {
    private enum ActiveTab: Int {
        case player = 0
        case queue = 1
        case lyrics = 2
    }

    private var activeTab: ActiveTab = .player
    private var stateDisposable: Disposable?
    private var currentState = BeyGramMusicSession.shared.currentState
    private var currentCoverURL: URL?
    private var isScrubbing = false
    private var loadedLyricsTrackId: String?
    private var lyricsText: String?
    private var isLoadingLyrics = false

    // Segmented Top Bar
    private let tabControl = UISegmentedControl(items: ["Player", "Queue", "Lyrics"])

    // Player Panel
    private let playerContainer = UIStackView()
    private let artworkCard = UIView()
    private let artworkImageView = UIImageView()
    private let trackTitleLabel = BeyGramTypography.makeLabel(style: .title2, weight: .bold, lines: 2)
    private let trackArtistLabel = BeyGramTypography.makeLabel(style: .body, weight: .medium, lines: 1)
    private let badgesStack = UIStackView()
    private let bpmBadge = BeyGramPillBadge()
    private let mixBadge = BeyGramPillBadge()

    private let seekSlider = UISlider()
    private let elapsedLabel = BeyGramTypography.makeLabel(style: .caption1, weight: .medium, lines: 1)
    private let remainingLabel = BeyGramTypography.makeLabel(style: .caption1, weight: .medium, lines: 1)

    private let playPauseButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let mixSettingsButton = UIButton(type: .system)
    private let sleepTimerButton = UIButton(type: .system)
    private var sleepTimerDisposable: Disposable?
    private var sleepTimerState: BeyGramSleepTimerState = BeyGramMusicSession.shared.sleepTimerState
    private let errorLabel = BeyGramTypography.makeLabel(style: .footnote, weight: .medium, lines: 0)

    // Queue Panel
    private let queueContainer = UIStackView()
    private let addFilesButton = BeyGramActionButton(style: .secondary)
    private let clearQueueButton = BeyGramActionButton(style: .destructive)
    private let queueListStack = UIStackView()

    // Lyrics Panel
    private let lyricsCard = BeyGramCardView(spacing: 8)
    private let lyricsLabel = BeyGramTypography.makeLabel(style: .body, weight: .regular, lines: 0)

    public override init(context: AccountContext) {
        super.init(context: context)
    }

    deinit {
        self.stateDisposable?.dispose()
        self.sleepTimerDisposable?.dispose()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.setupUI()
        self.stateDisposable = (BeyGramMusicSession.shared.stateSignal
        |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self else { return }
            self.currentState = state
            self.render()
        })
    }

    public override var keyCommands: [UIKeyCommand]? {
        var commands = super.keyCommands ?? []
        commands.append(UIKeyCommand(input: " ", modifierFlags: [], action: #selector(self.playPauseTapped)))
        commands.append(UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: .command, action: #selector(self.nextTapped)))
        return commands
    }

    private func setupUI() {
        self.tabControl.selectedSegmentIndex = 0
        self.tabControl.addTarget(self, action: #selector(self.tabChanged), for: .valueChanged)
        self.stackView.addArrangedSubview(self.tabControl)

        // Player Container
        self.playerContainer.axis = .vertical
        self.playerContainer.spacing = 16
        self.stackView.addArrangedSubview(self.playerContainer)

        self.artworkCard.layer.cornerRadius = 22
        self.artworkCard.layer.cornerCurve = .continuous
        self.artworkCard.clipsToBounds = true
        self.artworkCard.translatesAutoresizingMaskIntoConstraints = false
        self.artworkImageView.contentMode = .scaleAspectFill
        self.artworkImageView.translatesAutoresizingMaskIntoConstraints = false
        self.artworkCard.addSubview(self.artworkImageView)
        NSLayoutConstraint.activate([
            self.artworkCard.heightAnchor.constraint(equalTo: self.artworkCard.widthAnchor, multiplier: 0.85),
            self.artworkImageView.topAnchor.constraint(equalTo: self.artworkCard.topAnchor),
            self.artworkImageView.bottomAnchor.constraint(equalTo: self.artworkCard.bottomAnchor),
            self.artworkImageView.leadingAnchor.constraint(equalTo: self.artworkCard.leadingAnchor),
            self.artworkImageView.trailingAnchor.constraint(equalTo: self.artworkCard.trailingAnchor)
        ])
        self.playerContainer.addArrangedSubview(self.artworkCard)

        self.trackTitleLabel.textAlignment = .center
        self.trackArtistLabel.textAlignment = .center
        let titleStack = UIStackView(arrangedSubviews: [self.trackTitleLabel, self.trackArtistLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 4
        self.playerContainer.addArrangedSubview(titleStack)

        self.badgesStack.axis = .horizontal
        self.badgesStack.alignment = .center
        self.badgesStack.spacing = 8
        let badgeWrapper = UIStackView(arrangedSubviews: [UIView(), self.bpmBadge, self.mixBadge, UIView()])
        badgeWrapper.axis = .horizontal
        badgeWrapper.spacing = 8
        badgeWrapper.distribution = .equalCentering
        self.playerContainer.addArrangedSubview(badgeWrapper)

        self.seekSlider.addTarget(self, action: #selector(self.sliderBegan), for: .touchDown)
        self.seekSlider.addTarget(self, action: #selector(self.sliderEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        self.playerContainer.addArrangedSubview(self.seekSlider)

        let timeRow = UIStackView(arrangedSubviews: [self.elapsedLabel, UIView(), self.remainingLabel])
        timeRow.axis = .horizontal
        self.playerContainer.addArrangedSubview(timeRow)

        self.playPauseButton.layer.cornerRadius = 32
        self.playPauseButton.layer.cornerCurve = .continuous
        self.playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        self.playPauseButton.addTarget(self, action: #selector(self.playPauseTapped), for: .touchUpInside)

        self.nextButton.setImage(UIImage(systemName: "forward.end.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)), for: .normal)
        self.nextButton.addTarget(self, action: #selector(self.nextTapped), for: .touchUpInside)

        self.mixSettingsButton.setImage(UIImage(systemName: "slider.horizontal.3", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)), for: .normal)
        self.mixSettingsButton.addTarget(self, action: #selector(self.mixSettingsTapped), for: .touchUpInside)

        self.sleepTimerButton.setImage(UIImage(systemName: "moon.zzz", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)), for: .normal)
        self.sleepTimerButton.addTarget(self, action: #selector(self.sleepTimerTapped), for: .touchUpInside)
        self.sleepTimerDisposable = (BeyGramMusicSession.shared.sleepTimerSignal
        |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self else { return }
            self.sleepTimerState = state
            if self.isViewLoaded {
                self.render()
            }
        })

        NSLayoutConstraint.activate([
            self.playPauseButton.widthAnchor.constraint(equalToConstant: 64),
            self.playPauseButton.heightAnchor.constraint(equalToConstant: 64),
            self.nextButton.widthAnchor.constraint(equalToConstant: 48),
            self.nextButton.heightAnchor.constraint(equalToConstant: 48),
            self.mixSettingsButton.widthAnchor.constraint(equalToConstant: 48),
            self.mixSettingsButton.heightAnchor.constraint(equalToConstant: 48),
            self.sleepTimerButton.widthAnchor.constraint(equalToConstant: 48),
            self.sleepTimerButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        let controlsRow = UIStackView(arrangedSubviews: [UIView(), self.mixSettingsButton, self.playPauseButton, self.nextButton, self.sleepTimerButton, UIView()])
        controlsRow.axis = .horizontal
        controlsRow.alignment = .center
        controlsRow.spacing = 24
        controlsRow.distribution = .equalCentering
        self.playerContainer.addArrangedSubview(controlsRow)

        self.errorLabel.textAlignment = .center
        self.playerContainer.addArrangedSubview(self.errorLabel)

        // Queue Container
        self.queueContainer.axis = .vertical
        self.queueContainer.spacing = 12
        self.stackView.addArrangedSubview(self.queueContainer)

        self.addFilesButton.addTarget(self, action: #selector(self.addFilesTapped), for: .touchUpInside)
        self.clearQueueButton.addTarget(self, action: #selector(self.clearQueueTapped), for: .touchUpInside)
        let queueActions = UIStackView(arrangedSubviews: [self.addFilesButton, self.clearQueueButton])
        queueActions.axis = .horizontal
        queueActions.spacing = 8
        queueActions.distribution = .fillEqually
        self.queueContainer.addArrangedSubview(queueActions)

        self.queueListStack.axis = .vertical
        self.queueListStack.spacing = 8
        self.queueContainer.addArrangedSubview(self.queueListStack)

        // Lyrics Container
        self.lyricsCard.contentStack.addArrangedSubview(self.lyricsLabel)
        self.stackView.addArrangedSubview(self.lyricsCard)
    }

    public override func applyPresentationData(_ presentationData: PresentationData) {
        super.applyPresentationData(presentationData)
        self.render()
    }

    private func render() {
        let lang = self.presentationData.strings.primaryComponent.languageCode
        let isRu = lang.lowercased().hasPrefix("ru")
        let l10n = BeyGramL10n.shared
        let palette = BeyGramThemePalette(theme: self.presentationData.theme)

        self.title = l10n.string(.musicTitle, languageCode: lang)

        self.tabControl.setTitle(BeyGramAndroidStrings.shared.string("player_pane_title", languageCode: lang), forSegmentAt: 0)
        self.tabControl.setTitle("\(BeyGramAndroidStrings.shared.string("player_queue", languageCode: lang)) (\(self.currentState.queue.count))", forSegmentAt: 1)
        self.tabControl.setTitle(isRu ? "Текст" : "Lyrics", forSegmentAt: 2)

        self.playerContainer.isHidden = self.activeTab != .player
        self.queueContainer.isHidden = self.activeTab != .queue
        self.lyricsCard.isHidden = self.activeTab != .lyrics

        let track = self.currentState.currentTrack ?? self.currentState.queue.first

        // Artwork & Spring Scale
        self.artworkCard.backgroundColor = palette.accentSoft
        if self.currentCoverURL != track?.coverURL {
            self.currentCoverURL = track?.coverURL
            self.artworkImageView.image = UIImage(systemName: "music.note.list")
            self.artworkImageView.tintColor = palette.accent
            self.artworkImageView.contentMode = .scaleAspectFit
            BeyGramTrackMetadataStore.shared.loadCover(url: track?.coverURL) { [weak self] image in
                guard let self, self.currentCoverURL == track?.coverURL, let image else { return }
                self.artworkImageView.contentMode = .scaleAspectFill
                UIView.transition(with: self.artworkImageView, duration: 0.25, options: .transitionCrossDissolve) {
                    self.artworkImageView.image = image
                }
            }
        }
        let targetScale: CGFloat = self.currentState.isPlaying ? 1.0 : 0.93
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.3, options: [.allowUserInteraction]) {
            self.artworkCard.transform = CGAffineTransform(scaleX: targetScale, y: targetScale)
        }

        // Title & Artist
        self.trackTitleLabel.text = track?.title ?? (isRu ? "Ничего не играет" : "Nothing playing")
        self.trackTitleLabel.textColor = palette.primaryText
        self.trackArtistLabel.text = track?.artist ?? (isRu ? "Выберите трек в Яндекс.Музыке или библиотеке" : "Pick a track in Yandex Music or Library")
        self.trackArtistLabel.textColor = palette.secondaryText

        if let bpm = track?.bpm {
            self.bpmBadge.isHidden = false
            self.bpmBadge.configure(text: "\(bpm) BPM", textColor: palette.accent, backgroundColor: palette.accentSoft)
        } else {
            self.bpmBadge.isHidden = true
        }
        if self.currentState.isTransitionActive {
            self.mixBadge.isHidden = false
            self.mixBadge.configure(text: isRu ? "BG Mix · Переход" : "BG Mix · Crossfade", textColor: palette.success, backgroundColor: palette.successSoft)
        } else if self.currentState.isPreparingNext {
            self.mixBadge.isHidden = false
            self.mixBadge.configure(text: isRu ? "Подготовка…" : "Preparing next…", textColor: palette.warning, backgroundColor: palette.warningSoft)
        } else {
            self.mixBadge.isHidden = true
        }

        // Slider & Time
        self.seekSlider.minimumTrackTintColor = palette.accent
        self.seekSlider.maximumTrackTintColor = palette.separator.withAlphaComponent(0.35)
        let duration = max(0, self.currentState.duration)
        let position = min(duration, max(0, self.currentState.position))
        if !self.isScrubbing {
            self.seekSlider.maximumValue = Float(max(duration, 1.0))
            self.seekSlider.value = Float(position)
            self.seekSlider.isEnabled = duration > 0 && !self.currentState.isTransitionActive
        }
        self.elapsedLabel.text = self.formatTime(position)
        self.elapsedLabel.textColor = palette.secondaryText
        self.remainingLabel.text = duration > 0 ? "-\(self.formatTime(max(0, duration - position)))" : "0:00"
        self.remainingLabel.textColor = palette.secondaryText

        // Controls
        self.playPauseButton.backgroundColor = palette.accent
        self.playPauseButton.tintColor = palette.onAccent
        let iconName = self.currentState.isPlaying ? "pause.fill" : "play.fill"
        self.playPauseButton.setImage(UIImage(systemName: iconName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .bold)), for: .normal)
        self.playPauseButton.accessibilityLabel = self.currentState.isPlaying ? "Pause" : "Play"
        self.nextButton.tintColor = palette.primaryText
        self.nextButton.isEnabled = !self.currentState.queue.isEmpty
        self.mixSettingsButton.tintColor = palette.accent
        self.sleepTimerButton.tintColor = self.sleepTimerState == .off ? palette.primaryText : palette.accent
        self.sleepTimerButton.accessibilityLabel = BeyGramAndroidStrings.shared.string("player_sleep_timer", languageCode: self.presentationData.strings.primaryComponent.languageCode)

        if let err = self.currentState.lastError, !err.isEmpty {
            self.errorLabel.isHidden = false
            self.errorLabel.text = err
            self.errorLabel.textColor = palette.destructive
        } else {
            self.errorLabel.isHidden = true
        }

        // Queue Tab
        self.addFilesButton.configure(title: isRu ? "Добавить файлы" : "Add Audio Files", style: .secondary, palette: palette)
        self.clearQueueButton.configure(title: isRu ? "Очистить" : "Clear", style: .destructive, palette: palette, isEnabled: !self.currentState.queue.isEmpty)
        for subview in self.queueListStack.arrangedSubviews {
            self.queueListStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        if self.currentState.queue.isEmpty {
            let empty = BeyGramTypography.makeLabel(style: .subheadline, weight: .regular, lines: 0)
            empty.text = isRu ? "Очередь пуста. Добавьте аудиофайлы или включите трек в Яндекс.Музыке." : "Queue is empty. Add audio files or play from Yandex Music."
            empty.textColor = palette.secondaryText
            empty.textAlignment = .center
            self.queueListStack.addArrangedSubview(empty)
        } else {
            let card = BeyGramCardView(spacing: 0, insets: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
            card.apply(palette: palette)
            for (idx, item) in self.currentState.queue.enumerated() {
                let row = BeyGramRowView()
                let statusText: String
                let statusColor: UIColor
                switch item.status {
                case .pending:
                    statusText = isRu ? "В очереди" : "Queued"
                    statusColor = palette.secondaryText
                case let .preparing(p):
                    statusText = "\(Int(p * 100))%"
                    statusColor = palette.warning
                case .ready:
                    statusText = isRu ? "Готов" : "Ready"
                    statusColor = palette.secondaryText
                case .playing:
                    statusText = isRu ? "Играет" : "Playing"
                    statusColor = palette.accent
                case .played:
                    statusText = isRu ? "Проигран" : "Played"
                    statusColor = palette.secondaryText
                case .failed:
                    statusText = isRu ? "Ошибка" : "Failed"
                    statusColor = palette.destructive
                }
                let sub = [item.artist, item.bpm.map { "\($0) BPM" }].compactMap { $0 }.joined(separator: " · ")
                row.configure(
                    iconName: item.status == .playing ? "speaker.wave.2.fill" : "music.note",
                    iconTint: item.status == .playing ? palette.accent : palette.secondaryText,
                    title: item.title,
                    subtitle: sub.isEmpty ? nil : sub,
                    value: statusText,
                    valueColor: statusColor,
                    showSeparator: idx < self.currentState.queue.count - 1,
                    palette: palette,
                    onTap: { [weak self] in
                        self?.confirmRemoveTrack(item)
                    }
                )
                card.contentStack.addArrangedSubview(row)
            }
            self.queueListStack.addArrangedSubview(card)
        }

        // Lyrics Tab
        self.lyricsCard.apply(palette: palette)
        if self.activeTab == .lyrics {
            self.loadLyricsIfNeeded(track: track, isRu: isRu)
        }
        self.lyricsLabel.textColor = palette.primaryText
        if self.isLoadingLyrics {
            self.lyricsLabel.text = isRu ? "Загрузка текста песни…" : "Loading lyrics…"
            self.lyricsLabel.textColor = palette.secondaryText
        } else if let lyricsText, !lyricsText.isEmpty {
            self.lyricsLabel.text = lyricsText
        } else {
            self.lyricsLabel.text = isRu ? "Текст песни недоступен для этого трека." : "Lyrics are not available for this track."
            self.lyricsLabel.textColor = palette.secondaryText
        }
    }

    private func loadLyricsIfNeeded(track: BeyGramMusicTrack?, isRu: Bool) {
        guard let trackId = track?.yandexTrackId else {
            self.loadedLyricsTrackId = nil
            self.lyricsText = nil
            return
        }
        if self.loadedLyricsTrackId == trackId || self.isLoadingLyrics {
            return
        }
        self.loadedLyricsTrackId = trackId
        self.isLoadingLyrics = true
        BGYandexRuntime.shared.lyrics(trackId: trackId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoadingLyrics = false
                switch result {
                case let .success(lyrics):
                    if !lyrics.lines.isEmpty {
                        self.lyricsText = lyrics.lines.map { $0.text }.joined(separator: "\n")
                    } else {
                        self.lyricsText = lyrics.plainText
                    }
                    if let holder = lyrics.copyrightHolder, !holder.isEmpty {
                        self.lyricsText = (self.lyricsText ?? "") + "\n\n\(holder)"
                    }
                case .failure:
                    self.lyricsText = nil
                }
                self.render()
            }
        }
    }

    private func confirmRemoveTrack(_ track: BeyGramMusicTrack) {
        let isRu = self.presentationData.strings.primaryComponent.languageCode.lowercased().hasPrefix("ru")
        let sheet = ActionSheetController(presentationData: self.presentationData)
        sheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: track.title),
                ActionSheetButtonItem(title: isRu ? "Удалить из очереди" : "Remove from queue", color: .destructive, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    BeyGramMusicSession.shared.removeTrack(id: track.id)
                })
            ]),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: self.presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        self.present(sheet, in: .window(.root))
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @objc private func tabChanged() {
        self.activeTab = ActiveTab(rawValue: self.tabControl.selectedSegmentIndex) ?? .player
        self.render()
    }

    @objc private func sliderBegan() {
        self.isScrubbing = true
    }

    @objc private func sliderEnded() {
        self.isScrubbing = false
        _ = BeyGramMusicSession.shared.seek(to: TimeInterval(self.seekSlider.value))
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

    @objc private func sleepTimerTapped() {
        let languageCode = self.presentationData.strings.primaryComponent.languageCode
        let l10n = BeyGramAndroidStrings.shared
        let session = BeyGramMusicSession.shared
        let sheet = ActionSheetController(presentationData: self.presentationData)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: l10n.string("player_sleep_timer", languageCode: languageCode))]
        for minutes in BeyGramSleepTimer.presetMinutes {
            items.append(ActionSheetButtonItem(title: l10n.string("player_sleep_in_minutes", languageCode: languageCode, minutes), action: { [weak sheet] in
                sheet?.dismissAnimated()
                session.setSleepTimer(minutes: minutes)
            }))
        }
        items.append(ActionSheetButtonItem(title: l10n.string("player_sleep_until_track_end", languageCode: languageCode), action: { [weak sheet] in
            sheet?.dismissAnimated()
            session.setSleepTimerUntilTrackEnd()
        }))
        if self.sleepTimerState != .off {
            items.append(ActionSheetButtonItem(title: l10n.string("player_sleep_extend", languageCode: languageCode, BeyGramSleepTimer.extensionMinutes), action: { [weak sheet] in
                sheet?.dismissAnimated()
                session.extendSleepTimer()
            }))
            items.append(ActionSheetButtonItem(title: l10n.string("player_sleep_cancel_plain", languageCode: languageCode), color: .destructive, action: { [weak sheet] in
                sheet?.dismissAnimated()
                session.cancelSleepTimer()
            }))
        }
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: self.presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })
            ])
        ])
        self.present(sheet, in: .window(.root))
    }

    @objc private func mixSettingsTapped() {
        (self.navigationController as? NavigationController)?.pushViewController(beyGramMixSettingsController(context: self.context))
    }

    @objc private func addFilesTapped() {
        let types: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        self.present(picker, animated: true, completion: nil)
    }

    @objc private func clearQueueTapped() {
        BeyGramMusicSession.shared.clearQueue()
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        BeyGramMusicSession.shared.addTracks(urls: urls)
    }
}
