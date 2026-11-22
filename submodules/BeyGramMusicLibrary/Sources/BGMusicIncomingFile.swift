import Foundation
import BeyGramMusicFormat

/// The identifiers of a .bgmusic file. Info.plist declares the same type for Open in, Share and the Files app.
public enum BGMusicFileTypes {
    public static let uniformTypeIdentifier = "org.beygram.bgmusic"
    public static let mimeType = "application/vnd.beygram.music+zip"
    public static let fileExtension = BGMusicFileNaming.fileExtension
}

/// Reads a file that the system hands the app: a URL from Open in, from Share or from the Files app.
public enum BGMusicIncomingFile {
    /// Reads the whole file and refuses anything over the format's file limit (section 6). The size is checked before the
    /// file is read and again after it. The security scope is opened for the read and closed after it.
    public static func load(from url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > BGMusicArchive.maxFileBytes {
            throw BGMusicLibraryError.fileTooLarge
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BGMusicLibraryError.fileNotReadable
        }
        guard data.count <= BGMusicArchive.maxFileBytes else {
            throw BGMusicLibraryError.fileTooLarge
        }
        return data
    }
}
