import Foundation

/// Gives a local MP3 for a `ym:` row. Only the file is kept. A link is asked for each time it is needed, because it expires.
/// Files live in the folder the service is given, excluded from iCloud and device backups: the tracks may not leave the device.
/// A file is kept only when `BGYandexAudioCheck` accepts it, and a kept file is checked again before it is played.
public final class BGYandexTrackResolver {
    /// Gives a fresh link for a track: the service checks the session and the subscription. Not on the main queue.
    public typealias LinkProvider = (String, @escaping (Result<BGYandexAudio, BGYandexError>) -> Void) -> Void

    /// Set by the service once it exists. Without it no track can be downloaded.
    public var linkProvider: LinkProvider?

    /// Told about each download that the check refused, with what the body looked like. It names no link, token or path.
    /// Called on the download's own queue, not the main queue.
    public var onRejectedDownload: ((BGYandexAudioCheck.Probe) -> Void)?

    private let cacheDirectory: URL
    private let session: URLSession
    private let fileManager = FileManager.default

    /// The folder the tracks live in, used as given. It is excluded from backups in full, so it must be a folder of its own:
    /// the screens pass `Application Support/beygram/yandex`.
    public init(cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = BGYandexConfig.readTimeout
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        BGYandexTrackResolver.excludeFromBackup(cacheDirectory)
    }

    /// Keeps one folder out of iCloud and device backups. Application Support is backed up unless a folder says otherwise.
    static func excludeFromBackup(_ folder: URL) {
        var target = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    private static let supportedExtensions = ["mp3", "m4a", "flac", "wav", "aiff"]

    /// File name for a track id. Only letters and digits pass, so an id can never point outside the folder.
    static func fileName(trackId: String, ext: String = "mp3") -> String {
        let safe = trackId.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return "ym-\(safe).\(ext)"
    }

    private func cacheURL(trackId: String, ext: String = "mp3") -> URL {
        return cacheDirectory.appendingPathComponent(BGYandexTrackResolver.fileName(trackId: trackId, ext: ext))
    }

    public func cachedFile(trackId: String) -> URL? {
        for ext in BGYandexTrackResolver.supportedExtensions {
            let url = cacheURL(trackId: trackId, ext: ext)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
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
            // A file that fails the check (kept before the check existed, or damaged on disk) is removed and downloaded again.
            if BGYandexAudioCheck.inspect(fileAt: cached).verdict == .audio {
                let normalized = normalizeCachedExtensionIfNeeded(cached, trackId: trackId)
                report(.success(normalized))
                return
            }
            try? fileManager.removeItem(at: cached)
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
                    let http = response as? HTTPURLResponse
                    let status = http?.statusCode ?? 0
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
                    // The temporary file is only valid inside this handler, so it is checked and moved here.
                    let (probe, header) = self.inspectDownload(at: tempURL, response: http)
                    guard probe.verdict == .audio else {
                        try? self.fileManager.removeItem(at: tempURL)
                        self.onRejectedDownload?(probe)
                        // A body that is not a track may come from a stale link: one fresh link, then the track waits.
                        if retriesLeft > 0 {
                            self.download(trackId: trackId, retriesLeft: retriesLeft - 1, completion: completion)
                        } else {
                            completion(.failure(.invalidFile))
                        }
                        return
                    }
                    let ext = BGYandexAudioCheck.fileExtension(for: header, contentType: http?.value(forHTTPHeaderField: "Content-Type"), fallbackCodec: audio.codec)
                    let target = self.cacheURL(trackId: trackId, ext: ext)
                    do {
                        self.forget(trackId: trackId)
                        try self.fileManager.moveItem(at: tempURL, to: target)
                        completion(.success(target))
                    } catch {
                        completion(.failure(.unknown))
                    }
                }.resume()
            }
        }
    }

    /// The check of a finished download, with what the response said about its body.
    private func inspectDownload(at file: URL, response: HTTPURLResponse?) -> (BGYandexAudioCheck.Probe, Data) {
        let attributes = try? fileManager.attributesOfItem(atPath: file.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        var header = Data()
        if let handle = try? FileHandle(forReadingFrom: file) {
            header = (try? handle.read(upToCount: BGYandexAudioCheck.headerByteCount)) ?? Data()
            try? handle.close()
        }
        // A body the system decoded no longer has the length the server announced, so the length is not compared.
        let encoding = response?.value(forHTTPHeaderField: "Content-Encoding")?.lowercased() ?? "identity"
        let isEncoded = !encoding.isEmpty && encoding != "identity"
        let announced = isEncoded ? -1 : (response?.expectedContentLength ?? -1)
        let probe = BGYandexAudioCheck.inspect(header: header,
                                               byteCount: byteCount,
                                               expectedLength: announced,
                                               contentType: response?.value(forHTTPHeaderField: "Content-Type"))
        return (probe, header)
    }

    /// If a valid cached file has a container header whose extension differs from its filename
    /// (e.g. an M4A cached as `.mp3` by an earlier build), renames it in-place without re-downloading.
    private func normalizeCachedExtensionIfNeeded(_ url: URL, trackId: String) -> URL {
        var header = Data()
        if let handle = try? FileHandle(forReadingFrom: url) {
            header = (try? handle.read(upToCount: BGYandexAudioCheck.headerByteCount)) ?? Data()
            try? handle.close()
        }
        guard !header.isEmpty else {
            return url
        }
        let detectedExt = BGYandexAudioCheck.fileExtension(for: header)
        let currentExt = url.pathExtension.lowercased()
        guard detectedExt != currentExt else {
            return url
        }
        let target = cacheURL(trackId: trackId, ext: detectedExt)
        do {
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.moveItem(at: url, to: target)
            return target
        } catch {
            return url
        }
    }

    public func forget(trackId: String) {
        for ext in BGYandexTrackResolver.supportedExtensions {
            try? fileManager.removeItem(at: cacheURL(trackId: trackId, ext: ext))
        }
    }

    /// Removes every cached track. Called on sign-out.
    public func clearAll() {
        let files = (try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("ym-") {
            try? fileManager.removeItem(at: file)
        }
    }
}
