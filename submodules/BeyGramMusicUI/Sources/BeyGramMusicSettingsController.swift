import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import UniformTypeIdentifiers
import BeyGramDesign
import BeyGramKit
import BeyGramMusicLibrary
import BeyGramYandexMusic

private final class BeyGramMusicCenterViewControllerImpl: BeyGramScrollViewController, UIDocumentPickerDelegate {
    private var stateDisposable: Disposable?
    private var musicState = BeyGramMusicSession.shared.currentState
    private let libraryStore: BGMusicLibraryStore

    private let waveHeroCard = BeyGramCardView(spacing: 10)
    private let waveHeroTitle = BeyGramTypography.makeLabel(style: .title3, weight: .bold, lines: 1)
    private let waveHeroSubtitle = BeyGramTypography.makeLabel(style: .subheadline, weight: .regular, lines: 0)
    private let waveHeroButton = BeyGramActionButton(style: .primary)

    private let sourcesHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let sourcesCard = BeyGramCardView(spacing: 0, insets: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
    private let yandexRow = BeyGramRowView()
    private let bgMixRow = BeyGramRowView()
    private let bgWaveRow = BeyGramRowView()
    private let mixSettingsRow = BeyGramRowView()

    private let libraryHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let libraryCard = BeyGramCardView(spacing: 10)
    private let libraryListStack = UIStackView()
    private let importBgMusicButton = BeyGramActionButton(style: .secondary)

    private let recentHeader = BeyGramTypography.makeLabel(style: .footnote, weight: .semibold, lines: 1)
    private let recentCard = BeyGramCardView(spacing: 0, insets: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))

    private var miniPlayerBar: BeyGramMiniPlayerBar!

