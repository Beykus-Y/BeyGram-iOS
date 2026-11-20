import Foundation
import CryptoKit

public struct BGYandexAccount: Equatable {
    public let uid: String
    public let displayName: String
    public let hasPlus: Bool
}

public struct BGYandexTrack: Equatable {
    public let trackId: String
    public let title: String
    public let artists: [String]
    public let albumId: String?
    public let albumTitle: String?
    public let durationMs: Int64
}

/// A signed download link. Never stored: it expires quickly and is requested again when a track is fetched.
public struct BGYandexAudioLink: Equatable {
    public let url: URL
}

/// The endpoints the iOS client uses, with the parsing rules of `YandexApi.kt`. Only the account, search and audio link
/// are implemented. Likes, playlists, waves, and lyrics are not.
public final class BGYandexAPI {
    private let client: BGYandexClient

    public init(client: BGYandexClient) {
        self.client = client
    }

    private static func url(_ path: String, query: String? = nil) -> URL {
        var string = BGYandexConfig.apiBase + path
        if let query = query {
            string += "?" + query
        }
        return URL(string: string)!
    }

    private static func encode(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    private static func json(_ data: Data) -> [String: Any]? {
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    public func account(token: String, completion: @escaping (Result<BGYandexAccount, BGYandexError>) -> Void) {
        client.send(URLRequest(url: BGYandexAPI.url("/account/status")), token: token) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(data):
                guard let root = BGYandexAPI.json(data), let account = BGYandexAPI.parseAccount(root) else {
                    completion(.failure(.serviceChanged))
                    return
                }
                completion(.success(account))
            }
        }
    }

    static func parseAccount(_ root: [String: Any]) -> BGYandexAccount? {
        let result = (root["result"] as? [String: Any]) ?? root
        guard let account = result["account"] as? [String: Any] else {
            return nil
        }
        let uid: String
        if let number = account["uid"] as? NSNumber {
            uid = number.stringValue
        } else if let text = account["uid"] as? String, !text.isEmpty {
            uid = text
        } else {
            return nil
        }
        let name = ((account["displayName"] as? String) ?? "").isEmpty ? ((account["login"] as? String) ?? "") : (account["displayName"] as? String ?? "")
        let plus = result["plus"] as? [String: Any]
        let subscription = result["subscription"] as? [String: Any]
        let flags: [Any?] = [
            plus?["has_plus"], plus?["hasPlus"], subscription?["has_plus"], subscription?["hasPlus"],
            result["has_plus"], account["has_plus"],
        ]
        let hasPlus = flags.contains { ($0 as? Bool) == true }
        return BGYandexAccount(uid: uid, displayName: name, hasPlus: hasPlus)
    }

