import Foundation
import UIKit
import AVFoundation
import BeyGramYandexMusic

public struct BeyGramResolvedTrackMeta: Equatable {
    public let title: String
    public let artist: String?
    public let coverURL: URL?
    public let yandexTrackId: String?

    public init(title: String, artist: String?, coverURL: URL?, yandexTrackId: String? = nil) {
        self.title = title
        self.artist = artist
        self.coverURL = coverURL
        self.yandexTrackId = yandexTrackId
    }
}

/// Shared metadata & cover cache for Music Center, Mini-Player, Full Player, and Queue.
/// Ensures real track titles, artists, and covers are shown instead of UUIDs or raw cache filenames.
public final class BeyGramTrackMetadataStore {
    public static let shared = BeyGramTrackMetadataStore()
    public static let didUpdateNotification = Notification.Name("BeyGramTrackMetadataDidUpdate")

    private let lock = NSLock()
    private var byURLKey: [String: BeyGramResolvedTrackMeta] = [:]
    private var byYandexId: [String: BeyGramResolvedTrackMeta] = [:]
    private var imageCache = NSCache<NSURL, UIImage>()
    private var pendingAssetKeys = Set<String>()
    private var pendingImageURLs = Set<URL>()

    private init() {
        self.imageCache.countLimit = 120
    }

    /// Strips any leading `<UUID>-` prefix and file extension so local files never show UUIDs.
    public static func cleanDisplayTitle(fromRawName raw: String) -> String {
        var name = (raw as NSString).deletingPathExtension
        if name.isEmpty {
            name = raw
        }
        // Strip leading 36-char UUID + hyphen if present (e.g. "550e8400-e29b-41d4-a716-446655440000-Song")
        if name.count > 37 {
            let prefix = String(name.prefix(36))
            let sepIdx = name.index(name.startIndex, offsetBy: 36)
            if UUID(uuidString: prefix) != nil && name[sepIdx] == "-" {
                let rest = String(name[name.index(after: sepIdx)...])
                if !rest.isEmpty {
                    name = rest
                }
            }
        }
        // If cache file is named "ym-<trackId>", show friendly label until Yandex metadata arrives.
        if name.hasPrefix("ym-"), name.dropFirst(3).allSatisfy(\.isNumber) {
            return "Yandex Track #\(name.dropFirst(3))"
        }
        return name
    }

    public func registerYandexTrack(_ track: BGYandexTrack, localURL: URL? = nil) {
        let info = BGYandexTrackInfo(track: track)
        let artistText = info.artists.joined(separator: ", ")
        let meta = BeyGramResolvedTrackMeta(
            title: info.title ?? track.title,
            artist: artistText.isEmpty ? nil : artistText,
            coverURL: info.coverURL,
            yandexTrackId: track.trackId
        )
        self.lock.lock()
        self.byYandexId[track.trackId] = meta
        if let localURL {
            self.byURLKey[localURL.standardizedFileURL.path] = meta
        }
        self.lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
        }
    }

    public func associate(localURL: URL, with track: BGYandexTrack) {
        self.registerYandexTrack(track, localURL: localURL)
    }

    public func metadata(for url: URL, fallbackName: String) -> BeyGramResolvedTrackMeta {
        let path = url.standardizedFileURL.path
        self.lock.lock()
        if let cached = self.byURLKey[path] {
            self.lock.unlock()
            return cached
        }
        // Check if filename is ym-<trackId>.<ext>
        let stem = (url.lastPathComponent as NSString).deletingPathExtension
        if stem.hasPrefix("ym-") {
            let trackId = String(stem.dropFirst(3))
            if let ym = self.byYandexId[trackId] {
                self.byURLKey[path] = ym
                self.lock.unlock()
                return ym
            }
        }
        let shouldExtract = !self.pendingAssetKeys.contains(path)
        if shouldExtract {
            self.pendingAssetKeys.insert(path)
        }
        self.lock.unlock()

        if shouldExtract {
            self.extractAssetMetadata(url: url, path: path, fallbackName: fallbackName)
        }

        return BeyGramResolvedTrackMeta(
            title: Self.cleanDisplayTitle(fromRawName: fallbackName),
            artist: nil,
            coverURL: nil,
            yandexTrackId: stem.hasPrefix("ym-") ? String(stem.dropFirst(3)) : nil
        )
    }

    public func loadCover(url: URL?, completion: @escaping (UIImage?) -> Void) {
        guard let url else {
            completion(nil)
            return
        }
        if let cached = self.imageCache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }
        self.lock.lock()
        let alreadyLoading = self.pendingImageURLs.contains(url)
        if !alreadyLoading {
            self.pendingImageURLs.insert(url)
        }
        self.lock.unlock()
        if alreadyLoading {
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            self.lock.lock()
            self.pendingImageURLs.remove(url)
            self.lock.unlock()
            let image = data.flatMap { UIImage(data: $0) }
            if let image {
                self.imageCache.setObject(image, forKey: url as NSURL)
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
    }

    private func extractAssetMetadata(url: URL, path: String, fallbackName: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let asset = AVURLAsset(url: url)
            var title: String?
            var artist: String?
            for item in asset.commonMetadata {
                if item.commonKey == .commonKeyTitle, let value = item.stringValue, !value.isEmpty {
                    title = value
                } else if item.commonKey == .commonKeyArtist, let value = item.stringValue, !value.isEmpty {
                    artist = value
                }
            }
            let resolved = BeyGramResolvedTrackMeta(
                title: title ?? Self.cleanDisplayTitle(fromRawName: fallbackName),
                artist: artist,
                coverURL: nil
            )
            self.lock.lock()
            self.pendingAssetKeys.remove(path)
            if self.byURLKey[path] == nil {
                self.byURLKey[path] = resolved
            }
            self.lock.unlock()
            if title != nil || artist != nil {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
                }
            }
        }
    }
}
