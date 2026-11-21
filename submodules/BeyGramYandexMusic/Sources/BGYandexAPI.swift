import Foundation
import CryptoKit

/// Request builders of the endpoints. Path segments are percent-encoded here; form and JSON bodies are built here too.
enum BGYandexRequests {
    static func url(_ path: String, query: String? = nil) -> URL {
        var string = BGYandexConfig.apiBase + path
        if let query = query {
            string += "?" + query
        }
        return URL(string: string)!
    }

    static func encode(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    /// POST with an `application/x-www-form-urlencoded` body, as the like and track endpoints expect.
    static func form(_ url: URL, fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = BGYandexDeviceFlow.formBody(fields)
        return request
    }

    /// POST with a JSON body, as the radio (rotor) endpoints expect.
    static func json(_ url: URL, body: [String: Any]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return request
    }
}

/// The endpoints the iOS client uses, with the parsing rules of `YandexApi.kt`. Each call answers once, with a value or a
/// `BGYandexError`; nothing throws. Tokens and bodies are never logged. Completions run on the client's queue.
public final class BGYandexAPI {
    private let client: BGYandexClient

    public init(client: BGYandexClient) {
        self.client = client
    }

    // MARK: Account and search

    public func account(token: String, completion: @escaping (Result<BGYandexAccount, BGYandexError>) -> Void) {
        client.send(URLRequest(url: BGYandexRequests.url("/account/status")), token: token) { result in
            BGYandexAPI.object(result, completion) { root in
                BGYandexAPI.parseAccount(root)
            }
        }
    }

    /// Tracks matching `text`, first `limit` of them. Only tracks: the service's artist and album search is not in Android,
    /// so it is not used here either.
    public func search(token: String, text: String, limit: Int, completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void) {
        let query = "text=\(BGYandexRequests.encode(text))&type=track&page=0&nocorrect=false"
        client.send(URLRequest(url: BGYandexRequests.url("/search", query: query)), token: token) { result in
            BGYandexAPI.object(result, completion) { root in
                let tracks = BGYandexAPI.resultObject(root)["tracks"] as? [String: Any]
                let items = (tracks?["results"] as? [[String: Any]]) ?? []
                return Array(BGYandexAPI.parseTracks(items).prefix(max(0, limit)))
            }
        }
    }

    // MARK: Likes and dislikes

    /// Liked track ids, newest first as the service returns them.
    public func likedTrackIds(token: String, uid: String, completion: @escaping (Result<[String], BGYandexError>) -> Void) {
        let path = "/users/\(BGYandexRequests.encode(uid))/likes/tracks"
        client.send(URLRequest(url: BGYandexRequests.url(path)), token: token) { result in
            BGYandexAPI.object(result, completion) { root in
                let library = BGYandexAPI.resultObject(root)["library"] as? [String: Any]
                let items = (library?["tracks"] as? [[String: Any]]) ?? []
                return items.compactMap { BGYandexAPI.idText($0["id"]) }
            }
        }
    }

    /// Tracks by id, in the order given. Requested in chunks of `BGYandexConfig.trackChunk`, one after another.
    public func tracks(token: String, ids: [String], completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void) {
        var chunks: [[String]] = []
        var start = 0
        while start < ids.count {
            let end = min(start + BGYandexConfig.trackChunk, ids.count)
            chunks.append(Array(ids[start..<end]))
            start = end
        }
        fetchTrackChunks(chunks, token: token, collected: [], completion: completion)
    }

    private func fetchTrackChunks(_ chunks: [[String]], token: String, collected: [BGYandexTrack],
                                  completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void) {
        guard let chunk = chunks.first else {
            completion(.success(collected))
            return
        }
        let rest = Array(chunks.dropFirst())
        let request = BGYandexRequests.form(BGYandexRequests.url("/tracks"), fields: [("track-ids", chunk.joined(separator: ","))])
        client.send(request, token: token) { result in
            BGYandexAPI.object(result, { (part: Result<[BGYandexTrack], BGYandexError>) in
                switch part {
                case let .failure(error):
                    completion(.failure(error))
                case let .success(tracks):
                    self.fetchTrackChunks(rest, token: token, collected: collected + tracks, completion: completion)
                }
            }) { root in
                BGYandexAPI.parseTracks(BGYandexAPI.resultArray(root))
            }
        }
    }

