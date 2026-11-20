import Foundation

/// Why a .bgmusic archive was refused (section 6.1 of the spec). Manifest errors are in `BGMusicFormatError`.
public enum BGMusicArchiveError: Error, Equatable {
    case tooLarge
    case notZip
    case corruptArchive
    case missingManifest
    case badEntryName
    case duplicateEntry
    case tooManyEntries
    case manifestTooLarge
    case coverTooLarge
    case badCover
}

public enum BGMusicCoverKind: String, Equatable {
    case webp = "cover.webp"
    case jpg = "cover.jpg"
    case png = "cover.png"
}

public struct BGMusicCover: Equatable {
    public let kind: BGMusicCoverKind
    public let data: Data

    public init(kind: BGMusicCoverKind, data: Data) {
        self.kind = kind
        self.data = data
    }
}

public struct BGMusicArchiveContents: Equatable {
    /// The raw bytes of `manifest.json`. Parse them with `BGMusicManifest.decode(_:)`.
    public let manifest: Data
    public let cover: BGMusicCover?
}

/// The .bgmusic ZIP container (section 2 and section 4 of the spec). Reads stored and deflated entries and writes stored ones.
public enum BGMusicArchive {
    public static let maxFileBytes = 4 * 1024 * 1024
    public static let maxTotalUncompressed = 4 * 1024 * 1024
    public static let maxManifestBytes = 2 * 1024 * 1024
    public static let maxCoverBytes = 1024 * 1024
    public static let maxEntries = 8
    public static let maxNameLength = 100

    private static let forbiddenExtensions: [String] = [".zip", ".bgmusic", ".jar", ".apk", ".7z", ".rar", ".tar", ".gz", ".tgz", ".bz2", ".xz"]

    private struct Entry {
        let name: String
        let method: Int
        let flags: Int
        let crc: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localOffset: Int
    }

    // MARK: Reading

    public static func read(_ data: Data) -> Result<BGMusicArchiveContents, BGMusicArchiveError> {
        guard data.count <= maxFileBytes else {
            return .failure(.tooLarge)
        }
        let bytes = [UInt8](data)
        guard bytes.count >= 4, u32(bytes, 0) == 0x0403_4B50 else {
            return .failure(.notZip)
        }
        guard let eocd = findEndOfCentralDirectory(bytes) else {
            return .failure(.corruptArchive)
        }
        let entryCount = Int(u16(bytes, eocd + 10))
        let directorySize = Int(u32(bytes, eocd + 12))
        let directoryOffset = Int(u32(bytes, eocd + 16))
        guard entryCount <= maxEntries else {
            return .failure(.tooManyEntries)
        }
        guard directoryOffset + directorySize <= bytes.count, directoryOffset <= eocd else {
            return .failure(.corruptArchive)
        }

        var entries: [Entry] = []
        var cursor = directoryOffset
        for _ in 0..<entryCount {
            guard cursor + 46 <= bytes.count, u32(bytes, cursor) == 0x0201_4B50 else {
                return .failure(.corruptArchive)
            }
            let flags = Int(u16(bytes, cursor + 8))
            let method = Int(u16(bytes, cursor + 10))
            let crc = u32(bytes, cursor + 16)
            let compressed = Int(u32(bytes, cursor + 20))
            let uncompressed = Int(u32(bytes, cursor + 24))
            let nameLength = Int(u16(bytes, cursor + 28))
            let extraLength = Int(u16(bytes, cursor + 30))
            let commentLength = Int(u16(bytes, cursor + 32))
            let localOffset = Int(u32(bytes, cursor + 42))
            guard cursor + 46 + nameLength <= bytes.count else {
                return .failure(.corruptArchive)
            }
            let nameBytes = Array(bytes[(cursor + 46)..<(cursor + 46 + nameLength)])
            guard nameBytes.allSatisfy({ $0 < 0x80 }) else {
                return .failure(.badEntryName)
            }
            let name = String(decoding: nameBytes, as: UTF8.self)
            // Encrypted entries and methods other than stored and deflated are corrupt for this format.
            guard flags & 0x0001 == 0, method == 0 || method == 8 else {
                return .failure(.corruptArchive)
            }
            // ZIP64 sentinels are not supported.
            guard compressed != 0xFFFF_FFFF, uncompressed != 0xFFFF_FFFF, localOffset != 0xFFFF_FFFF else {
                return .failure(.corruptArchive)
            }
            entries.append(Entry(name: name, method: method, flags: flags, crc: crc, compressedSize: compressed, uncompressedSize: uncompressed, localOffset: localOffset))
            cursor += 46 + nameLength + extraLength + commentLength
        }

        var seen = Set<String>()
        var declaredTotal = 0
        for entry in entries {
            if let failure = checkName(entry.name) {
                return .failure(failure)
            }
            guard seen.insert(entry.name.lowercased()).inserted else {
                return .failure(.duplicateEntry)
            }
            declaredTotal += entry.uncompressedSize
        }
        guard declaredTotal <= maxTotalUncompressed else {
            return .failure(.tooLarge)
        }

        var manifest: Data?
        var cover: BGMusicCover?
        var coverSeen = false
        for entry in entries {
            let content: [UInt8]
            switch extract(entry, bytes: bytes) {
            case let .success(value):
                content = value
            case let .failure(error):
                return .failure(error)
            }
            if nestedArchiveSignature(content) {
                return .failure(.badEntryName)
            }
            switch entry.name.lowercased() {
            case "manifest.json":
                guard content.count <= maxManifestBytes else {
                    return .failure(.manifestTooLarge)
                }
                manifest = Data(content)
            case BGMusicCoverKind.webp.rawValue, BGMusicCoverKind.jpg.rawValue, BGMusicCoverKind.png.rawValue:
                if coverSeen {
                    return .failure(.duplicateEntry)
                }
                coverSeen = true
                guard content.count <= maxCoverBytes else {
                    return .failure(.coverTooLarge)
                }
                let kind = BGMusicCoverKind(rawValue: entry.name.lowercased()) ?? .webp
                guard coverMatches(kind, content) else {
                    return .failure(.badCover)
                }
                cover = BGMusicCover(kind: kind, data: Data(content))
            default:
                // Unknown safe entries are skipped so later versions stay readable. They still count against the limits above.
                continue
            }
        }
        guard let manifestData = manifest else {
            return .failure(.missingManifest)
        }
        return .success(BGMusicArchiveContents(manifest: manifestData, cover: cover))
    }

