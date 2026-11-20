import Foundation

/// The message history, newest first, in pages as the app loads them (100 per request).
public protocol ChatExportHistory: AnyObject {
    /// The next page, or an empty array when the history is exhausted.
    func nextPage() async throws -> [ChatExportMessage]
    /// Starts again from the newest message. Called only when the document does not fit the buffer.
    func rewind() async throws
}

/// Writes the chat as a ZIP holding the document and the media of its messages. This is the Android `writeZip` flow.
///
/// One walk of the history copies each media file when its message is reached, and renders the document into a buffer
/// of `documentBufferBytes`. The document entry follows the media entries, as on Android. When the document does not fit
/// the buffer, the history is walked again and the document is written straight into its entry; the media is not copied twice.
///
/// On cancellation or any error, `cleanup` runs and the error is rethrown. The app deletes the destination, or truncates
/// it when deleting is refused. Run a job once.
public final class ChatExportArchiveJob {
    private let format: ChatExportFormat
    private let header: ChatExportHeader
    private let range: ChatExportRange
    private let history: ChatExportHistory
    private let files: ChatExportFileProvider
    private let destination: ChatExportSink
    private let documentBufferBytes: Int
    private let calendar: Calendar
    private let cleanup: () -> Void
    private let onProgress: (ChatExportProgress) -> Void
    private var budget: ChatExportMediaBudget
    private var linkedPaths: [Int64: String] = [:]
    private var mediaFiles = 0
    private var skippedMedia = 0
    private var progress = ChatExportProgress(processedMessages: 0, exportedMessages: 0, pagesLoaded: 0)

    public init(
        format: ChatExportFormat,
        header: ChatExportHeader,
        range: ChatExportRange,
        history: ChatExportHistory,
        files: ChatExportFileProvider,
        destination: ChatExportSink,
        limits: ChatExportMediaLimits = .standard,
        documentBufferBytes: Int = 16 * 1024 * 1024,
        calendar: Calendar = .current,
        cleanup: @escaping () -> Void,
        onProgress: @escaping (ChatExportProgress) -> Void
    ) {
        self.format = format
        var archiveHeader = header
        // An archive holds media, so its document says so, as the Android export does.
        archiveHeader.mediaRequested = true
        self.header = archiveHeader
        self.range = range
        self.history = history
        self.files = files
        self.destination = destination
        self.documentBufferBytes = documentBufferBytes
        self.calendar = calendar
        self.cleanup = cleanup
        self.onProgress = onProgress
        self.budget = ChatExportMediaBudget(limits: limits)
    }

    public func run() async throws -> ChatExportSummary {
        do {
            return try await execute()
        } catch {
            cleanup()
            throw error
        }
    }

    private func execute() async throws -> ChatExportSummary {
        let archive = ChatExportZipWriter(sink: destination, calendar: calendar)

        // Pass one: copy each media file as its message is reached, and render the document into the buffer.
        let rendered = ChatExportBufferSink(limit: documentBufferBytes)
        let renderWriter = ChatExportWriter(format: format, header: header, range: range, sink: rendered)
        try renderWriter.begin()
        try await walk(writer: renderWriter, archive: archive)
        // The media counts are final once the first pass has copied every file, so the document carries them.
        let summary = try renderWriter.finish(mediaFiles: mediaFiles, skippedMedia: skippedMedia)

        // The document entry follows the media entries, as on Android.
        // Android stamps every entry with the time it is written, so the document takes the current time too.
        try archive.beginEntry(name: "messages.\(format.fileExtension)", modified: Date())
        if rendered.overflowed {
            // Too large to keep in memory: walk the history again and write the document into its entry.
            // The media is already archived, so nothing is copied again.
            try await history.rewind()
            let entryWriter = ChatExportWriter(
                format: format,
                header: header,
                range: range,
                sink: ChatExportZipEntrySink(zip: archive)
            )
            try entryWriter.begin()
            try await walk(writer: entryWriter, archive: nil)
            _ = try entryWriter.finish(mediaFiles: mediaFiles, skippedMedia: skippedMedia)
        } else {
            try rendered.writeKept(to: ChatExportZipEntrySink(zip: archive))
        }
        try archive.endEntry()
        try archive.finish()

        return summary
    }

    /// Walks the history newest first and feeds every message to `writer`. With `archive` set, the file of each accepted
    /// message is copied first and its archive path is passed on. Without it, the path recorded in pass one is reused.
    private func walk(writer: ChatExportWriter, archive: ChatExportZipWriter?) async throws {
        // Progress counts the first pass only, so the second pass does not count the history twice.
        let isFirstPass = archive != nil
        while true {
            try Task.checkCancellation()
            let page = try await history.nextPage()
            if page.isEmpty {
                break
            }
            if isFirstPass {
                progress.pagesLoaded += 1
            }
            for message in page {
                if isFirstPass {
                    progress.processedMessages += 1
                }
                var mediaPath: String?
                if writer.accepts(message) {
                    if let archive, let attachment = message.attachment {
                        mediaPath = try await copyMedia(
                            attachment,
                            messageId: message.id,
                            into: archive
                        )
                    } else {
                        mediaPath = linkedPaths[message.id]
                    }
                }
                let appended = try writer.append(message, mediaPath: mediaPath)
                if appended, isFirstPass {
                    progress.exportedMessages += 1
                }
            }
            if isFirstPass {
                publishProgress()
            }
        }
    }

    /// Copies one file into the archive if the limits allow it. Returns its archive path, or nil when the file is skipped.
    private func copyMedia(
        _ attachment: ChatExportAttachment,
        messageId: Int64,
        into archive: ChatExportZipWriter
    ) async throws -> String? {
        guard budget.hasRoomForAnotherFile else {
            skipMedia()
            return nil
        }
        guard let stream = try await openQuietly(attachment, reserveDownload: { self.budget.reserveDownload(size: $0) }) else {
            skipMedia()
            return nil
        }
        defer {
            stream.close()
        }
        let entryName = ChatExportFileName.mediaEntryName(messageId: messageId, attachment: attachment)
        // Each media entry takes the time it is written, as on Android.
        try archive.beginEntry(name: entryName, modified: Date())
        while let chunk = try await stream.readChunk() {
            try Task.checkCancellation()
            try archive.write(chunk)
        }
        try archive.endEntry()
        budget.recordCopied()
        mediaFiles += 1
        linkedPaths[messageId] = entryName
        return entryName
    }

    /// Opens a file for the archive. A nil result or any error other than cancellation skips the file, as on Android.
    private func openQuietly(
        _ attachment: ChatExportAttachment,
        reserveDownload: (_ size: Int64) -> Bool
    ) async throws -> ChatExportFileStream? {
        do {
            return try await files.openFile(for: attachment, reserveDownload: reserveDownload)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private func skipMedia() {
        skippedMedia += 1
    }

    private func publishProgress() {
        var snapshot = progress
        snapshot.mediaCopied = mediaFiles
        snapshot.mediaSkipped = skippedMedia
        onProgress(snapshot)
    }
}
