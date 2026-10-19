import Foundation
import ImageIO
import AVFoundation
import UIKit

enum BeyGramOutgoingKind: String, Equatable {
    case photo
    case video
    case document
}

struct BeyGramOutgoingAttachment: Identifiable, Equatable {
    let id: UUID
    let kind: BeyGramOutgoingKind
    let localURL: URL
    let displayName: String
    let sizeBytes: Int64
    let width: Int
    let height: Int
    let durationSeconds: Int

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

enum BeyGramAttachmentPreparationError: LocalizedError {
    case unreadable
    case unsupportedPhoto
    case unsupportedVideo
    case tooLarge
    case emptyFile
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .unreadable: return "Не удалось прочитать выбранный файл."
        case .unsupportedPhoto: return "Не удалось подготовить фотографию."
        case .unsupportedVideo: return "Не удалось преобразовать видео в MP4 (H.264)."
        case .tooLarge: return "Для этого тестового этапа файл должен быть меньше 200 МБ."
        case .emptyFile: return "Пустые файлы пока не поддерживаются."
        case .invalidFile: return "Это не обычный файл."
        }
    }
}

/// Mirrors Android's OutgoingMediaImporter. Always stage files inside the app
/// sandbox before asking TDLib to upload them; never rely on a temporary
/// security-scoped provider URL remaining valid after the picker closes.
enum BeyGramOutgoingMediaImporter {
    private static let maximumDocumentBytes: Int64 = 200 * 1024 * 1024
    private static let maximumPhotoBytes = 10 * 1024 * 1024