    /// Returns the rule that the name breaks, or nil when the name is safe.
    private static func checkName(_ name: String) -> BGMusicArchiveError? {
        let scalars = Array(name.unicodeScalars)
        guard !scalars.isEmpty, scalars.count <= maxNameLength else {
            return .badEntryName
        }
        guard let first = scalars.first, isAlphaNumeric(first) else {
            return .badEntryName
        }
        for scalar in scalars where !(isAlphaNumeric(scalar) || scalar == "." || scalar == "_" || scalar == "-") {
            return .badEntryName
        }
        if name.contains("..") || name.hasSuffix("/") {
            return .badEntryName
        }
        let lowered = name.lowercased()
        for ext in forbiddenExtensions where lowered.hasSuffix(ext) {
            return .badEntryName
        }
        return nil
    }

    private static func isAlphaNumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
            return true
        default:
            return false
        }
    }

    /// True when the content starts with the signature of an archive or compressed container, which nested
    /// archives are refused for.
    private static func nestedArchiveSignature(_ content: [UInt8]) -> Bool {
        let signatures: [[UInt8]] = [
            [0x50, 0x4B, 0x03, 0x04],
            [0x50, 0x4B, 0x05, 0x06],
            [0x50, 0x4B, 0x07, 0x08],
            [0x1F, 0x8B],
            [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C],
            [0x52, 0x61, 0x72, 0x21],
            [0x42, 0x5A, 0x68],
            [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00],
        ]
        for signature in signatures where content.count >= signature.count && Array(content[0..<signature.count]) == signature {
            return true
        }
        return false
    }

    private static func coverMatches(_ kind: BGMusicCoverKind, _ content: [UInt8]) -> Bool {
        guard !content.isEmpty else {
            return false
        }
        switch kind {
        case .webp:
            return content.count >= 12 && Array(content[0..<4]) == [0x52, 0x49, 0x46, 0x46] && Array(content[8..<12]) == [0x57, 0x45, 0x42, 0x50]
        case .jpg:
            return content.count >= 3 && content[0] == 0xFF && content[1] == 0xD8 && content[2] == 0xFF
        case .png:
            return content.count >= 8 && Array(content[0..<8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        }
    }

    private static func findEndOfCentralDirectory(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else {
            return nil
        }
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        var index = bytes.count - 22
        while index >= lowest {
            if u32(bytes, index) == 0x0605_4B50 {
                return index
            }
            index -= 1
        }
        return nil
    }

    private static func extract(_ entry: Entry, bytes: [UInt8]) -> Result<[UInt8], BGMusicArchiveError> {
        let header = entry.localOffset
        guard header + 30 <= bytes.count, u32(bytes, header) == 0x0403_4B50 else {
            return .failure(.corruptArchive)
        }
        let start = header + 30 + Int(u16(bytes, header + 26)) + Int(u16(bytes, header + 28))
        guard start + entry.compressedSize <= bytes.count else {
            return .failure(.corruptArchive)
        }
        let payload = Array(bytes[start..<(start + entry.compressedSize)])
        let content: [UInt8]
        if entry.method == 0 {
            content = payload
        } else {
            do {
                content = try BGMusicInflate.inflate(payload, limit: entry.uncompressedSize)
            } catch {
                return .failure(.corruptArchive)
            }
        }
        guard content.count == entry.uncompressedSize, BGMusicCRC32.checksum(content) == entry.crc else {
            return .failure(.corruptArchive)
        }
        return .success(content)
    }

    // MARK: Writing

    /// Writes a .bgmusic archive with stored entries. The cover name is taken from its magic bytes, not from the caller.
    public static func write(manifest: Data, cover: BGMusicCover?) -> Result<Data, BGMusicArchiveError> {
        guard manifest.count <= maxManifestBytes else {
            return .failure(.manifestTooLarge)
        }
        var files: [(String, [UInt8])] = [("manifest.json", [UInt8](manifest))]
        if let cover = cover {
            guard cover.data.count <= maxCoverBytes else {
                return .failure(.coverTooLarge)
            }
            let bytes = [UInt8](cover.data)
            guard coverMatches(cover.kind, bytes) else {
                return .failure(.badCover)
            }
            files.append((cover.kind.rawValue, bytes))
        }
        let total = files.reduce(0) { $0 + $1.1.count }
        guard total <= maxTotalUncompressed else {
            return .failure(.tooLarge)
        }

        var out: [UInt8] = []
        var directory: [UInt8] = []
        var offsets: [Int] = []
        for (name, content) in files {
            let nameBytes = Array(name.utf8)
            let crc = BGMusicCRC32.checksum(content)
            offsets.append(out.count)
            appendU32(&out, 0x0403_4B50)
            appendU16(&out, 20)           // version needed
            appendU16(&out, 0)            // flags
            appendU16(&out, 0)            // method: stored
            appendU16(&out, 0)            // time
            appendU16(&out, 0x0021)       // date: 1980-01-01
            appendU32(&out, crc)
            appendU32(&out, UInt32(content.count))
            appendU32(&out, UInt32(content.count))
            appendU16(&out, UInt16(nameBytes.count))
            appendU16(&out, 0)            // extra length
            out.append(contentsOf: nameBytes)
            out.append(contentsOf: content)
        }
        let directoryOffset = out.count
        for (index, (name, content)) in files.enumerated() {
            let nameBytes = Array(name.utf8)
            let crc = BGMusicCRC32.checksum(content)
            appendU32(&directory, 0x0201_4B50)
            appendU16(&directory, 20)     // version made by
            appendU16(&directory, 20)     // version needed
            appendU16(&directory, 0)      // flags
            appendU16(&directory, 0)      // method
            appendU16(&directory, 0)      // time
            appendU16(&directory, 0x0021) // date
            appendU32(&directory, crc)
            appendU32(&directory, UInt32(content.count))
            appendU32(&directory, UInt32(content.count))
            appendU16(&directory, UInt16(nameBytes.count))
            appendU16(&directory, 0)      // extra length
            appendU16(&directory, 0)      // comment length
            appendU16(&directory, 0)      // disk number
            appendU16(&directory, 0)      // internal attributes
            appendU32(&directory, 0)      // external attributes
            appendU32(&directory, UInt32(offsets[index]))
            directory.append(contentsOf: nameBytes)
        }
        out.append(contentsOf: directory)
        appendU32(&out, 0x0605_4B50)
        appendU16(&out, 0)
        appendU16(&out, 0)
        appendU16(&out, UInt16(files.count))
        appendU16(&out, UInt16(files.count))
        appendU32(&out, UInt32(directory.count))
        appendU32(&out, UInt32(directoryOffset))
        appendU16(&out, 0)
        guard out.count <= maxFileBytes else {
            return .failure(.tooLarge)
        }
        return .success(Data(out))
    }

    // MARK: Byte helpers

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        return UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8) | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func appendU16(_ out: inout [UInt8], _ value: UInt16) {
        out.append(UInt8(value & 0xFF))
        out.append(UInt8(value >> 8))
    }

    private static func appendU32(_ out: inout [UInt8], _ value: UInt32) {
        out.append(UInt8(value & 0xFF))
        out.append(UInt8((value >> 8) & 0xFF))
        out.append(UInt8((value >> 16) & 0xFF))
        out.append(UInt8(value >> 24))
    }
}

/// CRC-32 (IEEE 802.3), the checksum ZIP uses.
enum BGMusicCRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
