import Foundation

public struct ChatExportProgress: Equatable {
    public var processedMessages: Int
    public var exportedMessages: Int
    public var pagesLoaded: Int
}

/// Drives a `ChatExportWriter` from a paged history source, with progress and cancellation.
///
/// `nextPage` returns the next page of messages (100 per request in the app, newest first), or an
/// empty array when the history is exhausted. Messages are written in the order they arrive, so the
/// output is newest first. Each page is written before the next is requested.
///
/// On cancellation or any error, `cleanup` runs and the error is rethrown. The app's cleanup deletes
/// the destination document, or truncates it when the provider refuses deletion.
public final class ChatExportJob {
    private let writer: ChatExportWriter
    private let cleanup: () -> Void
    private let onProgress: (ChatExportProgress) -> Void
    private var progress = ChatExportProgress(processedMessages: 0, exportedMessages: 0, pagesLoaded: 0)

    public init(writer: ChatExportWriter, cleanup: @escaping () -> Void, onProgress: @escaping (ChatExportProgress) -> Void) {
        self.writer = writer
        self.cleanup = cleanup
        self.onProgress = onProgress
    }

    public func run(nextPage: () async throws -> [ChatExportMessage]) async throws -> ChatExportSummary {
        do {
            try writer.begin()
            while true {
                try Task.checkCancellation()
                let page = try await nextPage()
                if page.isEmpty {
                    break
                }
                progress.pagesLoaded += 1
                for message in page {
                    progress.processedMessages += 1
                    if try writer.append(message) {
                        progress.exportedMessages += 1
                    }
                }
                onProgress(progress)
            }
            return try writer.finish()
        } catch {
            cleanup()
            throw error
        }
    }
}
