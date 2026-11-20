import Foundation

/// Gives a local MP3 for a `ym:` row. Only the file is kept. A link is asked for each time it is needed, because it expires.
/// Files live in `beygram/yandex` under the given folder, excluded from iCloud and device backups: the tracks may not leave the device.
public final class BGYandexTrackResolver {
    /// Gives a fresh link for a track: the service checks the session and the subscription. Not on the main queue.
    public typealias LinkProvider = (String, @escaping (Result<BGYandexAudio, BGYandexError>) -> Void) -> Void

    /// Set by the service once it exists. Without it no track can be downloaded.
    public var linkProvider: LinkProvider?

    private let cacheDirectory: URL
    private let session: URLSession
    private let fileManager = FileManager.default

    public init(cacheDirectory: URL) {
        // The given folder holds `beygram/yandex`, where the tracks live.
        let folder = cacheDirectory.appendingPathComponent("beygram", isDirectory: true)
            .appendingPathComponent("yandex", isDirectory: true)
        self.cacheDirectory = folder
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = BGYandexConfig.readTimeout
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        BGYandexTrackResolver.excludeFromBackup(folder)
    }

    /// Keeps one folder out of iCloud and device backups. Application Support is backed up unless a folder says otherwise.
    static func excludeFromBackup(_ folder: URL) {
        var target = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    /// File name for a track id. Only letters and digits pass, so an id can never point outside the folder.
    static func fileName(trackId: String) -> String {
        let safe = trackId.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return "ym-\(safe).mp3"
    }

    private func cacheURL(trackId: String) -> URL {
        return cacheDirectory.appendingPathComponent(BGYandexTrackResolver.fileName(trackId: trackId))
    }

    public func cachedFile(trackId: String) -> URL? {
        let url = cacheURL(trackId: trackId)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Local file for the track: the cached copy, or a fresh download. A link refused as expired is asked for once more.
    /// Completes on the main queue.
    public func localFile(trackId: String, completion: @escaping (Result<URL, BGYandexError>) -> Void) {
        let report: (Result<URL, BGYandexError>) -> Void = { result in
            DispatchQueue.main.async {
                completion(result)
            }
        }
        if let cached = cachedFile(trackId: trackId) {
            report(.success(cached))
            return
        }
        download(trackId: trackId, retriesLeft: 1, completion: report)
    }

    private func download(trackId: String, retriesLeft: Int, completion: @escaping (Result<URL, BGYandexError>) -> Void) {
        guard let provider = linkProvider else {
            completion(.failure(.notSignedIn))
            return
        }
        provider(trackId) { linkResult in
            switch linkResult {
            case let .failure(error):
                completion(.failure(error))
            case let .success(audio):
                self.session.downloadTask(with: URLRequest(url: audio.url)) { tempURL, response, error in
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    // The link was refused as expired: one fresh link, then the track waits for a later try.
                    if status == 403 || status == 410 {
                        if retriesLeft > 0 {
                            self.download(trackId: trackId, retriesLeft: retriesLeft - 1, completion: completion)
                        } else {
                            completion(.failure(.unavailable))
                        }
                        return
                    }
                    guard error == nil, (200...299).contains(status), let tempURL = tempURL else {
                        completion(.failure(.network))
                        return
                    }
                    // The temporary file is only valid inside this handler, so it is moved here.
                    let target = self.cacheURL(trackId: trackId)
                    do {
                        if self.fileManager.fileExists(atPath: target.path) {
                            try self.fileManager.removeItem(at: target)
                        }
                        try self.fileManager.moveItem(at: tempURL, to: target)
                        completion(.success(target))
                    } catch {
                        completion(.failure(.unknown))
                    }
                }.resume()
            }
        }
    }

    public func forget(trackId: String) {
        try? fileManager.removeItem(at: cacheURL(trackId: trackId))
    }

    /// Removes every cached track. Called on sign-out.
    public func clearAll() {
        let files = (try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("ym-") {
            try? fileManager.removeItem(at: file)
        }
    }
}