    override init(context: AccountContext) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let libRoot = base.appendingPathComponent("beygram/music-library/\(context.account.peerId.toInt64())", isDirectory: true)
        self.libraryStore = BGMusicLibraryStore(rootDirectory: libRoot)
        super.init(context: context)
    }

    deinit {
        self.stateDisposable?.dispose()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupUI()
        self.stateDisposable = (BeyGramMusicSession.shared.stateSignal
        |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self else { return }
            self.musicState = state
            self.render()
        })
    }

    private func setupUI() {
        // My Wave Hero Card
        self.waveHeroCard.contentStack.addArrangedSubview(self.waveHeroTitle)
        self.waveHeroCard.contentStack.addArrangedSubview(self.waveHeroSubtitle)
        self.waveHeroButton.addTarget(self, action: #selector(self.openYandexTapped), for: .touchUpInside)
        self.waveHeroCard.contentStack.addArrangedSubview(self.waveHeroButton)
        self.stackView.addArrangedSubview(self.waveHeroCard)

        // Sources
        self.stackView.addArrangedSubview(self.sourcesHeader)
        self.sourcesCard.contentStack.addArrangedSubview(self.yandexRow)
        self.sourcesCard.contentStack.addArrangedSubview(self.bgMixRow)
        self.sourcesCard.contentStack.addArrangedSubview(self.bgWaveRow)
        self.sourcesCard.contentStack.addArrangedSubview(self.mixSettingsRow)
        self.stackView.addArrangedSubview(self.sourcesCard)

        // Local Library & .bgmusic
        self.stackView.addArrangedSubview(self.libraryHeader)
        self.libraryListStack.axis = .vertical
        self.libraryListStack.spacing = 0
        self.libraryCard.contentStack.addArrangedSubview(self.libraryListStack)
        self.importBgMusicButton.addTarget(self, action: #selector(self.importBgMusicTapped), for: .touchUpInside)
        self.libraryCard.contentStack.addArrangedSubview(self.importBgMusicButton)
        self.stackView.addArrangedSubview(self.libraryCard)

        // Recent Tracks
        self.stackView.addArrangedSubview(self.recentHeader)
        self.stackView.addArrangedSubview(self.recentCard)

        // Docked Mini-Player
        self.miniPlayerBar = BeyGramMiniPlayerBar(onOpenPlayer: { [weak self] in
            guard let self else { return }
            (self.navigationController as? NavigationController)?.pushViewController(BeyGramNowPlayingViewController(context: self.context))
        })
        self.miniPlayerBar.translatesAutoresizingMaskIntoConstraints = false
        self.displayNode.view.addSubview(self.miniPlayerBar)
        NSLayoutConstraint.activate([
            self.miniPlayerBar.leadingAnchor.constraint(equalTo: self.displayNode.view.leadingAnchor, constant: 12),
            self.miniPlayerBar.trailingAnchor.constraint(equalTo: self.displayNode.view.trailingAnchor, constant: -12),
            self.miniPlayerBar.bottomAnchor.constraint(equalTo: self.displayNode.view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])

        self.render()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let extraBottom: CGFloat = self.miniPlayerBar.isHidden ? 16 : 82
        self.scrollView.contentInset.bottom = layout.intrinsicInsets.bottom + extraBottom
        self.scrollView.scrollIndicatorInsets = self.scrollView.contentInset
    }

    override func applyPresentationData(_ presentationData: PresentationData) {
        super.applyPresentationData(presentationData)
        self.render()
    }

    private func render() {
        let lang = self.presentationData.strings.primaryComponent.languageCode
        let isRu = lang.lowercased().hasPrefix("ru")
        let l10n = BeyGramL10n.shared
        let palette = BeyGramThemePalette(theme: self.presentationData.theme)

        self.title = l10n.string(.musicTitle, languageCode: lang)
        self.miniPlayerBar?.apply(theme: self.presentationData.theme)

        // Hero Card
        self.waveHeroCard.apply(palette: palette)
        let ymService = BGYandexRuntime.shared
        let ymSignedIn: Bool
        let ymAccountLabel: String
        switch ymService.accountState {
        case .signedOut:
            ymSignedIn = false
            ymAccountLabel = isRu ? "Не подключено" : "Not signed in"
        case let .signedIn(account):
            ymSignedIn = true
            let plus = account.hasPlus ? " · Plus" : ""
            ymAccountLabel = account.displayName + plus
        }

        self.waveHeroTitle.text = isRu ? "Моя волна и Музыка" : "My Wave & Music"
        self.waveHeroTitle.textColor = palette.primaryText
        self.waveHeroSubtitle.text = ymSignedIn
            ? (isRu ? "Непрерывный поток рекомендаций, поиск, лайки и плейлисты Яндекс.Музыки." : "Continuous recommendations, search, likes, and playlists via Yandex Music.")
            : (isRu ? "Подключите Яндекс.Музыку для Моей волны, поиска и текстов песен." : "Connect Yandex Music for My Wave, search, and synced lyrics.")
        self.waveHeroSubtitle.textColor = palette.secondaryText
        self.waveHeroButton.configure(
            title: ymSignedIn ? (isRu ? "Открыть Мою волну" : "Open My Wave") : (isRu ? "Подключить Яндекс.Музыку" : "Connect Yandex Music"),
            style: .primary,
            palette: palette
        )

        // Sources
        self.sourcesHeader.text = (isRu ? "ИСТОЧНИКИ И ПЛЕЕР" : "SOURCES & PLAYER").uppercased()
        self.sourcesHeader.textColor = palette.secondaryText
        self.sourcesCard.apply(palette: palette)

        self.yandexRow.configure(
            iconName: "music.quarternote.3",
            iconTint: palette.accent,
            title: l10n.string(.yandexTitle, languageCode: lang),
            subtitle: ymAccountLabel,
            showsChevron: true,
            showSeparator: true,
            palette: palette,
            onTap: { [weak self] in self?.openYandexTapped() }
        )

        let queueCount = self.musicState.queue.count
        let mixSub: String
        if let current = self.musicState.currentTrack {
            mixSub = current.title + (current.bpm.map { " · \($0) BPM" } ?? "")
        } else if queueCount > 0 {
            mixSub = isRu ? "Треков в очереди: \(queueCount)" : "\(queueCount) tracks in queue"
        } else {
            mixSub = isRu ? "Открыть плеер и очередь" : "Open full player & queue"
        }
        self.bgMixRow.configure(
            iconName: "play.square.stack.fill",
            iconTint: palette.accent,
            title: l10n.string(.bgMixTitle, languageCode: lang),
            subtitle: mixSub,
            showsChevron: true,
            showSeparator: true,
            palette: palette,
            onTap: { [weak self] in
                guard let self else { return }
                (self.navigationController as? NavigationController)?.pushViewController(BeyGramNowPlayingViewController(context: self.context))
            }
        )

        self.bgWaveRow.configure(
            iconName: "dot.radiowaves.left.and.right",
            iconTint: palette.accent,
            title: l10n.string(.bgWaveTitle, languageCode: lang),
            subtitle: isRu ? "Совместное прослушивание (P2P)" : "Listen together over P2P",
            showsChevron: true,
            showSeparator: true,
            palette: palette,
            onTap: { [weak self] in
                guard let self else { return }
                (self.navigationController as? NavigationController)?.pushViewController(beyGramWaveController(context: self.context))
            }
        )

        self.mixSettingsRow.configure(
            iconName: "slider.horizontal.3",
            iconTint: palette.secondaryText,
            title: l10n.string(.bgMixSettingsTitle, languageCode: lang),
            subtitle: isRu ? "Кроссфейды, Bass Swap и BG Beat" : "Crossfades, Bass Swap & BG Beat",
            showsChevron: true,
            showSeparator: false,
            palette: palette,
            onTap: { [weak self] in
                guard let self else { return }
                (self.navigationController as? NavigationController)?.pushViewController(beyGramMixSettingsController(context: self.context))
            }
        )

        // Library
        self.libraryHeader.text = (isRu ? "МЕДИАТЕКА И .BGMUSIC" : "LIBRARY & .BGMUSIC").uppercased()
        self.libraryHeader.textColor = palette.secondaryText
        self.libraryCard.apply(palette: palette)

        for subview in self.libraryListStack.arrangedSubviews {
            self.libraryListStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        let playlists = self.libraryStore.load().playlists
        if playlists.isEmpty {
            let empty = BeyGramTypography.makeLabel(style: .footnote, weight: .regular, lines: 0)
            empty.text = isRu ? "Локальных плейлистов пока нет. Вы можете импортировать архив .bgmusic." : "No local playlists yet. You can import a .bgmusic archive."
            empty.textColor = palette.secondaryText
            self.libraryListStack.addArrangedSubview(empty)
        } else {
            for (idx, playlist) in playlists.enumerated() {
                let row = BeyGramRowView()
                row.configure(
                    iconName: "music.note.list",
                    iconTint: palette.accent,
                    title: playlist.title,
                    subtitle: isRu ? "Треков: \(playlist.tracks.count)" : "\(playlist.tracks.count) tracks",
                    showSeparator: idx < playlists.count - 1,
                    palette: palette,
                    onTap: { [weak self] in
                        self?.playLocalPlaylist(playlist)
                    }
                )
                self.libraryListStack.addArrangedSubview(row)
            }
        }
        self.importBgMusicButton.configure(
            title: isRu ? "Импортировать .bgmusic" : "Import .bgmusic",
            style: .secondary,
            palette: palette
        )

        // Recent
        self.recentHeader.text = (isRu ? "НЕДАВНИЕ ТРЕКИ" : "RECENTLY PLAYED").uppercased()
        self.recentHeader.textColor = palette.secondaryText
        self.recentCard.apply(palette: palette)
        for subview in self.recentCard.contentStack.arrangedSubviews {
            self.recentCard.contentStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        if self.musicState.recentTracks.isEmpty {
            let row = BeyGramRowView()
            row.configure(
                iconName: "clock",
                iconTint: palette.secondaryText,
                title: l10n.string(.musicEmptyLibrary, languageCode: lang),
                showSeparator: false,
                palette: palette
            )
            self.recentCard.contentStack.addArrangedSubview(row)
        } else {
            let items = Array(self.musicState.recentTracks.prefix(10))
            for (idx, track) in items.enumerated() {
                let row = BeyGramRowView()
                row.configure(
                    iconName: track.status == .playing ? "speaker.wave.2.fill" : "music.note",
                    iconTint: track.status == .playing ? palette.accent : palette.secondaryText,
                    title: track.title,
                    subtitle: track.artist,
                    value: track.bpm.map { "\($0) BPM" },
                    showsChevron: true,
                    showSeparator: idx < items.count - 1,
                    palette: palette,
                    onTap: { [weak self] in
                        guard let self else { return }
                        (self.navigationController as? NavigationController)?.pushViewController(BeyGramNowPlayingViewController(context: self.context))
                    }
                )
                self.recentCard.contentStack.addArrangedSubview(row)
            }
        }
    }

    private func playLocalPlaylist(_ playlist: BGMusicPlaylist) {
        let urls = playlist.tracks.compactMap { track -> URL? in
            let candidate = self.libraryStore.rootDirectory.appendingPathComponent(track.fileName)
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        }
        if !urls.isEmpty {
            BeyGramMusicSession.shared.addTracks(urls: urls)
            BeyGramMusicSession.shared.play()
            (self.navigationController as? NavigationController)?.pushViewController(BeyGramNowPlayingViewController(context: self.context))
        }
    }

    @objc private func openYandexTapped() {
        (self.navigationController as? NavigationController)?.pushViewController(beyGramYandexMusicController(context: self.context))
    }

    @objc private func importBgMusicTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip, .data, .item], asCopy: true)
        picker.delegate = self
        self.present(picker, animated: true, completion: nil)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let _ = try? self.libraryStore.importPlaylist(from: url)
        self.render()
    }
}

public func beyGramMusicSettingsController(context: AccountContext) -> ViewController {
    return BeyGramMusicCenterViewControllerImpl(context: context)
}
