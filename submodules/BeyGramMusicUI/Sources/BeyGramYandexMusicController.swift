import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import BeyGramDesign
import BeyGramKit
import BeyGramYandexMusic

private final class BeyGramYandexMusicViewControllerImpl: BeyGramScrollViewController, UITextFieldDelegate {
    private enum SectionTab: Int {
        case myWave = 0
        case search = 1
        case likes = 2
        case playlists = 3
    }

    private let service = BGYandexRuntime.shared
    private var activeTab: SectionTab = .myWave
    private var accepted: Bool = UserDefaults.standard.bool(forKey: "beygram.yandex.consentAccepted")
    private var waitingCode: String?
    private var verificationUrl: String?
    private var codeCopied: Bool = false
    private var authFailure: String?

    private var waveStateDisposable: Disposable?
    private var waveState = BeyGramMusicSession.shared.currentWaveState

    private var searchQuery: String = ""
    private var searchResults: [BGYandexTrack] = []
    private var searchLoading: Bool = false
    private var searchError: String?

    private var likedTracks: [BGYandexTrack] = []
    private var likesLoaded: Bool = false
    private var likesLoading: Bool = false

    private var playlists: [BGYandexPlaylist] = []
    private var playlistsLoaded: Bool = false
    private var playlistsLoading: Bool = false
    private var selectedPlaylist: BGYandexPlaylist?
    private var selectedPlaylistTracks: [BGYandexTrack] = []

    private var musicStateDisposable: Disposable?
    private var musicState = BeyGramMusicSession.shared.currentState

    // Onboarding / Auth UI
    private let authCard = BeyGramCardView(spacing: 12)
    private let authTitleLabel = BeyGramTypography.makeLabel(style: .title3, weight: .bold, lines: 0)
    private let authBodyLabel = BeyGramTypography.makeLabel(style: .subheadline, weight: .regular, lines: 0)
    private let codeLabel = BeyGramTypography.makeLabel(style: .title1, weight: .bold, lines: 1)
    private let authPrimaryButton = BeyGramActionButton(style: .primary)
    private let authSecondaryButton = BeyGramActionButton(style: .secondary)
    private let authErrorLabel = BeyGramTypography.makeLabel(style: .footnote, weight: .medium, lines: 0)

    // Signed-in Hub UI
    private let profileCard = BeyGramCardView(spacing: 8)
    private let profileTitleLabel = BeyGramTypography.makeLabel(style: .headline, weight: .semibold, lines: 1)
    private let profileBadge = BeyGramPillBadge()
    private let signOutButton = UIButton(type: .system)

    private let tabControl = UISegmentedControl(items: ["My Wave", "Search", "Likes", "Playlists"])

    // My Wave Card
    private let waveCard = BeyGramCardView(spacing: 12)
    private let waveCoverView = UIImageView()
    private let waveTrackTitle = BeyGramTypography.makeLabel(style: .title3, weight: .bold, lines: 2)
    private let waveTrackArtist = BeyGramTypography.makeLabel(style: .subheadline, weight: .medium, lines: 1)
    private let wavePlayButton = BeyGramActionButton(style: .primary)
    private let waveNextButton = BeyGramActionButton(style: .secondary)
    private let waveLikeButton = BeyGramActionButton(style: .secondary)
    private let waveStatusLabel = BeyGramTypography.makeLabel(style: .footnote, weight: .regular, lines: 0)

    // Search Card
    private let searchContainer = UIStackView()
    private let searchField = UITextField()
    private let searchButton = BeyGramActionButton(style: .primary)
    private let tracksListCard = BeyGramCardView(spacing: 0, insets: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
    private let listEmptyLabel = BeyGramTypography.makeLabel(style: .subheadline, weight: .regular, lines: 0)

    private var miniPlayerBar: BeyGramMiniPlayerBar!
    private var loadedWaveCoverURL: URL?

    deinit {
        self.musicStateDisposable?.dispose()
        self.waveStateDisposable?.dispose()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupUI()
        self.service.onAccountStateChange = { [weak self] _ in
            DispatchQueue.main.async {
                self?.render()
            }
        }
        self.musicStateDisposable = (BeyGramMusicSession.shared.stateSignal
        |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self else { return }
            self.musicState = state
            self.render()
        })
        self.waveStateDisposable = (BeyGramMusicSession.shared.waveStateSignal
        |> deliverOnMainQueue).start(next: { [weak self] waveState in
            guard let self else { return }
            self.waveState = waveState
            self.render()
        })
        self.render()
    }

