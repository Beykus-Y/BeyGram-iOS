import Foundation

/// Raw DEFLATE decoder (RFC 1951) for ZIP entries with method 8. Written after zlib's `puff.c` structure.
/// Any malformed input throws; the output never grows past `limit`.
enum BGMusicInflate {
    enum Failure: Error {
        case corrupt
    }

    private static let lengthBase: [Int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distBase: [Int] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distExtra: [Int] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    private static let codeLengthOrder: [Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private struct Huffman {
        var count = [Int](repeating: 0, count: 16)
        var symbol: [Int]

        /// Returns nil when the code lengths are over-subscribed.
        init?(lengths: [Int]) {
            symbol = [Int](repeating: 0, count: lengths.count)
            for length in lengths {
                count[length] += 1
            }
            if count[0] == lengths.count {
                return
            }
            var left = 1
            for length in 1...15 {
                left <<= 1
                left -= count[length]
                if left < 0 {
                    return nil
                }
            }
            var offsets = [Int](repeating: 0, count: 16)
            for length in 1..<15 {
                offsets[length + 1] = offsets[length] + count[length]
            }
            for (sym, length) in lengths.enumerated() where length != 0 {
                symbol[offsets[length]] = sym
                offsets[length] += 1
            }
        }
    }

    private struct Reader {
        let input: [UInt8]
        var position = 0
        var bitBuffer: Int = 0
        var bitCount: Int = 0

        init(input: [UInt8]) {
            self.input = input
        }

        mutating func bit() throws -> Int {
            if bitCount == 0 {
                guard position < input.count else {
                    throw Failure.corrupt
                }
                bitBuffer = Int(input[position])
                position += 1
                bitCount = 8
            }
            let value = bitBuffer & 1
            bitBuffer >>= 1
            bitCount -= 1
            return value
        }

        mutating func bits(_ count: Int) throws -> Int {
            var value = 0
            for index in 0..<count {
                value |= try bit() << index
            }
            return value
        }

        mutating func decode(_ huffman: Huffman) throws -> Int {
            var code = 0
            var first = 0
            var index = 0
            for length in 1...15 {
                code |= try bit()
                let count = huffman.count[length]
                if code - count < first {
                    return huffman.symbol[index + (code - first)]
                }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            throw Failure.corrupt
        }
    }

    static func inflate(_ input: [UInt8], limit: Int) throws -> [UInt8] {
        var reader = Reader(input: input)
        var output: [UInt8] = []
        var last = 0
        repeat {
            last = try reader.bit()
            let type = try reader.bits(2)
            switch type {
            case 0:
                try storedBlock(&reader, &output, limit: limit)
            case 1:
                try fixedBlock(&reader, &output, limit: limit)
            case 2:
                try dynamicBlock(&reader, &output, limit: limit)
            default:
                throw Failure.corrupt
            }
        } while last == 0
        return output
    }

    private static func storedBlock(_ reader: inout Reader, _ output: inout [UInt8], limit: Int) throws {
        reader.bitBuffer = 0
        reader.bitCount = 0
        guard reader.position + 4 <= reader.input.count else {
            throw Failure.corrupt
        }
        let length = Int(reader.input[reader.position]) | (Int(reader.input[reader.position + 1]) << 8)
        let inverted = Int(reader.input[reader.position + 2]) | (Int(reader.input[reader.position + 3]) << 8)
        reader.position += 4
        guard length == (~inverted & 0xFFFF) else {
            throw Failure.corrupt
        }
        guard reader.position + length <= reader.input.count, output.count + length <= limit else {
            throw Failure.corrupt
        }
        output.append(contentsOf: reader.input[reader.position..<(reader.position + length)])
        reader.position += length
    }

    private static func fixedBlock(_ reader: inout Reader, _ output: inout [UInt8], limit: Int) throws {
        var lengths = [Int](repeating: 8, count: 288)
        for index in 144..<256 {
            lengths[index] = 9
        }
        for index in 256..<280 {
            lengths[index] = 7
        }
        guard let literal = Huffman(lengths: lengths), let distance = Huffman(lengths: [Int](repeating: 5, count: 30)) else {
            throw Failure.corrupt
        }
        try codes(&reader, &output, literal: literal, distance: distance, limit: limit)
    }

    private static func dynamicBlock(_ reader: inout Reader, _ output: inout [UInt8], limit: Int) throws {
        let literalCount = try reader.bits(5) + 257
        let distanceCount = try reader.bits(5) + 1
        let codeCount = try reader.bits(4) + 4
        guard literalCount <= 286, distanceCount <= 30 else {
            throw Failure.corrupt
        }
        var codeLengths = [Int](repeating: 0, count: 19)
        for index in 0..<codeCount {
            codeLengths[codeCodeIndex(index)] = try reader.bits(3)
        }
        guard let lengthCode = Huffman(lengths: codeLengths) else {
            throw Failure.corrupt
        }
        var lengths: [Int] = []
        let total = literalCount + distanceCount
        while lengths.count < total {
            let symbol = try reader.decode(lengthCode)
            if symbol < 16 {
                lengths.append(symbol)
            } else if symbol == 16 {
                guard let previous = lengths.last else {
                    throw Failure.corrupt
                }
                let repeats = try 3 + reader.bits(2)
                lengths.append(contentsOf: [Int](repeating: previous, count: repeats))
            } else if symbol == 17 {
                let zeros = try 3 + reader.bits(3)
                lengths.append(contentsOf: [Int](repeating: 0, count: zeros))
            } else {
                let zeros = try 11 + reader.bits(7)
                lengths.append(contentsOf: [Int](repeating: 0, count: zeros))
            }
        }
        guard lengths.count == total, lengths[256] != 0 else {
            throw Failure.corrupt
        }
        guard let literal = Huffman(lengths: Array(lengths[0..<literalCount])),
              let distance = Huffman(lengths: Array(lengths[literalCount..<total])) else {
            throw Failure.corrupt
        }
        try codes(&reader, &output, literal: literal, distance: distance, limit: limit)
    }

    private static func codeCodeIndex(_ index: Int) -> Int {
        return codeLengthOrder[index]
    }

    private static func codes(_ reader: inout Reader, _ output: inout [UInt8], literal: Huffman, distance: Huffman, limit: Int) throws {
        while true {
            let symbol = try reader.decode(literal)
            if symbol < 256 {
                guard output.count < limit else {
                    throw Failure.corrupt
                }
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let lengthIndex = symbol - 257
                guard lengthIndex < 29 else {
                    throw Failure.corrupt
                }
                let length = try lengthBase[lengthIndex] + reader.bits(lengthExtra[lengthIndex])
                let distanceSymbol = try reader.decode(distance)
                guard distanceSymbol < 30 else {
                    throw Failure.corrupt
                }
                let distanceValue = try distBase[distanceSymbol] + reader.bits(distExtra[distanceSymbol])
                guard distanceValue <= output.count, output.count + length <= limit else {
                    throw Failure.corrupt
                }
                for _ in 0..<length {
                    output.append(output[output.count - distanceValue])
                }
            }
        }
    }
}
