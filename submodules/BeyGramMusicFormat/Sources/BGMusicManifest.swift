import Foundation

/// Why a .bgmusic manifest was refused. Only the reasons that the manifest itself can cause are here;
/// container errors (ZIP, cover) belong to the archive reader.
public enum BGMusicFormatError: Error, Equatable {
    case badJson
    case badSignature
    case badField(String)
    case tooManyTracks
}

public enum BGMusicDecodeResult: Equatable {
    case success(BGMusicManifest)
    /// The file needs a newer reader. Nothing is imported and the file is left alone.
    case unsupported(formatVersion: Int64, minReaderVersion: Int64)
    case invalid(BGMusicFormatError)
}

public enum BGMusicSource: Equatable {
    /// A public post. `username` has no `@`.
    case telegramPublic(username: String, messageId: Int64)
}

public struct BGMusicTrack: Equatable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var durationSec: Int64
    /// `sha256:` and 64 lowercase hex digits, or nil when the hash was not computed.
    public var audioHash: String?
    public var sources: [BGMusicSource]

    public init(id: String, title: String, artist: String, album: String, durationSec: Int64, audioHash: String?, sources: [BGMusicSource]) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSec = durationSec
        self.audioHash = audioHash
        self.sources = sources
    }
}

/// The `manifest.json` of a .bgmusic v1 file (section 3 of the spec).
///
/// The ZIP container is not handled here. `normalized()` applies the write rules, and `decode(_:)` applies the
/// read rules to already-parsed JSON bytes. Both use the same text cleaning, so a written file reads back as is.
public struct BGMusicManifest: Equatable {
    public static let formatName = "beygram.music"
    public static let formatVersion: Int64 = 1
    public static let maxTracks = 5000
    public static let maxSourcesPerTrack = 8
    public static let maxRevision: Int64 = Int64.max
    public static let maxUpdatedAt: Int64 = 253_402_300_799_999
    public static let maxDurationSec: Int64 = 604_800

    public var playlistId: String
    public var revision: Int64
    public var title: String
    public var description: String
    public var updatedAt: Int64
    /// Written only with the owner's explicit consent (section 9). Nil means no author field.
    public var authorName: String?
    public var tracks: [BGMusicTrack]

    public init(playlistId: String, revision: Int64, title: String, description: String, updatedAt: Int64, authorName: String?, tracks: [BGMusicTrack]) {
        self.playlistId = playlistId
        self.revision = revision
        self.title = title
        self.description = description
        self.updatedAt = updatedAt
        self.authorName = authorName
        self.tracks = tracks
    }

    // MARK: Validation helpers

    /// Lowercased UUID in the 8-4-4-4-12 form, or nil.
    static func canonicalUUID(_ value: String) -> String? {
        let chars = Array(value)
        guard chars.count == 36 else {
            return nil
        }
        for (index, char) in chars.enumerated() {
            if index == 8 || index == 13 || index == 18 || index == 23 {
                if char != "-" {
                    return nil
                }
            } else if !char.isHexDigit {
                return nil
            }
        }
        return value.lowercased()
    }

    /// `sha256:` plus 64 hex digits, lowercased, or nil.
    static func canonicalAudioHash(_ value: String) -> String? {
        let prefix = "sha256:"
        guard value.lowercased().hasPrefix(prefix) else {
            return nil
        }
        let digits = String(value.dropFirst(prefix.count))
        guard digits.count == 64, digits.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return prefix + digits.lowercased()
    }

    /// Telegram username without `@`: 5 to 32 characters, Latin letters, digits and `_`, starting with a letter.
    static func isValidUsername(_ value: String) -> Bool {
        let chars = Array(value)
        guard chars.count >= 5, chars.count <= 32, let first = chars.first, first.isASCII, first.isLetter else {
            return false
        }
        return chars.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" }
    }

    // MARK: Normalization (write rules, same as the read rules)

