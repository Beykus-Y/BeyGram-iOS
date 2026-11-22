import Foundation

/// What a Yandex Music web address opens inside the app. Only the forms the app opens natively are listed. Every other
/// address (home, charts, radio, artists, and playlists in the `/users/<login>/playlists/<id>` form) stays a web link.
public enum BGYandexLinkTarget: Equatable {
    /// `/album/<id>`: the album screen.
    case album(albumId: String)
    /// `/track/<id>` or `/album/<id>/track/<id>`: the track starts playing. `albumId` is kept when the address has one.
    case track(trackId: String, albumId: String?)
    /// `/playlists/<uuid>` or `/playlists/lk.<uuid>`: the playlist screen, when the account owns or follows it. `uuid` is
    /// lowercased, with its `lk.` prefix when the address has one, so the two forms never match each other.
    case playlist(uuid: String)
}

/// Parses Yandex Music web addresses in the forms the Android app opens natively (`deeplink/YandexMusicLink.kt`).
public enum BGYandexLink {
    /// The Yandex Music hosts. A `www.` prefix is ignored and the case of the host does not matter.
    static let hosts: Set<String> = [
        "music.yandex.ru",
        "music.yandex.com",
        "music.yandex.by",
        "music.yandex.kz",
        "music.yandex.uz",
    ]

    /// The target of a Yandex Music address, or nil when the address is not one of the supported forms. The query and the
    /// fragment do not change the target, so a link with or without `utm_*` tags opens the same screen. An address without
    /// a scheme is read as `https`. An address that carries credentials is refused.
    public static func target(from raw: String) -> BGYandexLinkTarget? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        let normalized = value.contains("://") ? value : "https://" + value
        guard let url = URL(string: normalized), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        guard components.user == nil, components.password == nil else {
            return nil
        }
        guard var host = components.host?.lowercased() else {
            return nil
        }
        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        guard hosts.contains(host) else {
            return nil
        }
        let parts = components.path.split(separator: "/").map(String.init)
        switch parts.count {
        case 2 where parts[0] == "album" && isNumericId(parts[1]):
            return .album(albumId: parts[1])
        case 2 where parts[0] == "track" && isNumericId(parts[1]):
            return .track(trackId: parts[1], albumId: nil)
        case 2 where parts[0] == "playlists" && isPlaylistUuid(parts[1]):
            return .playlist(uuid: parts[1].lowercased())
        case 4 where parts[0] == "album" && parts[2] == "track" && isNumericId(parts[1]) && isNumericId(parts[3]):
            return .track(trackId: parts[3], albumId: parts[1])
        default:
            return nil
        }
    }

    /// A numeric id: 1 to 20 ASCII digits, as the service writes them.
    static func isNumericId(_ text: String) -> Bool {
        return (1...20).contains(text.count) && text.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    /// A playlist uuid (groups of 8, 4, 4, 4 and 12 hex digits), with an optional `lk.` prefix in any letter case.
    static func isPlaylistUuid(_ text: String) -> Bool {
        var body = Substring(text)
        if body.lowercased().hasPrefix("lk.") {
            body = body.dropFirst(3)
        }
        let groups = body.split(separator: "-", omittingEmptySubsequences: false)
        let lengths = [8, 4, 4, 4, 12]
        guard groups.count == lengths.count else {
            return false
        }
        for (group, length) in zip(groups, lengths) {
            guard group.count == length, group.allSatisfy({ $0.isHexDigit }) else {
                return false
            }
        }
        return true
    }
}