    public func search(token: String, text: String, limit: Int, completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void) {
        let query = "text=\(BGYandexAPI.encode(text))&type=track&page=0&nocorrect=false"
        client.send(URLRequest(url: BGYandexAPI.url("/search", query: query)), token: token) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(data):
                guard let root = BGYandexAPI.json(data) else {
                    completion(.failure(.serviceChanged))
                    return
                }
                let result = (root["result"] as? [String: Any]) ?? root
                let items = ((result["tracks"] as? [String: Any])?["results"] as? [[String: Any]]) ?? []
                let tracks = items.compactMap { BGYandexAPI.parseTrack($0) }
                completion(.success(Array(tracks.prefix(limit))))
            }
        }
    }

    static func parseTrack(_ object: [String: Any]) -> BGYandexTrack? {
        guard let id = idText(object["id"]), let title = object["title"] as? String, !title.isEmpty else {
            return nil
        }
        let artists = ((object["artists"] as? [[String: Any]]) ?? []).compactMap { ($0["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let firstAlbum = (object["albums"] as? [[String: Any]])?.first
        let duration = (object["durationMs"] as? NSNumber)?.int64Value ?? 0
        return BGYandexTrack(
            trackId: id,
            title: title,
            artists: artists,
            albumId: idText(firstAlbum?["id"]),
            albumTitle: (firstAlbum?["title"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            durationMs: duration
        )
    }

    static func idText(_ value: Any?) -> String? {
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let text = value as? String, !text.isEmpty {
            return text
        }
        return nil
    }

    /// Signed MP3 link for a track: the `download-info` list, then the XML of the best option unless the link is direct.
    /// Previews (about 30 seconds) are never used as full tracks.
    public func audioLink(token: String, trackId: String, completion: @escaping (Result<BGYandexAudioLink, BGYandexError>) -> Void) {
        client.send(URLRequest(url: BGYandexAPI.url("/tracks/\(BGYandexAPI.encode(trackId))/download-info")), token: token) { [weak self] result in
            guard let self = self else {
                return
            }
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(data):
                guard let root = BGYandexAPI.json(data), let array = root["result"] as? [[String: Any]] else {
                    completion(.failure(.serviceChanged))
                    return
                }
                let options = array.compactMap { item -> (Int, String, Bool)? in
                    guard (item["codec"] as? String) == "mp3", (item["preview"] as? Bool) != true else {
                        return nil
                    }
                    let kbps = (item["bitrateInKbps"] as? NSNumber)?.intValue ?? 0
                    return (kbps, (item["downloadInfoUrl"] as? String) ?? "", (item["direct"] as? Bool) == true)
                }
                guard let best = options.max(by: { $0.0 < $1.0 }), !best.1.isEmpty else {
                    completion(.failure(.serviceChanged))
                    return
                }
                if best.2, let direct = URL(string: best.1) {
                    completion(.success(BGYandexAudioLink(url: direct)))
                    return
                }
                self.signedLink(fromXMLAt: best.1, completion: completion)
            }
        }
    }

    private func signedLink(fromXMLAt urlText: String, completion: @escaping (Result<BGYandexAudioLink, BGYandexError>) -> Void) {
        guard let url = URL(string: urlText) else {
            completion(.failure(.serviceChanged))
            return
        }
        // Helper file on a storage host: no token, and no gap between requests (as Android's `paced = false`).
        client.send(URLRequest(url: url), token: nil, paced: false) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(data):
                guard let xml = String(data: data, encoding: .utf8), let info = BGYandexAPI.parseDownloadInfo(xml),
                      let link = BGYandexAPI.directLink(info) else {
                    completion(.failure(.serviceChanged))
                    return
                }
                completion(.success(BGYandexAudioLink(url: link)))
            }
        }
    }

    struct DownloadInfo: Equatable {
        let host: String
        let path: String
        let ts: String
        let s: String
    }

    /// Reads the four fields. Documents with a DOCTYPE or ENTITY declaration are refused, so no entity is ever resolved.
    static func parseDownloadInfo(_ xml: String) -> DownloadInfo? {
        let upper = xml.uppercased()
        if upper.contains("<!DOCTYPE") || upper.contains("<!ENTITY") {
            return nil
        }
        func field(_ name: String) -> String? {
            guard let open = xml.range(of: "<\(name)>"), let close = xml.range(of: "</\(name)>", range: open.upperBound..<xml.endIndex) else {
                return nil
            }
            let value = String(xml[open.upperBound..<close.lowerBound])
            return value.isEmpty ? nil : value
        }
        guard let host = field("host"), let path = field("path"), let ts = field("ts"), let s = field("s") else {
            return nil
        }
        return DownloadInfo(host: host, path: path, ts: ts, s: s)
    }

    /// `https://<host>/get-mp3/<md5(salt + path-without-slash + s)>/<ts><path>`.
    static func directLink(_ info: DownloadInfo) -> URL? {
        let input = BGYandexConfig.downloadSignSalt + String(info.path.drop(while: { $0 == "/" })) + info.s
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        let sign = digest.map { String(format: "%02x", $0) }.joined()
        return URL(string: "https://\(info.host)/get-mp3/\(sign)/\(info.ts)\(info.path)")
    }
}
