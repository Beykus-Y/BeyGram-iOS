import Foundation

/// Gives a local MP3 for a `ym:` row. Only the file is kept. Links are requested again each time, because they expire.
/// The cache is a folder inside the app's private storage, so it is not in backups that leave the device.
public final class BGYandexTrackResolver {
    private let api: BGYandexAPI
    private let cacheDirectory: URL
    private let session: URLSession
    private let fileManager = FileManager.default

    public init(api: BGYandexAPI, cacheDirectory: URL) {
        self.api = api
        self.cacheDirectory = cacheDirectory
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = BGYandexConfig.readTimeout
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// File name for a track id. Only letters and digits pass, so an id can never point outside the folder.
    static func fileName(trackId: String) -> String {
        let safe = trackId.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return "ym-\(safe).mp3"
    }

    public func cachedFile(trackId: String) -> URL? {
        let url = cacheDirectory.appendingPathComponent(BGYandexTrackResolver.fileName(trackId: trackId))
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Local file for the track: the cached copy, or a fresh download. One retry when the link was refused as expired.
    public func localFile(token: String, trackId: String, completion: @escaping (Result<URL, BGYandexError>) -> Void) {
        if let cached = cachedFile(trackId: trackId) {
            completion(.success(cached))
            return
        }
        download(token: token, trackId: trackId, retriesLeft: 1, completion: completion)
    }

    private func download(token: String, trackId: String, retriesLeft: Int, completion: @escaping (Result<URL, BGYandexError>) -> Void) {
        api.audioLink(token: token, trackId: trackId) { [weak self] linkResult in
            guard let self = self else {
                return
            }
            switch linkResult {
            case let .failure(error):
                completion(.failure(error))
            case let .success(link):
                self.session.downloadTask(with: URLRequest(url: link.url)) { tempURL, response, error in
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if (status == 403 || status == 410), retriesLeft > 0 {
                        self.download(token: token, trackId: trackId, retriesLeft: retriesLeft - 1, completion: completion)
                        return
                    }
                    guard error == nil, (200...299).contains(status), let tempURL = tempURL else {
                        completion(.failure(.network))
                        return
                    }
                    let target = self.cacheDirectory.appendingPathComponent(BGYandexTrackResolver.fileName(trackId: trackId))
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
        try? fileManager.removeItem(at: cacheDirectory.appendingPathComponent(BGYandexTrackResolver.fileName(trackId: trackId)))
    }

    /// Removes every cached track. Called on sign-out.
    public func clearAll() {
        let files = (try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("ym-") {
            try? fileManager.removeItem(at: file)
        }
    }
}
