import Foundation

/// Errors from `ChatExportZipWriter`. After any of them the archive is incomplete, and the caller deletes it.
public enum ChatExportZipError: Error, Equatable {
    /// `beginEntry` was called while another entry is still open.
    case entryAlreadyOpen
    /// `write` or `endEntry` was called with no entry open.
    case noOpenEntry
    /// The archive is already finished.
    case finished
    /// The entry name is empty, starts with `/`, or is too long for its header field.
    case invalidName
    /// The archive would not fit the 32-bit or 16-bit ZIP fields. ZIP64 is not written.
    case limitExceeded
}

/// Writes a ZIP archive into a `ChatExportSink` as it goes, so no entry is held in memory.
///
/// Entries are stored without compression (method 0). Each entry has a local header with the
/// data-descriptor flag set, then its bytes, then a descriptor with the CRC-32 and the sizes. The
/// central directory comes after the last entry. Streaming writers use this layout when the sizes
/// are not known in advance, and archive tools read it. Names are UTF-8 (flag bit 11).
///
/// Call `beginEntry`, then `write` as often as needed, then `endEntry`, once per entry. Call `finish`
/// once at the end. Any error leaves the archive incomplete, so the caller must delete or truncate it.
public final class ChatExportZipWriter {
    private static let localHeaderSignature: UInt32 = 0x0403_4B50
    private static let dataDescriptorSignature: UInt32 = 0x0807_4B50
    private static let centralDirectorySignature: UInt32 = 0x0201_4B50
    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4B50
    /// Version 2.0 is the minimum that allows a data descriptor.
    private static let versionNeeded: UInt16 = 20
    /// Bit 3 marks a data descriptor after the data. Bit 11 marks UTF-8 names.
    private static let generalPurposeFlags: UInt16 = 0x0808
    private static let storedMethod: UInt16 = 0

    private struct OpenEntry {
        let name: Data
        let localOffset: UInt32
        let dosTime: UInt16
        let dosDate: UInt16
        /// Running CRC-32 before the final inversion.
        var crc: UInt32 = 0xFFFF_FFFF
        var size: UInt64 = 0
    }

    private struct CentralEntry {
        let name: Data
        let crc: UInt32
        let size: UInt32
        let localOffset: UInt32
        let dosTime: UInt16
        let dosDate: UInt16
    }

    private let sink: ChatExportSink
    private let calendar: Calendar
    private var offset: UInt64 = 0
    private var entries: [CentralEntry] = []
    private var currentEntry: OpenEntry?
    private var isFinished = false

    /// `calendar` turns entry dates into the local-time DOS date and time fields.
    public init(sink: ChatExportSink, calendar: Calendar = .current) {
        self.sink = sink
        self.calendar = calendar
    }

    /// Starts an entry. `modified` is stored in its header.
    public func beginEntry(name: String, modified: Date) throws {
        guard !isFinished else {
            throw ChatExportZipError.finished
        }
        guard currentEntry == nil else {
            throw ChatExportZipError.entryAlreadyOpen
        }
        let nameData = Data(name.utf8)
        guard !name.isEmpty, !name.hasPrefix("/"), nameData.count <= Int(UInt16.max) else {
            throw ChatExportZipError.invalidName
        }
        guard entries.count < Int(UInt16.max), offset <= UInt64(UInt32.max) else {
            throw ChatExportZipError.limitExceeded
        }
        let (dosTime, dosDate) = Self.dosDateTime(modified, calendar: calendar)
        let localOffset = UInt32(offset)
        var header = Data()
        Self.appendUInt32(Self.localHeaderSignature, to: &header)
        Self.appendUInt16(Self.versionNeeded, to: &header)
        Self.appendUInt16(Self.generalPurposeFlags, to: &header)
        Self.appendUInt16(Self.storedMethod, to: &header)
        Self.appendUInt16(dosTime, to: &header)
        Self.appendUInt16(dosDate, to: &header)
        // The CRC and the sizes are zero here. The data descriptor after the bytes holds them.
        Self.appendUInt32(0, to: &header)
        Self.appendUInt32(0, to: &header)
        Self.appendUInt32(0, to: &header)
        Self.appendUInt16(UInt16(nameData.count), to: &header)
        Self.appendUInt16(0, to: &header)
        header.append(nameData)
        try emit(header)
        currentEntry = OpenEntry(name: nameData, localOffset: localOffset, dosTime: dosTime, dosDate: dosDate)
    }

    /// Appends bytes to the open entry.
    public func write(_ data: Data) throws {
        guard !isFinished else {
            throw ChatExportZipError.finished
        }
        guard var entry = currentEntry else {
            throw ChatExportZipError.noOpenEntry
        }
        guard entry.size + UInt64(data.count) <= UInt64(UInt32.max) else {
            throw ChatExportZipError.limitExceeded
        }
        entry.crc = Self.crcUpdate(entry.crc, data)
        entry.size += UInt64(data.count)
        currentEntry = entry
        try emit(data)
    }

