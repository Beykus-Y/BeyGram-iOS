import Foundation

/// A parsed JSON value. Object members keep their order and are checked for duplicate keys at parse time.
public indirect enum BGMusicJSONValue: Equatable {
    case null
    case bool(Bool)
    /// The number as written, so integers beyond 2^53 are kept exactly.
    case number(String)
    case string(String)
    case array([BGMusicJSONValue])
    case object([(String, BGMusicJSONValue)])

    public static func == (lhs: BGMusicJSONValue, rhs: BGMusicJSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null):
            return true
        case let (.bool(a), .bool(b)):
            return a == b
        case let (.number(a), .number(b)):
            return a == b
        case let (.string(a), .string(b)):
            return a == b
        case let (.array(a), .array(b)):
            return a == b
        case let (.object(a), .object(b)):
            guard a.count == b.count else {
                return false
            }
            for (left, right) in zip(a, b) where left.0 != right.0 || left.1 != right.1 {
                return false
            }
            return true
        default:
            return false
        }
    }

    public subscript(key: String) -> BGMusicJSONValue? {
        guard case let .object(members) = self else {
            return nil
        }
        return members.first(where: { $0.0 == key })?.1
    }
}

/// Strict JSON parser, RFC 8259, for `manifest.json`.
///
/// Rejects: single quotes, comments, trailing commas, bare words, data after the value, raw control characters
/// inside strings, duplicate keys in one object, and nesting deeper than `maxDepth`. A leading UTF-8 BOM is dropped.
/// Input must be valid UTF-8.
public struct BGMusicStrictJSON {
    public static let maxDepth = 16

    public enum Failure: Error, Equatable {
        case invalid
        case duplicateKey
        case tooDeep
    }