    /// Cleans every text field and checks every range. Throws `badField` with the field name on failure.
    public func normalized() throws -> BGMusicManifest {
        guard let playlist = BGMusicManifest.canonicalUUID(playlistId) else {
            throw BGMusicFormatError.badField("playlist_id")
        }
        guard revision >= 0 else {
            throw BGMusicFormatError.badField("revision")
        }
        let cleanTitle = BGMusicText.singleLine(title, maxLength: 128)
        guard !cleanTitle.isEmpty else {
            throw BGMusicFormatError.badField("title")
        }
        guard updatedAt >= 0, updatedAt <= BGMusicManifest.maxUpdatedAt else {
            throw BGMusicFormatError.badField("updated_at")
        }
        let cleanDescription = BGMusicText.multiline(description, maxLength: 1000)
        var cleanAuthor: String?
        if let authorName = authorName {
            let clean = BGMusicText.singleLine(authorName, maxLength: 128)
            guard !clean.isEmpty else {
                throw BGMusicFormatError.badField("author.name")
            }
            cleanAuthor = clean
        }
        guard tracks.count <= BGMusicManifest.maxTracks else {
            throw BGMusicFormatError.tooManyTracks
        }
        var seenIds = Set<String>()
        var cleanTracks: [BGMusicTrack] = []
        for track in tracks {
            guard let trackId = BGMusicManifest.canonicalUUID(track.id), seenIds.insert(trackId).inserted else {
                throw BGMusicFormatError.badField("tracks.id")
            }
            let cleanTrackTitle = BGMusicText.singleLine(track.title, maxLength: 256)
            guard !cleanTrackTitle.isEmpty else {
                throw BGMusicFormatError.badField("tracks.title")
            }
            guard track.durationSec >= 0, track.durationSec <= BGMusicManifest.maxDurationSec else {
                throw BGMusicFormatError.badField("tracks.duration_sec")
            }
            var hash: String?
            if let rawHash = track.audioHash {
                guard let canonical = BGMusicManifest.canonicalAudioHash(rawHash) else {
                    throw BGMusicFormatError.badField("tracks.audio_hash")
                }
                hash = canonical
            }
            guard track.sources.count <= BGMusicManifest.maxSourcesPerTrack else {
                throw BGMusicFormatError.badField("tracks.sources")
            }
            var sources: [BGMusicSource] = []
            for source in track.sources {
                switch source {
                case let .telegramPublic(username, messageId):
                    guard BGMusicManifest.isValidUsername(username), messageId >= 1, messageId <= 2_147_483_647 else {
                        throw BGMusicFormatError.badField("tracks.sources")
                    }
                    sources.append(source)
                }
            }
            cleanTracks.append(BGMusicTrack(
                id: trackId,
                title: cleanTrackTitle,
                artist: BGMusicText.singleLine(track.artist, maxLength: 256),
                album: BGMusicText.singleLine(track.album, maxLength: 256),
                durationSec: track.durationSec,
                audioHash: hash,
                sources: sources
            ))
        }
        return BGMusicManifest(
            playlistId: playlist,
            revision: revision,
            title: cleanTitle,
            description: cleanDescription,
            updatedAt: updatedAt,
            authorName: cleanAuthor,
            tracks: cleanTracks
        )
    }

    // MARK: Encoding

    /// Strict JSON with the fixed key order of section 3. Optional fields are left out, never written as `null`.
    public func jsonData() throws -> Data {
        let m = try normalized()
        var parts: [String] = []
        parts.append("\"format\":\(BGMusicJSON.string(BGMusicManifest.formatName))")
        parts.append("\"format_version\":\(BGMusicManifest.formatVersion)")
        parts.append("\"min_reader_version\":\(BGMusicManifest.formatVersion)")
        parts.append("\"playlist_id\":\(BGMusicJSON.string(m.playlistId))")
        parts.append("\"revision\":\(m.revision)")
        parts.append("\"title\":\(BGMusicJSON.string(m.title))")
        parts.append("\"description\":\(BGMusicJSON.string(m.description))")
        parts.append("\"updated_at\":\(m.updatedAt)")
        if let author = m.authorName {
            parts.append("\"author\":{\"name\":\(BGMusicJSON.string(author))}")
        }
        let trackJSON = m.tracks.map { track -> String in
            var fields: [String] = []
            fields.append("\"id\":\(BGMusicJSON.string(track.id))")
            fields.append("\"title\":\(BGMusicJSON.string(track.title))")
            fields.append("\"artist\":\(BGMusicJSON.string(track.artist))")
            fields.append("\"album\":\(BGMusicJSON.string(track.album))")
            fields.append("\"duration_sec\":\(track.durationSec)")
            if let hash = track.audioHash {
                fields.append("\"audio_hash\":\(BGMusicJSON.string(hash))")
            }
            if !track.sources.isEmpty {
                let sources = track.sources.map { source -> String in
                    switch source {
                    case let .telegramPublic(username, messageId):
                        return "{\"type\":\"telegram_public\",\"username\":\(BGMusicJSON.string(username)),\"message_id\":\(messageId)}"
                    }
                }
                fields.append("\"sources\":[\(sources.joined(separator: ","))]")
            }
            return "{\(fields.joined(separator: ","))}"
        }
        parts.append("\"tracks\":[\(trackJSON.joined(separator: ","))]")
        let json = "{\(parts.joined(separator: ","))}"
        return Data(json.utf8)
    }