    /// Likes or unlikes a track. Only success or failure matters; the answer body is not read.
    public func setLiked(token: String, uid: String, trackId: String, liked: Bool, completion: @escaping (Result<Void, BGYandexError>) -> Void) {
        let action = liked ? "add-multiple" : "remove"
        sendTrackMutation("/users/\(BGYandexRequests.encode(uid))/likes/tracks/\(action)", trackId: trackId, token: token, completion: completion)
    }

    /// Dislikes or undoes it. Endpoint and form are not checked on the live service yet, as on Android: a failure only means
    /// the service did not learn about it, and the radio keeps playing.
    public func setDisliked(token: String, uid: String, trackId: String, disliked: Bool, completion: @escaping (Result<Void, BGYandexError>) -> Void) {
        let action = disliked ? "add-multiple" : "remove"
        sendTrackMutation("/users/\(BGYandexRequests.encode(uid))/dislikes/tracks/\(action)", trackId: trackId, token: token, completion: completion)
    }

    private func sendTrackMutation(_ path: String, trackId: String, token: String, completion: @escaping (Result<Void, BGYandexError>) -> Void) {
        client.send(BGYandexRequests.form(BGYandexRequests.url(path), fields: [("track-ids", trackId)]), token: token) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case .success:
                completion(.success(()))
            }
        }
    }

    // MARK: Playlists and albums

    /// Playlists the account owns.
    public func playlists(token: String, uid: String, completion: @escaping (Result<[BGYandexPlaylist], BGYandexError>) -> Void) {
        client.send(URLRequest(url: BGYandexRequests.url("/users/\(BGYandexRequests.encode(uid))/playlists/list")), token: token) { result in
            BGYandexAPI.object(result, completion) { root in
                BGYandexAPI.resultArray(root).compactMap { BGYandexAPI.parsePlaylist($0, uid: uid) }
            }
        }
    }

    /// Playlists of other users the account liked. Each entry may wrap the playlist in a `playlist` object.
    public func likedPlaylists(token: String, uid: String, completion: @escaping (Result<[BGYandexPlaylist], BGYandexError>) -> Void) {
        client.send(URLRequest(url: BGYandexRequests.url("/users/\(BGYandexRequests.encode(uid))/likes/playlists")), token: token) { result in
            BGYandexAPI.object(result, completion) { root in
                BGYandexAPI.resultArray(root).compactMap { (item: [String: Any]) -> BGYandexPlaylist? in
                    let wrapped = (item["playlist"] as? [String: Any]) ?? item
                    return BGYandexAPI.parsePlaylist(wrapped, uid: uid)
                }
            }
        }
    }

    /// Tracks of one playlist. `ownerUid` is the playlist's owner: the account's own uid for its own playlists.
    public func playlistTracks(token: String, ownerUid: String, kind: String, completion: @escaping (Result<[BGYandexTrack], BGYandexError>) -> Void) {
        let path = "/users/\(BGYandexRequests.encode(ownerUid))/playlists/\(BGYandexRequests.encode(kind))"
        client.send(URLRequest(url: BGYandexRequests.url(path)), token: token) { result in
            BGYandexAPI.object(result, completion) { root in
                let items = (BGYandexAPI.resultObject(root)["tracks"] as? [[String: Any]]) ?? []
                return items.compactMap { (item: [String: Any]) -> BGYandexTrack? in
                    let wrapped = (item["track"] as? [String: Any]) ?? item
                    return BGYandexAPI.parseTrack(wrapped)
                }
            }
        }
    }

    /// Liked albums. Each entry may wrap the album in an `album` object.
    public func likedAlbums(token: String, uid: String, completion: @escaping (Result<[BGYandexAlbum], BGYandexError>) -> Void) {
        let url = BGYandexRequests.url("/users/\(BGYandexRequests.encode(uid))/likes/albums", query: "rich=true")
        client.send(URLRequest(url: url), token: token) { result in
            BGYandexAPI.object(result, completion) { root in
                BGYandexAPI.resultArray(root).compactMap { (item: [String: Any]) -> BGYandexAlbum? in
                    let wrapped = (item["album"] as? [String: Any]) ?? item
                    return BGYandexAPI.parseAlbum(wrapped)
                }
            }
        }
    }

    /// An album with its tracks. The service groups them by disc in `volumes`; tracks without an album get this one.
    public func album(token: String, albumId: String, completion: @escaping (Result<BGYandexAlbumTracks, BGYandexError>) -> Void) {
        let path = "/albums/\(BGYandexRequests.encode(albumId))/with-tracks"
        client.send(URLRequest(url: BGYandexRequests.url(path)), token: token) { result in
            BGYandexAPI.object(result, completion) { root in
                let info = BGYandexAPI.resultObject(root)
                guard let album = BGYandexAPI.parseAlbum(info) else {
                    return nil
                }
                var tracks: [BGYandexTrack] = []
                let volumes = (info["volumes"] as? [Any]) ?? []
                for volume in volumes {
                    guard let items = volume as? [[String: Any]] else {
                        continue
                    }
                    tracks += BGYandexAPI.parseTracks(items)
                }
                let withAlbum = tracks.map { (track: BGYandexTrack) -> BGYandexTrack in
                    return track.albumId == nil ? track.with(albumId: album.id) : track
                }
                return BGYandexAlbumTracks(album: album, tracks: withAlbum)
            }
        }
    }

    // MARK: Radio («Моя волна»)

    /// Starts a radio session from `seeds`. `queue` lists the tracks already heard, as `id:albumId`.
    public func waveStart(token: String, seeds: [String], queue: [String], completion: @escaping (Result<BGYandexWaveBatch, BGYandexError>) -> Void) {
        var body: [String: Any] = ["seeds": seeds, "includeTracksInResponse": true]
        if !queue.isEmpty {
            body["queue"] = Array(queue.suffix(BGYandexConfig.queueHint))
        }
        client.send(BGYandexRequests.json(BGYandexRequests.url("/rotor/session/new"), body: body), token: token) { result in
            BGYandexAPI.object(result, completion) { root in
                BGYandexAPI.parseWaveBatch(root, sessionId: nil)
            }
        }
    }

    /// The next batch of a radio session. `queue` lists the tracks the session already gave, as `id:albumId`.
    public func waveNext(token: String, sessionId: String, queue: [String], completion: @escaping (Result<BGYandexWaveBatch, BGYandexError>) -> Void) {
        let body: [String: Any] = ["queue": Array(queue.suffix(BGYandexConfig.queueHint))]
        let path = "/rotor/session/\(BGYandexRequests.encode(sessionId))/tracks"
        client.send(BGYandexRequests.json(BGYandexRequests.url(path), body: body), token: token) { result in
            BGYandexAPI.object(result, completion) { root in
                BGYandexAPI.parseWaveBatch(root, sessionId: sessionId)
            }
        }
    }

    /// One listening event of a radio session. Answers are ignored beyond success or failure, as on Android.
    public func waveFeedback(token: String, sessionId: String, event: BGYandexWaveEvent, batchId: String?, completion: @escaping (Result<Void, BGYandexError>) -> Void) {
        var body: [String: Any] = ["event": event.json()]
        if let batchId = batchId {
            body["batchId"] = batchId
        }
        if event.type == .radioStarted {
            body["from"] = BGYandexConfig.waveFrom
        }
        let path = "/rotor/session/\(BGYandexRequests.encode(sessionId))/feedback"
        client.send(BGYandexRequests.json(BGYandexRequests.url(path), body: body), token: token) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case .success:
                completion(.success(()))
            }
        }
    }

    // MARK: Lyrics and audio

    /// Lyrics: the service gives a link to a file, LRC when it has time tags and plain text otherwise. The file is read
    /// without the token, as on Android.
    public func lyrics(token: String, trackId: String, completion: @escaping (Result<BGYandexLyrics, BGYandexError>) -> Void) {
        let url = BGYandexRequests.url("/tracks/\(BGYandexRequests.encode(trackId))/lyrics", query: "format=LRC")
        client.send(URLRequest(url: url), token: token) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(data):
                guard let root = BGYandexAPI.json(data), let info = root["result"] as? [String: Any],
                      let link = BGYandexAPI.nonBlank(info["downloadUrl"] as? String), let fileURL = URL(string: link) else {
                    completion(.failure(.serviceChanged))
                    return
                }
                let major = info["major"] as? [String: Any]
                let holder = BGYandexAPI.nonBlank(major?["name"] as? String)
                self.client.send(URLRequest(url: fileURL), token: nil) { fileResult in
                    switch fileResult {
                    case let .failure(error):
                        completion(.failure(error))
                    case let .success(body):
                        let text = String(decoding: body, as: UTF8.self)
                        completion(.success(BGYandexLRC.lyrics(from: text, copyrightHolder: holder)))
                    }
                }
            }
        }
    }

    /// Full-track link: the `download-info` list, then the XML of the best MP3 unless that link is direct. Previews (about
    /// 30 seconds) are never used as full tracks. The service checks the subscription before this is called.
    public func audioLink(token: String, trackId: String, completion: @escaping (Result<BGYandexAudio, BGYandexError>) -> Void) {
        let path = "/tracks/\(BGYandexRequests.encode(trackId))/download-info"
        client.send(URLRequest(url: BGYandexRequests.url(path)), token: token) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(data):
                guard let root = BGYandexAPI.json(data), let array = root["result"] as? [[String: Any]] else {
                    completion(.failure(.serviceChanged))
                    return
                }
                let options = array.compactMap { BGYandexAPI.downloadOption($0) }
                // The first of equal bitrates wins, as `maxByOrNull` on Android.
                guard let best = options.max(by: { $0.kbps < $1.kbps }), !best.url.isEmpty else {
                    completion(.failure(.serviceChanged))
                    return
                }
                if best.direct, let direct = URL(string: best.url) {
                    completion(.success(BGYandexAudio(url: direct, codec: best.codec, bitrateKbps: best.kbps)))
                    return
                }
                self.signedLink(fromXMLAt: best.url, codec: best.codec, kbps: best.kbps, completion: completion)
            }
        }
    }

    private func signedLink(fromXMLAt urlText: String, codec: String, kbps: Int, completion: @escaping (Result<BGYandexAudio, BGYandexError>) -> Void) {
        guard let url = URL(string: urlText) else {
            completion(.failure(.serviceChanged))
            return
        }
        // Helper file on a storage host: no token, and no gap between requests (as Android's `fetchFile`).
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
                completion(.success(BGYandexAudio(url: link, codec: codec, bitrateKbps: kbps)))
            }
        }
    }

    // MARK: Parsing (the rules of YandexApi.kt). Unknown fields are ignored; a missing required field is a changed service.

    struct DownloadOption: Equatable {
        let codec: String
        let kbps: Int
        let url: String
        let direct: Bool
    }

    private static let supportedCodecs: Set<String> = ["mp3", "aac", "he-aac", "mp4", "m4a", "flac", "alac", "wav"]

    static func downloadOption(_ item: [String: Any]) -> DownloadOption? {
        guard let rawCodec = (item["codec"] as? String)?.lowercased(),
              supportedCodecs.contains(rawCodec),
              (item["preview"] as? Bool) != true else {
            return nil
        }
        return DownloadOption(
            codec: rawCodec,
            kbps: (item["bitrateInKbps"] as? NSNumber)?.intValue ?? 0,
            url: (item["downloadInfoUrl"] as? String) ?? "",
            direct: (item["direct"] as? Bool) == true
        )
    }

    /// Parses a body that must be one JSON object; a body of another shape, or one the map cannot read, is a changed service.
    static func object<T>(_ result: Result<Data, BGYandexError>,
                          _ completion: (Result<T, BGYandexError>) -> Void,
                          _ map: ([String: Any]) -> T?) {
        switch result {
        case let .failure(error):
            completion(.failure(error))
        case let .success(data):
            guard let root = BGYandexAPI.json(data), let value = map(root) else {
                completion(.failure(.serviceChanged))
                return
            }
            completion(.success(value))
        }
    }

    /// The JSON object of a body, or nil when the body is not one.
    static func json(_ data: Data) -> [String: Any]? {
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// The `result` object of a response, or the response itself when there is none.
    static func resultObject(_ root: [String: Any]) -> [String: Any] {
        return (root["result"] as? [String: Any]) ?? root
    }

    /// The `result` array of a response; empty when missing.
    static func resultArray(_ root: [String: Any]) -> [[String: Any]] {
        return (root["result"] as? [[String: Any]]) ?? []
    }

    /// The text when it is not blank, else nil.
    static func nonBlank(_ value: String?) -> String? {
        guard let value = value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    /// An id, which the service sends as a number or as text. Blank is no id.
    static func idText(_ value: Any?) -> String? {
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nonBlank(value as? String)
    }

    /// Cover address as the app shows it: the service's template with the 200x200 size. Nil when there is none.
    static func coverUrl(_ raw: String?) -> String? {
        guard let raw = BGYandexAPI.nonBlank(raw) else {
            return nil
        }
        return "https://" + raw.replacingOccurrences(of: "%%", with: "200x200")
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

    static func parseTracks(_ items: [[String: Any]]) -> [BGYandexTrack] {
        return items.compactMap { BGYandexAPI.parseTrack($0) }
    }

    static func parseTrack(_ object: [String: Any]) -> BGYandexTrack? {
        guard let id = BGYandexAPI.idText(object["id"]), let title = BGYandexAPI.nonBlank(object["title"] as? String) else {
            return nil
        }
        let artistObjects = (object["artists"] as? [[String: Any]]) ?? []
        let artists: [String] = artistObjects.compactMap { BGYandexAPI.nonBlank($0["name"] as? String) }
        let artistRefs: [BGYandexArtistRef] = artistObjects.compactMap { (item: [String: Any]) -> BGYandexArtistRef? in
            guard let name = BGYandexAPI.nonBlank(item["name"] as? String), let artistId = BGYandexAPI.idText(item["id"]) else {
                return nil
            }
            return BGYandexArtistRef(id: artistId, name: name)
        }
        let firstAlbum = (object["albums"] as? [[String: Any]])?.first
        let duration = (object["durationMs"] as? NSNumber)?.int64Value ?? 0
        return BGYandexTrack(
            trackId: id,
            title: title,
            artists: artists,
            albumId: firstAlbum.flatMap { BGYandexAPI.idText($0["id"]) },
            albumTitle: firstAlbum.flatMap { BGYandexAPI.nonBlank($0["title"] as? String) },
            durationMs: duration,
            coverUrl: BGYandexAPI.coverUrl(object["coverUri"] as? String),
            isAvailable: (object["available"] as? Bool) ?? true,
            liked: nil,
            artistRefs: artistRefs
        )
    }

    static func parsePlaylist(_ item: [String: Any], uid: String) -> BGYandexPlaylist? {
        guard let kind = BGYandexAPI.idText(item["kind"]), let title = BGYandexAPI.nonBlank(item["title"] as? String) else {
            return nil
        }
        let owner = item["owner"] as? [String: Any]
        let ownerUid = owner.flatMap { BGYandexAPI.idText($0["uid"]) } ?? BGYandexAPI.idText(item["uid"])
        let cover = item["cover"] as? [String: Any]
        let coverRaw = BGYandexAPI.nonBlank(cover?["uri"] as? String) ?? (item["ogImage"] as? String)
        let ownerName = owner.flatMap { BGYandexAPI.nonBlank($0["name"] as? String) ?? BGYandexAPI.nonBlank($0["login"] as? String) }
        return BGYandexPlaylist(
            kind: kind,
            title: title,
            trackCount: (item["trackCount"] as? NSNumber)?.intValue ?? 0,
            coverUrl: BGYandexAPI.coverUrl(coverRaw),
            isOwn: ownerUid == uid,
            ownerUid: ownerUid,
            ownerName: ownerName,
            uuid: BGYandexAPI.nonBlank(item["playlistUuid"] as? String)
        )
    }

    static func parseAlbum(_ object: [String: Any]) -> BGYandexAlbum? {
        guard let id = BGYandexAPI.idText(object["id"]), let title = BGYandexAPI.nonBlank(object["title"] as? String) else {
            return nil
        }
        let artists: [String] = ((object["artists"] as? [[String: Any]]) ?? []).compactMap { BGYandexAPI.nonBlank($0["name"] as? String) }
        let year = (object["year"] as? NSNumber)?.intValue ?? 0
        return BGYandexAlbum(
            id: id,
            title: title,
            artists: artists,
            year: year > 0 ? year : nil,
            trackCount: (object["trackCount"] as? NSNumber)?.intValue ?? 0,
            coverUrl: BGYandexAPI.coverUrl(object["coverUri"] as? String)
        )
    }

    /// A session or next-batch answer. Nil when the shape is not the expected one.
    static func parseWaveBatch(_ root: [String: Any], sessionId: String?) -> BGYandexWaveBatch? {
        let result = BGYandexAPI.resultObject(root)
        guard let id = BGYandexAPI.idText(result["radioSessionId"]) ?? sessionId else {
            return nil
        }
        let sequence = (result["sequence"] as? [[String: Any]]) ?? []
        var tracks: [BGYandexTrack] = []
        for entry in sequence {
            guard let object = entry["track"] as? [String: Any], let track = BGYandexAPI.parseTrack(object) else {
                continue
            }
            if let liked = entry["liked"] as? Bool {
                tracks.append(track.with(liked: liked))
            } else {
                tracks.append(track)
            }
        }
        return BGYandexWaveBatch(
            sessionId: id,
            batchId: BGYandexAPI.idText(result["batchId"]),
            tracks: tracks,
            unknownSession: (result["unknownSession"] as? Bool) ?? false,
            terminated: (result["terminated"] as? Bool) ?? false
        )
    }

    // MARK: Download link (the legacy signed XML of a track)

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