    private let bytes: [UInt8]
    private var pos = 0

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    public static func parse(_ data: Data) -> Result<BGMusicJSONValue, Failure> {
        var bytes = [UInt8](data)
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            bytes.removeFirst(3)
        }
        guard isValidUTF8(bytes) else {
            return .failure(.invalid)
        }
        var parser = BGMusicStrictJSON(bytes: bytes)
        do {
            parser.skipWhitespace()
            let value = try parser.parseValue(depth: 0)
            parser.skipWhitespace()
            guard parser.pos == parser.bytes.count else {
                return .failure(.invalid)
            }
            return .success(value)
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.invalid)
        }
    }

    /// UTF-8 validation without relying on C strings (which stop at NUL).
    private static func isValidUTF8(_ bytes: [UInt8]) -> Bool {
        return String(bytes: bytes, encoding: .utf8) != nil
    }

    private mutating func skipWhitespace() {
        while pos < bytes.count {
            switch bytes[pos] {
            case 0x20, 0x09, 0x0A, 0x0D:
                pos += 1
            default:
                return
            }
        }
    }

    private mutating func parseValue(depth: Int) throws -> BGMusicJSONValue {
        guard pos < bytes.count else {
            throw Failure.invalid
        }
        switch bytes[pos] {
        case 0x7B:
            return try parseObject(depth: depth + 1)
        case 0x5B:
            return try parseArray(depth: depth + 1)
        case 0x22:
            return .string(try parseString())
        case 0x74:
            try expectWord("true")
            return .bool(true)
        case 0x66:
            try expectWord("false")
            return .bool(false)
        case 0x6E:
            try expectWord("null")
            return .null
        case 0x2D, 0x30...0x39:
            return .number(try parseNumber())
        default:
            throw Failure.invalid
        }
    }

    private mutating func expectWord(_ word: String) throws {
        let expected = Array(word.utf8)
        guard pos + expected.count <= bytes.count, Array(bytes[pos..<(pos + expected.count)]) == expected else {
            throw Failure.invalid
        }
        pos += expected.count
    }

    private mutating func parseObject(depth: Int) throws -> BGMusicJSONValue {
        guard depth <= BGMusicStrictJSON.maxDepth else {
            throw Failure.tooDeep
        }
        pos += 1 // {
        skipWhitespace()
        var members: [(String, BGMusicJSONValue)] = []
        // Keys are compared by their UTF-8 bytes, as the Android reader compares them. Canonically equivalent spellings
        // (precomposed and decomposed) are therefore different keys here too, not duplicates.
        var keys = Set<[UInt8]>()
        if pos < bytes.count, bytes[pos] == 0x7D {
            pos += 1
            return .object(members)
        }
        while true {
            skipWhitespace()
            guard pos < bytes.count, bytes[pos] == 0x22 else {
                throw Failure.invalid
            }
            let key = try parseString()
            guard keys.insert(Array(key.utf8)).inserted else {
                throw Failure.duplicateKey
            }
            skipWhitespace()
            guard pos < bytes.count, bytes[pos] == 0x3A else {
                throw Failure.invalid
            }
            pos += 1
            skipWhitespace()
            let value = try parseValue(depth: depth)
            members.append((key, value))
            skipWhitespace()
            guard pos < bytes.count else {
                throw Failure.invalid
            }
            if bytes[pos] == 0x2C {
                pos += 1
                continue
            }
            if bytes[pos] == 0x7D {
                pos += 1
                return .object(members)
            }
            throw Failure.invalid
        }
    }

    private mutating func parseArray(depth: Int) throws -> BGMusicJSONValue {
        guard depth <= BGMusicStrictJSON.maxDepth else {
            throw Failure.tooDeep
        }
        pos += 1 // [
        skipWhitespace()
        var items: [BGMusicJSONValue] = []
        if pos < bytes.count, bytes[pos] == 0x5D {
            pos += 1
            return .array(items)
        }
        while true {
            skipWhitespace()
            items.append(try parseValue(depth: depth))
            skipWhitespace()
            guard pos < bytes.count else {
                throw Failure.invalid
            }
            if bytes[pos] == 0x2C {
                pos += 1
                continue
            }
            if bytes[pos] == 0x5D {
                pos += 1
                return .array(items)
            }
            throw Failure.invalid
        }
    }

    private mutating func parseNumber() throws -> String {
        let start = pos
        if bytes[pos] == 0x2D {
            pos += 1
        }
        guard pos < bytes.count else {
            throw Failure.invalid
        }
        if bytes[pos] == 0x30 {
            pos += 1
        } else if bytes[pos] >= 0x31 && bytes[pos] <= 0x39 {
            while pos < bytes.count, bytes[pos] >= 0x30, bytes[pos] <= 0x39 {
                pos += 1
            }
        } else {
            throw Failure.invalid
        }
        if pos < bytes.count, bytes[pos] == 0x2E {
            pos += 1
            let digitsStart = pos
            while pos < bytes.count, bytes[pos] >= 0x30, bytes[pos] <= 0x39 {
                pos += 1
            }
            guard pos > digitsStart else {
                throw Failure.invalid
            }
        }
        if pos < bytes.count, bytes[pos] == 0x65 || bytes[pos] == 0x45 {
            pos += 1
            if pos < bytes.count, bytes[pos] == 0x2B || bytes[pos] == 0x2D {
                pos += 1
            }
            let digitsStart = pos
            while pos < bytes.count, bytes[pos] >= 0x30, bytes[pos] <= 0x39 {
                pos += 1
            }
            guard pos > digitsStart else {
                throw Failure.invalid
            }
        }
        return String(decoding: bytes[start..<pos], as: UTF8.self)
    }

    private mutating func parseHex4() throws -> UInt32 {
        guard pos + 4 <= bytes.count else {
            throw Failure.invalid
        }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[pos]
            pos += 1
            value <<= 4
            switch byte {
            case 0x30...0x39:
                value |= UInt32(byte - 0x30)
            case 0x41...0x46:
                value |= UInt32(byte - 0x41 + 10)
            case 0x61...0x66:
                value |= UInt32(byte - 0x61 + 10)
            default:
                throw Failure.invalid
            }
        }
        return value
    }

    private mutating func parseString() throws -> String {
        pos += 1 // opening quote
        var scalars = String.UnicodeScalarView()
        while true {
            guard pos < bytes.count else {
                throw Failure.invalid
            }
            let byte = bytes[pos]
            if byte == 0x22 {
                pos += 1
                return String(scalars)
            }
            if byte < 0x20 {
                throw Failure.invalid
            }
            if byte == 0x5C {
                pos += 1
                guard pos < bytes.count else {
                    throw Failure.invalid
                }
                let escape = bytes[pos]
                pos += 1
                switch escape {
                case 0x22: scalars.append("\"")
                case 0x5C: scalars.append("\\")
                case 0x2F: scalars.append("/")
                case 0x62: scalars.append("\u{08}")
                case 0x66: scalars.append("\u{0C}")
                case 0x6E: scalars.append("\n")
                case 0x72: scalars.append("\r")
                case 0x74: scalars.append("\t")
                case 0x75:
                    let high = try parseHex4()
                    if high >= 0xD800 && high <= 0xDBFF {
                        guard pos + 6 <= bytes.count, bytes[pos] == 0x5C, bytes[pos + 1] == 0x75 else {
                            throw Failure.invalid
                        }
                        pos += 2
                        let low = try parseHex4()
                        guard low >= 0xDC00 && low <= 0xDFFF else {
                            throw Failure.invalid
                        }
                        let codePoint = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
                        guard let scalar = Unicode.Scalar(codePoint) else {
                            throw Failure.invalid
                        }
                        scalars.append(scalar)
                    } else {
                        guard let scalar = Unicode.Scalar(high) else {
                            // Lone low surrogate: not valid text.
                            throw Failure.invalid
                        }
                        scalars.append(scalar)
                    }
                default:
                    throw Failure.invalid
                }
                continue
            }
            // Plain UTF-8 sequence: copy the whole scalar.
            let length: Int
            if byte < 0x80 {
                length = 1
            } else if byte >= 0xC2 && byte <= 0xDF {
                length = 2
            } else if byte >= 0xE0 && byte <= 0xEF {
                length = 3
            } else if byte >= 0xF0 && byte <= 0xF4 {
                length = 4
            } else {
                throw Failure.invalid
            }
            guard pos + length <= bytes.count else {
                throw Failure.invalid
            }
            // `parse` checked the whole input as UTF-8, so this sequence is valid and only needs decoding.
            var codePoint = UInt32(byte)
            if length == 2 {
                let b1 = UInt32(bytes[pos + 1]) & 0x3F
                codePoint = ((UInt32(byte) & 0x1F) << 6) | b1
            } else if length == 3 {
                let b1 = UInt32(bytes[pos + 1]) & 0x3F
                let b2 = UInt32(bytes[pos + 2]) & 0x3F
                codePoint = ((UInt32(byte) & 0x0F) << 12) | (b1 << 6) | b2
            } else if length == 4 {
                let b1 = UInt32(bytes[pos + 1]) & 0x3F
                let b2 = UInt32(bytes[pos + 2]) & 0x3F
                let b3 = UInt32(bytes[pos + 3]) & 0x3F
                codePoint = ((UInt32(byte) & 0x07) << 18) | (b1 << 12) | (b2 << 6) | b3
            }
            guard let scalar = Unicode.Scalar(codePoint) else {
                throw Failure.invalid
            }
            scalars.append(scalar)
            pos += length
        }
    }
}