    // MARK: Decoding

    /// Reads manifest bytes. The strict parser runs first (duplicate keys, depth and grammar are checked there).
    /// Then the format name and versions are checked (section 8), then the fields. Unknown fields are ignored.
    public static func decode(_ data: Data) -> BGMusicDecodeResult {
        let parsed: BGMusicJSONValue
        switch BGMusicStrictJSON.parse(data) {
        case let .success(value):
            parsed = value
        case .failure:
            return .invalid(.badJson)
        }
        guard case .object = parsed else {
            return .invalid(.badJson)
        }
        guard stringValue(parsed["format"]) == formatName else {
            return .invalid(.badSignature)
        }
        guard let formatVersionValue = integerValue(parsed["format_version"]), formatVersionValue >= 1,
              let minReaderValue = integerValue(parsed["min_reader_version"]), minReaderValue >= 1, minReaderValue <= formatVersionValue else {
            return .invalid(.badField("format_version"))
        }
        if minReaderValue > formatVersion {
            return .unsupported(formatVersion: formatVersionValue, minReaderVersion: minReaderValue)
        }
        guard let playlistRaw = stringValue(parsed["playlist_id"]), canonicalUUID(playlistRaw) != nil else {
            return .invalid(.badField("playlist_id"))
        }
        guard let revisionValue = integerValue(parsed["revision"]), revisionValue >= 0 else {
            return .invalid(.badField("revision"))
        }
        guard let titleRaw = stringValue(parsed["title"]) else {
            return .invalid(.badField("title"))
        }
        let descriptionRaw = stringValue(parsed["description"]) ?? ""
        guard let updatedValue = integerValue(parsed["updated_at"]) else {
            return .invalid(.badField("updated_at"))
        }
        var authorName: String?
        if case .object? = parsed["author"] {
            authorName = stringValue(parsed["author"]?["name"])
        }
        guard case let .array(trackValues)? = parsed["tracks"] else {
            return .invalid(.badField("tracks"))
        }
        guard trackValues.count <= maxTracks else {
            return .invalid(.tooManyTracks)
        }
        var tracks: [BGMusicTrack] = []
        for raw in trackValues {
            guard let id = stringValue(raw["id"]), let title = stringValue(raw["title"]),
                  let duration = integerValue(raw["duration_sec"]) else {
                return .invalid(.badField("tracks"))
            }
            let hash = stringValue(raw["audio_hash"])
            var sources: [BGMusicSource] = []
            switch raw["sources"] {
            case nil, .null?:
                break
            case let .array(items)?:
                for item in items {
                    // Unknown types and broken hints are dropped without touching the rest of the file.
                    guard stringValue(item["type"]) == "telegram_public",
                          let username = stringValue(item["username"]),
                          let messageId = integerValue(item["message_id"]) else {
                        continue
                    }
                    sources.append(.telegramPublic(username: username, messageId: messageId))
                }
            default:
                return .invalid(.badField("tracks.sources"))
            }
            tracks.append(BGMusicTrack(
                id: id,
                title: title,
                artist: stringValue(raw["artist"]) ?? "",
                album: stringValue(raw["album"]) ?? "",
                durationSec: duration,
                audioHash: hash,
                sources: sources
            ))
        }
        let manifest = BGMusicManifest(
            playlistId: playlistRaw,
            revision: revisionValue,
            title: titleRaw,
            description: descriptionRaw,
            updatedAt: updatedValue,
            authorName: authorName,
            tracks: tracks
        )
        do {
            return .success(try manifest.normalized())
        } catch let error as BGMusicFormatError {
            return .invalid(error)
        } catch {
            return .invalid(.badField("manifest"))
        }
    }

    /// A JSON integer that fits Int64. Fractions and exponents are refused, since v1 has no such fields.
    private static func integerValue(_ value: BGMusicJSONValue?) -> Int64? {
        guard case let .number(text)? = value else {
            return nil
        }
        return Int64(text)
    }

    private static func stringValue(_ value: BGMusicJSONValue?) -> String? {
        guard case let .string(text)? = value else {
            return nil
        }
        return text
    }
}

/// Minimal JSON string escaping for the writer. Control characters become `\uXXXX`.
enum BGMusicJSON {
    static func string(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                out += "\\\""
            case "\\":
                out += "\\\\"
            case "\n":
                out += "\\n"
            case "\r":
                out += "\\r"
            case "\t":
                out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}