    private func setupUI() {
        // Auth Card
        self.codeLabel.textAlignment = .center
        self.authPrimaryButton.addTarget(self, action: #selector(self.authPrimaryTapped), for: .touchUpInside)
        self.authSecondaryButton.addTarget(self, action: #selector(self.authSecondaryTapped), for: .touchUpInside)
        self.authCard.contentStack.addArrangedSubview(self.authTitleLabel)
        self.authCard.contentStack.addArrangedSubview(self.authBodyLabel)
        self.authCard.contentStack.addArrangedSubview(self.codeLabel)
        self.authCard.contentStack.addArrangedSubview(self.authErrorLabel)
        self.authCard.contentStack.addArrangedSubview(self.authPrimaryButton)
        self.authCard.contentStack.addArrangedSubview(self.authSecondaryButton)
        self.stackView.addArrangedSubview(self.authCard)

        // Profile Card
        self.signOutButton.titleLabel?.font = BeyGramTypography.font(style: .footnote, weight: .semibold)
        self.signOutButton.addTarget(self, action: #selector(self.signOutTapped), for: .touchUpInside)
        let profileRow = UIStackView(arrangedSubviews: [self.profileTitleLabel, self.profileBadge, UIView(), self.signOutButton])
        profileRow.axis = .horizontal
        profileRow.alignment = .center
        profileRow.spacing = 8
        self.profileCard.contentStack.addArrangedSubview(profileRow)
        self.stackView.addArrangedSubview(self.profileCard)

        // Segmented Tabs
        self.tabControl.selectedSegmentIndex = 0
        self.tabControl.addTarget(self, action: #selector(self.tabChanged), for: .valueChanged)
        self.stackView.addArrangedSubview(self.tabControl)

        // My Wave Card
        self.waveCoverView.contentMode = .scaleAspectFill
        self.waveCoverView.layer.cornerRadius = 16
        self.waveCoverView.layer.cornerCurve = .continuous
        self.waveCoverView.clipsToBounds = true
        self.waveCoverView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.waveCoverView.heightAnchor.constraint(equalToConstant: 180)
        ])
        self.waveTrackTitle.textAlignment = .center
        self.waveTrackArtist.textAlignment = .center
        self.wavePlayButton.addTarget(self, action: #selector(self.wavePlayTapped), for: .touchUpInside)
        self.waveNextButton.addTarget(self, action: #selector(self.waveNextTapped), for: .touchUpInside)
        self.waveLikeButton.addTarget(self, action: #selector(self.waveLikeTapped), for: .touchUpInside)
        let waveActions = UIStackView(arrangedSubviews: [self.wavePlayButton, self.waveNextButton, self.waveLikeButton])
        waveActions.axis = .horizontal
        waveActions.spacing = 8
        waveActions.distribution = .fillEqually
        self.waveStatusLabel.textAlignment = .center

        self.waveCard.contentStack.addArrangedSubview(self.waveCoverView)
        self.waveCard.contentStack.addArrangedSubview(self.waveTrackTitle)
        self.waveCard.contentStack.addArrangedSubview(self.waveTrackArtist)
        self.waveCard.contentStack.addArrangedSubview(waveActions)
        self.waveCard.contentStack.addArrangedSubview(self.waveStatusLabel)
        self.stackView.addArrangedSubview(self.waveCard)

        // Search Row
        self.searchContainer.axis = .horizontal
        self.searchContainer.spacing = 8
        self.searchField.borderStyle = .roundedRect
        self.searchField.returnKeyType = .search
        self.searchField.clearButtonMode = .whileEditing
        self.searchField.font = BeyGramTypography.font(style: .body)
        self.searchField.adjustsFontForContentSizeCategory = true
        self.searchField.delegate = self
        self.searchButton.setContentHuggingPriority(.required, for: .horizontal)
        self.searchButton.addTarget(self, action: #selector(self.searchTapped), for: .touchUpInside)
        self.searchContainer.addArrangedSubview(self.searchField)
        self.searchContainer.addArrangedSubview(self.searchButton)
        self.stackView.addArrangedSubview(self.searchContainer)

        // List Card
        self.listEmptyLabel.textAlignment = .center
        self.stackView.addArrangedSubview(self.tracksListCard)
        self.stackView.addArrangedSubview(self.listEmptyLabel)

        // Mini-Player Bar
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

        self.title = l10n.string(.yandexTitle, languageCode: lang)
        self.miniPlayerBar?.apply(theme: self.presentationData.theme)

        let signedInAccount: BGYandexAccount?
        switch self.service.accountState {
        case .signedOut:
            signedInAccount = nil
        case let .signedIn(account):
            signedInAccount = account
        }

        let showHub = self.accepted && self.service.credentials.isConfigured && signedInAccount != nil
        self.authCard.isHidden = showHub
        self.profileCard.isHidden = !showHub
        self.tabControl.isHidden = !showHub
        self.waveCard.isHidden = !showHub || self.activeTab != .myWave
        self.searchContainer.isHidden = !showHub || self.activeTab != .search
        self.tracksListCard.isHidden = !showHub || self.activeTab == .myWave
        self.listEmptyLabel.isHidden = !showHub || self.activeTab == .myWave

        if !showHub {
            self.renderAuth(palette: palette, l10n: l10n, lang: lang, isRu: isRu)
            return
        }

        guard let account = signedInAccount else { return }
        self.profileCard.apply(palette: palette)
        self.profileTitleLabel.text = account.displayName
        self.profileTitleLabel.textColor = palette.primaryText
        self.profileBadge.configure(
            text: account.hasPlus ? "Plus" : "Free",
            textColor: account.hasPlus ? palette.success : palette.warning,
            backgroundColor: account.hasPlus ? palette.successSoft : palette.warningSoft
        )
        self.signOutButton.setTitle(l10n.string(.yandexSignOut, languageCode: lang), for: .normal)
        self.signOutButton.tintColor = palette.destructive

        self.tabControl.setTitle(isRu ? "Моя волна" : "My Wave", forSegmentAt: 0)
        self.tabControl.setTitle(isRu ? "Поиск" : "Search", forSegmentAt: 1)
        self.tabControl.setTitle(isRu ? "Лайки" : "Likes", forSegmentAt: 2)
        self.tabControl.setTitle(isRu ? "Плейлисты" : "Playlists", forSegmentAt: 3)

        switch self.activeTab {
        case .myWave:
            self.renderMyWave(palette: palette, isRu: isRu)
        case .search:
            self.renderSearch(palette: palette, isRu: isRu)
        case .likes:
            self.loadLikesIfNeeded()
            self.renderTrackList(
                tracks: self.likedTracks,
                loading: self.likesLoading,
                emptyText: isRu ? "Любимые треки не найдены." : "No liked tracks found.",
                palette: palette,
                isRu: isRu
            )
        case .playlists:
            self.loadPlaylistsIfNeeded()
            self.renderPlaylists(palette: palette, isRu: isRu)
        }
    }

    private func renderAuth(palette: BeyGramThemePalette, l10n: BeyGramL10n, lang: String, isRu: Bool) {
        self.authCard.apply(palette: palette)
        self.authTitleLabel.textColor = palette.primaryText
        self.authBodyLabel.textColor = palette.secondaryText
        self.codeLabel.textColor = palette.accent

        if let err = self.authFailure {
            self.authErrorLabel.isHidden = false
            self.authErrorLabel.text = err
            self.authErrorLabel.textColor = palette.destructive
        } else {
            self.authErrorLabel.isHidden = true
        }

        if !self.accepted {
            self.authTitleLabel.text = l10n.string(.yandexWarningTitle, languageCode: lang)
            self.authBodyLabel.text = l10n.string(.yandexWarningBody, languageCode: lang)
            self.codeLabel.isHidden = true
            self.authPrimaryButton.configure(title: l10n.string(.yandexAcceptConsent, languageCode: lang), style: .primary, palette: palette)
            self.authSecondaryButton.isHidden = true
        } else if !self.service.credentials.isConfigured {
            self.authTitleLabel.text = l10n.string(.yandexNotConfiguredTitle, languageCode: lang)
            self.authBodyLabel.text = l10n.string(.yandexNotConfiguredBody, languageCode: lang)
            self.codeLabel.isHidden = true
            self.authPrimaryButton.isHidden = true
            self.authSecondaryButton.isHidden = true
        } else if let code = self.waitingCode {
            self.authTitleLabel.text = l10n.string(.yandexWaitingTitle, languageCode: lang)
            self.authBodyLabel.text = l10n.string(.yandexOpenVerification, languageCode: lang)
            self.codeLabel.isHidden = false
            self.codeLabel.text = code
            self.authPrimaryButton.isHidden = false
            self.authPrimaryButton.configure(
                title: self.codeCopied ? l10n.string(.commonCopied, languageCode: lang) : l10n.string(.yandexCopyCode, languageCode: lang),
                style: .primary,
                palette: palette
            )
            self.authSecondaryButton.isHidden = false
            self.authSecondaryButton.configure(title: isRu ? "Открыть ссылку" : "Open Verification Page", style: .secondary, palette: palette)
        } else {
            self.authTitleLabel.text = l10n.string(.yandexTitle, languageCode: lang)
            self.authBodyLabel.text = isRu ? "Войдите в аккаунт Яндекс, чтобы слушать Мою волну, лайки и плейлисты." : "Sign in to your Yandex account for My Wave, likes, and playlists."
            self.codeLabel.isHidden = true
            self.authPrimaryButton.isHidden = false
            self.authPrimaryButton.configure(title: l10n.string(.yandexSignIn, languageCode: lang), style: .primary, palette: palette)
            self.authSecondaryButton.isHidden = true
        }
    }

    private func renderMyWave(palette: BeyGramThemePalette, isRu: Bool) {
        self.waveCard.apply(palette: palette)
        let track = self.waveState.currentTrack
        self.waveTrackTitle.text = track?.title ?? (isRu ? "Моя волна" : "My Wave")
        self.waveTrackTitle.textColor = palette.primaryText
        let artistJoined = track?.artists.joined(separator: ", ") ?? ""
        self.waveTrackArtist.text = artistJoined.isEmpty ? (isRu ? "Персональный поток музыки" : "Your personal continuous radio") : artistJoined
        self.waveTrackArtist.textColor = palette.secondaryText

        let coverURL = track.flatMap { BGYandexTrackInfo(track: $0).coverURL }
        if self.loadedWaveCoverURL != coverURL {
            self.loadedWaveCoverURL = coverURL
            self.waveCoverView.image = UIImage(systemName: "waveform.circle.fill")
            self.waveCoverView.tintColor = palette.accent
            self.waveCoverView.backgroundColor = palette.accentSoft
            self.waveCoverView.contentMode = .scaleAspectFit
            BeyGramTrackMetadataStore.shared.loadCover(url: coverURL) { [weak self] image in
                guard let self, self.loadedWaveCoverURL == coverURL, let image else { return }
                self.waveCoverView.contentMode = .scaleAspectFill
                UIView.transition(with: self.waveCoverView, duration: 0.25, options: .transitionCrossDissolve) {
                    self.waveCoverView.image = image
                }
            }
        }

        let isThisPlaying = self.musicState.isPlaying && (track == nil || self.musicState.currentTrack?.yandexTrackId == track?.trackId)
        self.wavePlayButton.configure(
            title: track == nil ? (isRu ? "Запустить" : "Start") : (isThisPlaying ? (isRu ? "Пауза" : "Pause") : (isRu ? "Играть" : "Play")),
            style: .primary,
            palette: palette,
            isLoading: self.waveState.isLoading
        )
        self.waveNextButton.configure(title: isRu ? "Дальше" : "Skip", style: .secondary, palette: palette, isEnabled: track != nil)
        self.waveLikeButton.configure(
            title: self.waveState.isLiked ? (isRu ? "В любимом" : "Liked") : (isRu ? "Нравится" : "Like"),
            style: .secondary,
            palette: palette,
            isEnabled: track != nil
        )

        if let waveError = self.waveState.error {
            self.waveStatusLabel.isHidden = false
            self.waveStatusLabel.text = waveError
            self.waveStatusLabel.textColor = palette.destructive
        } else if self.waveState.upcomingCount > 0 {
            self.waveStatusLabel.isHidden = false
            self.waveStatusLabel.text = isRu ? "Впереди ещё треков: \(self.waveState.upcomingCount) (автоподгрузка)" : "\(self.waveState.upcomingCount) tracks queued ahead (auto-refill)"
            self.waveStatusLabel.textColor = palette.secondaryText
        } else {
            self.waveStatusLabel.isHidden = true
        }
    }

    private func renderSearch(palette: BeyGramThemePalette, isRu: Bool) {
        self.searchField.placeholder = isRu ? "Трек, исполнитель или альбом…" : "Track, artist, or album…"
        self.searchField.textColor = palette.primaryText
        self.searchField.backgroundColor = palette.cardBackground
        self.searchButton.configure(title: isRu ? "Найти" : "Search", style: .primary, palette: palette, isLoading: self.searchLoading)

        if let err = self.searchError {
            self.renderTrackList(tracks: [], loading: false, emptyText: err, palette: palette, isRu: isRu)
        } else {
            self.renderTrackList(
                tracks: self.searchResults,
                loading: self.searchLoading,
                emptyText: isRu ? "Введите запрос для поиска." : "Enter a query to search Yandex Music.",
                palette: palette,
                isRu: isRu
            )
        }
    }

    private func renderTrackList(tracks: [BGYandexTrack], loading: Bool, emptyText: String, palette: BeyGramThemePalette, isRu: Bool) {
        self.tracksListCard.apply(palette: palette)
        for subview in self.tracksListCard.contentStack.arrangedSubviews {
            self.tracksListCard.contentStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        if loading {
            self.tracksListCard.isHidden = true
            self.listEmptyLabel.isHidden = false
            self.listEmptyLabel.text = isRu ? "Загрузка…" : "Loading…"
            self.listEmptyLabel.textColor = palette.secondaryText
            return
        }
        if tracks.isEmpty {
            self.tracksListCard.isHidden = true
            self.listEmptyLabel.isHidden = false
            self.listEmptyLabel.text = emptyText
            self.listEmptyLabel.textColor = palette.secondaryText
            return
        }
        self.tracksListCard.isHidden = false
        self.listEmptyLabel.isHidden = true
        for (idx, track) in tracks.prefix(40).enumerated() {
            BeyGramTrackMetadataStore.shared.registerYandexTrack(track)
            let row = BeyGramRowView()
            let totalSec = Int(track.durationMs / 1000)
            let durationText = totalSec > 0 ? String(format: "%d:%02d", totalSec / 60, totalSec % 60) : nil
            let artistText = track.artists.joined(separator: ", ")
            row.configure(
                iconName: "music.note",
                iconTint: palette.accent,
                title: track.title,
                subtitle: artistText.isEmpty ? nil : artistText,
                value: durationText,
                showSeparator: idx < min(tracks.count, 40) - 1,
                palette: palette,
                onTap: { [weak self] in
                    self?.playSingleYandexTrack(track)
                }
            )
            self.tracksListCard.contentStack.addArrangedSubview(row)
        }
    }

    private func renderPlaylists(palette: BeyGramThemePalette, isRu: Bool) {
        if let selected = self.selectedPlaylist {
            self.tracksListCard.apply(palette: palette)
            for subview in self.tracksListCard.contentStack.arrangedSubviews {
                self.tracksListCard.contentStack.removeArrangedSubview(subview)
                subview.removeFromSuperview()
            }
            let backRow = BeyGramRowView()
            backRow.configure(
                iconName: "chevron.left",
                iconTint: palette.accent,
                title: isRu ? "Назад к плейлистам (\(selected.title))" : "Back to Playlists (\(selected.title))",
                showSeparator: !self.selectedPlaylistTracks.isEmpty,
                palette: palette,
                onTap: { [weak self] in
                    self?.selectedPlaylist = nil
                    self?.selectedPlaylistTracks = []
                    self?.render()
                }
            )
            self.tracksListCard.contentStack.addArrangedSubview(backRow)
            for (idx, track) in self.selectedPlaylistTracks.prefix(40).enumerated() {
                BeyGramTrackMetadataStore.shared.registerYandexTrack(track)
                let row = BeyGramRowView()
                let artistText = track.artists.joined(separator: ", ")
                row.configure(
                    iconName: "music.note",
                    iconTint: palette.accent,
                    title: track.title,
                    subtitle: artistText.isEmpty ? nil : artistText,
                    showSeparator: idx < min(self.selectedPlaylistTracks.count, 40) - 1,
                    palette: palette,
                    onTap: { [weak self] in
                        self?.playSingleYandexTrack(track)
                    }
                )
                self.tracksListCard.contentStack.addArrangedSubview(row)
            }
            self.tracksListCard.isHidden = false
            self.listEmptyLabel.isHidden = true
            return
        }

        self.tracksListCard.apply(palette: palette)
        for subview in self.tracksListCard.contentStack.arrangedSubviews {
            self.tracksListCard.contentStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        if self.playlistsLoading {
            self.tracksListCard.isHidden = true
            self.listEmptyLabel.isHidden = false
            self.listEmptyLabel.text = isRu ? "Загрузка плейлистов…" : "Loading playlists…"
            self.listEmptyLabel.textColor = palette.secondaryText
            return
        }
        if self.playlists.isEmpty {
            self.tracksListCard.isHidden = true
            self.listEmptyLabel.isHidden = false
            self.listEmptyLabel.text = isRu ? "Плейлисты не найдены." : "No playlists found."
            self.listEmptyLabel.textColor = palette.secondaryText
            return
        }
        self.tracksListCard.isHidden = false
        self.listEmptyLabel.isHidden = true
        for (idx, playlist) in self.playlists.enumerated() {
            let row = BeyGramRowView()
            row.configure(
                iconName: "music.note.list",
                iconTint: palette.accent,
                title: playlist.title,
                value: "\(playlist.trackCount)",
                showsChevron: true,
                showSeparator: idx < self.playlists.count - 1,
                palette: palette,
                onTap: { [weak self] in
                    self?.openPlaylist(playlist)
                }
            )
            self.tracksListCard.contentStack.addArrangedSubview(row)
        }
    }

    private func playSingleYandexTrack(_ track: BGYandexTrack) {
        BeyGramMusicSession.shared.playYandexTrack(track, replaceQueue: true) { [weak self] result in
            guard let self else { return }
            if case let .failure(err) = result {
                let lang = self.presentationData.strings.primaryComponent.languageCode
                let alert = UIAlertController(
                    title: lang.lowercased().hasPrefix("ru") ? "Яндекс Музыка" : "Yandex Music",
                    message: Self.localizedPlaybackError(err, languageCode: lang),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: self.presentationData.strings.Common_OK, style: .default))
                self.present(alert, animated: true, completion: nil)
            }
        }
    }

    private static func localizedPlaybackError(_ error: BGYandexPlaybackError, languageCode: String) -> String {
        let isRu = languageCode.lowercased().hasPrefix("ru")
        switch error {
        case .notSignedIn:
            return isRu ? "Войдите в аккаунт Яндекс Музыки." : "Sign in to your Yandex Music account."
        case .subscriptionRequired:
            return isRu ? "Для прослушивания нужна активная подписка Яндекс Плюс." : "An active Yandex Plus subscription is required."
        case .unavailable:
            return isRu ? "Трек недоступен." : "This track is unavailable."
        case .rateLimited:
            return isRu ? "Слишком много запросов. Попробуйте позже." : "Too many requests. Please try again later."
        case .network:
            return isRu ? "Ошибка сети. Проверьте подключение." : "Network error. Check your connection."
        case .invalidFile:
            return isRu ? "Не удалось воспроизвести аудиофайл." : "Unable to play the audio file."
        }
    }

    private static func localizedServiceError(_ error: BGYandexError, languageCode: String) -> String {
        let isRu = languageCode.lowercased().hasPrefix("ru")
        switch error {
        case .network:
            return isRu ? "Ошибка сети. Проверьте подключение." : "Network error. Check your connection."
        case .sessionExpired:
            return isRu ? "Сессия истекла. Войдите снова." : "Session expired. Please sign in again."
        case .notSignedIn:
            return isRu ? "Войдите в аккаунт Яндекс Музыки." : "Sign in to your Yandex Music account."
        case .subscriptionRequired:
            return isRu ? "Требуется подписка Яндекс Плюс." : "Yandex Plus subscription required."
        case .unavailable:
            return isRu ? "Сервис временно недоступен." : "Service is temporarily unavailable."
        case .notFound:
            return isRu ? "Ничего не найдено." : "Nothing was found."
        case .rateLimited:
            return isRu ? "Слишком много запросов. Попробуйте позже." : "Too many requests. Please try again later."
        case .serviceChanged:
            return isRu ? "Формат ответа сервиса изменился. Обновите приложение." : "Service response changed. Please update the app."
        case .invalidFile:
            return isRu ? "Получен повреждённый аудиофайл." : "Received a corrupted audio file."
        case .unknown:
            return isRu ? "Неизвестная ошибка Яндекс Музыки." : "Unknown Yandex Music error."
        }
    }

    private func loadLikesIfNeeded() {
        if self.likesLoaded || self.likesLoading { return }
        self.likesLoading = true
        self.service.likedTracks { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.likesLoading = false
                self.likesLoaded = true
                if case let .success(tracks) = result {
                    self.likedTracks = tracks
                }
                self.render()
            }
        }
    }

    private func loadPlaylistsIfNeeded() {
        if self.playlistsLoaded || self.playlistsLoading { return }
        self.playlistsLoading = true
        self.service.playlists { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.playlistsLoading = false
                self.playlistsLoaded = true
                if case let .success(items) = result {
                    self.playlists = items
                }
                self.render()
            }
        }
    }

    private func openPlaylist(_ playlist: BGYandexPlaylist) {
        self.selectedPlaylist = playlist
        self.selectedPlaylistTracks = []
        self.render()
        self.service.playlistTracks(kind: playlist.kind, ownerUid: playlist.ownerUid) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if case let .success(tracks) = result {
                    self.selectedPlaylistTracks = tracks
                }
                self.render()
            }
        }
    }

    @objc private func authPrimaryTapped() {
        if !self.accepted {
            self.accepted = true
            UserDefaults.standard.set(true, forKey: "beygram.yandex.consentAccepted")
            self.render()
            return
        }
        if let code = self.waitingCode {
            UIPasteboard.general.string = code
            self.codeCopied = true
            self.render()
            return
        }
        self.authFailure = nil
        self.service.startSignIn { [weak self] event in
            DispatchQueue.main.async {
                guard let self else { return }
                switch event {
                case let .code(deviceCode):
                    self.waitingCode = deviceCode.userCode
                    self.verificationUrl = deviceCode.verificationUrl
                    self.codeCopied = false
                case .finished:
                    self.waitingCode = nil
                    self.verificationUrl = nil
                case let .failed(err):
                    self.waitingCode = nil
                    self.authFailure = String(describing: err)
                }
                self.render()
            }
        }
    }

    @objc private func authSecondaryTapped() {
        if let urlStr = self.verificationUrl, let url = URL(string: urlStr) {
            UIApplication.shared.open(url)
        }
    }

    @objc private func signOutTapped() {
        BeyGramMusicSession.shared.stopWave()
        self.service.signOut()
        self.render()
    }

    @objc private func tabChanged() {
        self.activeTab = SectionTab(rawValue: self.tabControl.selectedSegmentIndex) ?? .myWave
        self.render()
    }

    @objc private func wavePlayTapped() {
        BeyGramMusicSession.shared.startOrToggleWave()
    }

    @objc private func waveNextTapped() {
        BeyGramMusicSession.shared.skipWaveTrack()
    }

    @objc private func waveLikeTapped() {
        BeyGramMusicSession.shared.toggleWaveLike()
    }

    @objc private func searchTapped() {
        self.searchField.resignFirstResponder()
        let query = (self.searchField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        self.searchQuery = query
        self.searchLoading = true
        self.searchError = nil
        self.render()
        self.service.search(text: query, limit: 30) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.searchLoading = false
                switch result {
                case let .success(tracks):
                    self.searchResults = tracks
                case let .failure(err):
                    let lang = self.presentationData.strings.primaryComponent.languageCode
                    self.searchError = Self.localizedServiceError(err, languageCode: lang)
                }
                self.render()
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.searchTapped()
        return true
    }
}

public func beyGramYandexMusicController(context: AccountContext) -> ViewController {
    return BeyGramYandexMusicViewControllerImpl(context: context)
}