    static func preparePhoto(_ data: Data) async throws -> BeyGramOutgoingAttachment {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                throw BeyGramAttachmentPreparationError.unsupportedPhoto
            }
            // Downsampling limits decoded RAM and avoids sending giant images.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2560,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(
                source, 0, options as CFDictionary
            ) else {
                throw BeyGramAttachmentPreparationError.unsupportedPhoto
            }
            let photo = UIImage(cgImage: cg)
            var compressed: Data?
            for quality in [0.85, 0.7, 0.55] {
                guard let jpeg = photo.jpegData(compressionQuality: quality) else { continue }
                compressed = jpeg
                if jpeg.count <= maximumPhotoBytes { break }
            }
            guard let compressed, !compressed.isEmpty,
                  compressed.count <= maximumPhotoBytes else {
                throw BeyGramAttachmentPreparationError.unsupportedPhoto
            }

            let id = UUID()
            let folder = try stagedDirectory(for: id)
            let file = folder.appendingPathComponent("photo.jpg")
            try compressed.write(to: file, options: .atomic)
            return BeyGramOutgoingAttachment(
                id: id, kind: .photo, localURL: file,
                displayName: "Фото.jpg",
                sizeBytes: Int64(compressed.count), width: cg.width, height: cg.height,
                durationSeconds: 0
            )
        }.value
    }

    static func prepareDocument(_ providerURL: URL) async throws -> BeyGramOutgoingAttachment {
        try await Task.detached(priority: .userInitiated) {
            let authorized = providerURL.startAccessingSecurityScopedResource()
            defer {
                if authorized { providerURL.stopAccessingSecurityScopedResource() }
            }
            let resource = try providerURL.resourceValues(forKeys: [
                .isRegularFileKey, .fileSizeKey
            ])
            guard resource.isRegularFile == true else {
                throw BeyGramAttachmentPreparationError.invalidFile
            }
            let size = Int64(resource.fileSize ?? 0)
            guard size > 0 else { throw BeyGramAttachmentPreparationError.emptyFile }
            guard size <= maximumDocumentBytes else {
                throw BeyGramAttachmentPreparationError.tooLarge
            }
            let id = UUID()
            let directory = try stagedDirectory(for: id)
            let local = directory.appendingPathComponent(providerURL.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: providerURL, to: local)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw BeyGramAttachmentPreparationError.unreadable
            }
            let actual = (try? local.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard actual > 0, Int64(actual) <= maximumDocumentBytes else {
                try? FileManager.default.removeItem(at: directory)
                throw BeyGramAttachmentPreparationError.invalidFile
            }
            return BeyGramOutgoingAttachment(
                id: id, kind: .document, localURL: local,
                displayName: providerURL.lastPathComponent,
                sizeBytes: Int64(actual), width: 0, height: 0,
                durationSeconds: 0
            )
        }.value
    }

    /// Convert a video handed over by PhotosPicker into an upload-safe MP4.
    /// Input comes from a FileRepresentation copy, not in-memory Data.
    static func prepareVideo(_ pickedURL: URL) async throws -> BeyGramOutgoingAttachment {
        let resource = try pickedURL.resourceValues(forKeys: [.fileSizeKey])
        guard let sourceSize = resource.fileSize, sourceSize > 0 else {
            throw BeyGramAttachmentPreparationError.emptyFile
        }
        guard sourceSize <= 350 * 1024 * 1024 else {
            throw BeyGramAttachmentPreparationError.tooLarge
        }

        let asset = AVURLAsset(url: pickedURL)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else {
            throw BeyGramAttachmentPreparationError.unsupportedVideo
        }

        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw BeyGramAttachmentPreparationError.unsupportedVideo
        }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let width = Int(abs(bounds.width))
        let height = Int(abs(bounds.height))
        guard width > 0, height > 0 else {
            throw BeyGramAttachmentPreparationError.unsupportedVideo
        }

        let id = UUID()
        let folder = try stagedDirectory(for: id)
        let destination = folder.appendingPathComponent("video.mp4")
        do {
            guard let session = AVAssetExportSession(
                asset: asset, presetName: AVAssetExportPresetMediumQuality
            ), session.supportedFileTypes.contains(.mp4) else {
                throw BeyGramAttachmentPreparationError.unsupportedVideo
            }
            session.outputFileType = .mp4
            session.outputURL = destination
            session.shouldOptimizeForNetworkUse = true

            let status: AVAssetExportSession.Status = await withCheckedContinuation { continuation in
                session.exportAsynchronously {
                    continuation.resume(returning: session.status)
                }
            }
            guard status == .completed else {
                throw session.error ?? BeyGramAttachmentPreparationError.unsupportedVideo
            }
            let meta = try destination.resourceValues(forKeys: [.fileSizeKey])
            guard let bytes = meta.fileSize, bytes > 0, bytes <= 200 * 1024 * 1024 else {
                throw BeyGramAttachmentPreparationError.tooLarge
            }
            return BeyGramOutgoingAttachment(
                id: id, kind: .video, localURL: destination,
                displayName: "Видео.mp4", sizeBytes: Int64(bytes),
                width: width, height: height,
                durationSeconds: Int(ceil(seconds))
            )
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Don't remove staged files immediately on sendMessage's pending response:
    /// TDLib uploads asynchronously and still needs the local path.
    static func discardUnsent(_ item: BeyGramOutgoingAttachment) {
        try? FileManager.default.removeItem(at: item.localURL.deletingLastPathComponent())
    }

    /// Cleanup only abandoned old staging folders, never recently queued uploads.
    static func cleanStaleFiles() {
        guard let root = try? stagingRoot() else { return }
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let oldestAllowed = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        for folder in folders {
            guard let modified = (try? folder.resourceValues(
                forKeys: [.contentModificationDateKey]
            ))?.contentModificationDate, modified < oldestAllowed else { continue }
            try? fm.removeItem(at: folder)
        }
    }

    private static func stagingRoot() throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = caches.appendingPathComponent("BeyGramUploads", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        return directory
    }

    private static func stagedDirectory(for id: UUID) throws -> URL {
        let folder = try stagingRoot().appendingPathComponent(
            id.uuidString, isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true
        )
        return folder
    }
}