    /// Closes the open entry and writes its data descriptor.
    public func endEntry() throws {
        guard !isFinished else {
            throw ChatExportZipError.finished
        }
        guard let entry = currentEntry else {
            throw ChatExportZipError.noOpenEntry
        }
        // `write` keeps the size within UInt32, so the conversion cannot trap.
        let size = UInt32(entry.size)
        let crc = ~entry.crc
        var descriptor = Data()
        Self.appendUInt32(Self.dataDescriptorSignature, to: &descriptor)
        Self.appendUInt32(crc, to: &descriptor)
        Self.appendUInt32(size, to: &descriptor)
        Self.appendUInt32(size, to: &descriptor)
        try emit(descriptor)
        entries.append(CentralEntry(
            name: entry.name,
            crc: crc,
            size: size,
            localOffset: entry.localOffset,
            dosTime: entry.dosTime,
            dosDate: entry.dosDate
        ))
        currentEntry = nil
    }

    /// Writes a whole entry from memory. Use `beginEntry`, `write` and `endEntry` for large content.
    public func addEntry(name: String, modified: Date, contents: Data) throws {
        try beginEntry(name: name, modified: modified)
        try write(contents)
        try endEntry()
    }

    /// Writes the central directory and the end record. Call once, after the last entry.
    public func finish() throws {
        guard !isFinished else {
            throw ChatExportZipError.finished
        }
        guard currentEntry == nil else {
            throw ChatExportZipError.entryAlreadyOpen
        }
        guard offset <= UInt64(UInt32.max) else {
            throw ChatExportZipError.limitExceeded
        }
        let centralOffset = offset
        var directory = Data()
        for entry in entries {
            Self.appendUInt32(Self.centralDirectorySignature, to: &directory)
            Self.appendUInt16(Self.versionNeeded, to: &directory)
            Self.appendUInt16(Self.versionNeeded, to: &directory)
            Self.appendUInt16(Self.generalPurposeFlags, to: &directory)
            Self.appendUInt16(Self.storedMethod, to: &directory)
            Self.appendUInt16(entry.dosTime, to: &directory)
            Self.appendUInt16(entry.dosDate, to: &directory)
            Self.appendUInt32(entry.crc, to: &directory)
            Self.appendUInt32(entry.size, to: &directory)
            Self.appendUInt32(entry.size, to: &directory)
            Self.appendUInt16(UInt16(entry.name.count), to: &directory)
            Self.appendUInt16(0, to: &directory)
            Self.appendUInt16(0, to: &directory)
            Self.appendUInt16(0, to: &directory)
            Self.appendUInt16(0, to: &directory)
            Self.appendUInt32(0, to: &directory)
            Self.appendUInt32(entry.localOffset, to: &directory)
            directory.append(entry.name)
        }
        try emit(directory)
        let directorySize = offset - centralOffset
        guard directorySize <= UInt64(UInt32.max) else {
            throw ChatExportZipError.limitExceeded
        }
        var end = Data()
        Self.appendUInt32(Self.endOfCentralDirectorySignature, to: &end)
        Self.appendUInt16(0, to: &end)
        Self.appendUInt16(0, to: &end)
        Self.appendUInt16(UInt16(entries.count), to: &end)
        Self.appendUInt16(UInt16(entries.count), to: &end)
        Self.appendUInt32(UInt32(directorySize), to: &end)
        Self.appendUInt32(UInt32(centralOffset), to: &end)
        Self.appendUInt16(0, to: &end)
        try emit(end)
        isFinished = true
    }

    /// CRC-32 with the ZIP polynomial, of the whole buffer. `crc32(of: "123456789")` is `0xCBF43926`.
    public static func crc32(of data: Data) -> UInt32 {
        ~crcUpdate(0xFFFF_FFFF, data)
    }

    // MARK: - Private

    private func emit(_ data: Data) throws {
        try sink.write(data)
        offset += UInt64(data.count)
    }

    private static func crcUpdate(_ crc: UInt32, _ data: Data) -> UInt32 {
        var value = crc
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for byte in bytes {
                value = crcTable[Int((value ^ UInt32(byte)) & 0xFF)] ^ (value >> 8)
            }
        }
        return value
    }

    private static let crcTable: [UInt32] = (0 ..< 256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0 ..< 8 {
            value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    /// MS-DOS time and date fields in local time. Dates before 1980 are written as 1980.
    private static func dosDateTime(_ date: Date, calendar: Calendar) -> (time: UInt16, date: UInt16) {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = min(max((parts.year ?? 1980) - 1980, 0), 127)
        let month = min(max(parts.month ?? 1, 1), 12)
        let day = min(max(parts.day ?? 1, 1), 31)
        let hour = min(max(parts.hour ?? 0, 0), 23)
        let minute = min(max(parts.minute ?? 0, 0), 59)
        let second = min(max(parts.second ?? 0, 0), 59) / 2
        let dosDate = (year << 9) | (month << 5) | day
        let dosTime = (hour << 11) | (minute << 5) | second
        return (UInt16(dosTime), UInt16(dosDate))
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        appendUInt16(UInt16(truncatingIfNeeded: value), to: &data)
        appendUInt16(UInt16(truncatingIfNeeded: value >> 16), to: &data)
    }
}

/// A sink that writes into the open entry of a `ChatExportZipWriter`, so a document can stream into the archive.
public final class ChatExportZipEntrySink: ChatExportSink {
    private let zip: ChatExportZipWriter

    public init(zip: ChatExportZipWriter) {
        self.zip = zip
    }

    public func write(_ data: Data) throws {
        try zip.write(data)
    }
}
