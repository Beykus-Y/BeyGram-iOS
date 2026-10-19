import SwiftUI
import ImageIO
import AVKit
import QuickLook

/// Downsample on a background thread; never decode a multi-megapixel image
/// synchronously while scrolling through messages.
private enum BeyGramLocalImageDecoder {
    static func image(path: String, maxDimension: Int) -> UIImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct BeyGramLocalMediaImage: View {
    let path: String
    let maxDimension: Int

    @State private var decoded: UIImage?

    var body: some View {
        Group {
            if let decoded {
                Image(uiImage: decoded)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.13))
                    .overlay { ProgressView() }
            }
        }
        .clipped()
        .task(id: path) {
            decoded = nil
            let filePath = path
            let dimension = maxDimension
            let result = await Task.detached(priority: .userInitiated) {
                BeyGramLocalImageDecoder.image(path: filePath, maxDimension: dimension)
            }.value
            if !Task.isCancelled { decoded = result }
        }
    }
}

/// Android's MediaViews-inspired bubble. Never attempts an arbitrary URL fetch:
/// all file paths originate from completed TDLib file states.
struct BeyGramMediaAttachmentView: View {
    let media: TelegramMessageMedia
    @ObservedObject var conversations: TelegramConversations
    let colors: BeyGramChatColors

    @State private var spoilerRevealed = false
    @State private var showingViewer = false
    @State private var quickLookURL: URL?

    private var file: TelegramMediaFile {
        conversations.mediaFileState(media.file)
    }

    private var thumb: TelegramMediaFile? {
        guard let preview = media.preview else { return nil }
        return conversations.mediaFileState(preview)
    }

    private var displayPath: String? {
        guard !media.isSecret, (!media.hasSpoiler || spoilerRevealed) else { return nil }
        if let thumb, thumb.isOnDisk { return thumb.completedPath }
        return file.isOnDisk ? file.completedPath : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if media.isSecret {
                privateMediaPlaceholder
            } else if media.kind.isVisual {
                visualAttachment
            } else {
                fileAttachment
            }

            if !media.isSecret && !media.caption.isEmpty {
                Text(media.caption)
                    .font(.system(size: 14))
                    .foregroundStyle(colors.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !media.isSecret, let error = conversations.mediaError(for: media.file.id) {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .onAppear {
            loadPreviewIfAllowed()
        }
        .fullScreenCover(isPresented: $showingViewer) {
            if let path = file.completedPath, file.isOnDisk {
                BeyGramMediaViewer(media: media, path: path)
            }
        }
        .quickLookPreview($quickLookURL)
    }

    private var privateMediaPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
            Text("Защищённое вложение")
                .font(.caption.bold())
            Text("Просмотр одноразовых и секретных медиа появится после реализации защиты экрана.")
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(colors.secondary)
        .frame(width: 245, minHeight: 135)
        .padding(12)
        .background(colors.surface2, in: RoundedRectangle(cornerRadius: 16))
    }

    private var visualAttachment: some View {
        ZStack {
            if let path = displayPath {
                BeyGramLocalMediaImage(path: path, maxDimension: 920)
                    .frame(width: 245, height: max(155, min(330, 245 / media.shapeRatio)))
            } else {
                Rectangle()
                    .fill(colors.surface2)
                    .frame(width: 245, height: 185)
                    .overlay {
                        Image(systemName: media.kind.symbol)
                            .font(.system(size: 42, weight: .ultraLight))
                            .foregroundStyle(colors.accent.opacity(0.65))
                    }
            }

            if media.hasSpoiler && !spoilerRevealed {
                Button {
                    spoilerRevealed = true
                    loadPreviewIfAllowed()
                } label: {
                    Label("Показать спойлер", systemImage: "eye")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.74), in: Capsule())
                }
                .accessibilityLabel("Раскрыть скрытое медиа")
            } else {
                Button {
                    openOrDownload()
                } label: {
                    if file.isOnDisk {
                        Image(systemName: media.kind == .photo || media.kind == .sticker
                            ? "arrow.up.left.and.arrow.down.right" : "play.fill")
                            .font(.system(size: 24, weight: .semibold))
                    } else if file.isDownloading || conversations.pendingDownloads.contains(file.id) {
                        ProgressView(value: file.fraction > 0 ? file.fraction : nil)
                            .tint(.white)
                            .frame(width: 26, height: 26)
                    } else {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 24, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 53, height: 53)
                .background(.black.opacity(0.55), in: Circle())
                .disabled(file.isDownloading || conversations.pendingDownloads.contains(file.id))
                .accessibilityLabel(file.isOnDisk ? "Открыть медиа" : "Скачать медиа")
            }
        }
        .frame(width: 245)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .bottomLeading) {
            if media.durationSeconds > 0 {
                Text(duration(media.durationSeconds))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(8)
            }
        }
    }

    private var fileAttachment: some View {
        Button {
            openOrDownload()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: media.kind.symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(colors.accent)
                    .frame(width: 42, height: 42)
                    .background(colors.accentSoft, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(media.fileName.isEmpty ? media.kind.label : media.fileName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .foregroundStyle(colors.primary)
                    HStack(spacing: 5) {
                        if !file.humanSize.isEmpty {
                            Text(file.humanSize)
                        }
                        if file.isDownloading {
                            Text("\(Int(file.fraction * 100))%")
                        } else {
                            Text(file.isOnDisk ? "Открыть" : "Скачать")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(colors.secondary)
                }

                Spacer(minLength: 0)
                if file.isDownloading || conversations.pendingDownloads.contains(file.id) {
                    ProgressView().tint(colors.accent)
                } else {
                    Image(systemName: file.isOnDisk ? "arrow.up.forward" : "arrow.down.circle")
                        .foregroundStyle(colors.accent)
                }
            }
            .padding(10)
            .frame(width: 250)
            .background(colors.surface2, in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .disabled(file.isDownloading || conversations.pendingDownloads.contains(file.id))
    }

    private func loadPreviewIfAllowed() {
        guard !media.isSecret, (!media.hasSpoiler || spoilerRevealed),
              media.kind.isVisual, media.preview != nil else { return }
        conversations.downloadMedia(media, preview: true)
    }

    private func openOrDownload() {
        guard !media.isSecret, (!media.hasSpoiler || spoilerRevealed) else { return }
        guard file.isOnDisk, let path = file.completedPath else {
            conversations.downloadMedia(media)
            return
        }
        if media.kind == .document {
            quickLookURL = URL(fileURLWithPath: path)
        } else {
            showingViewer = true
        }
    }

    private func duration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct BeyGramMediaViewer: View {
    let media: TelegramMessageMedia
    let path: String

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isAudioPlaying = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                switch media.kind {
                case .photo, .sticker:
                    BeyGramLocalMediaImage(path: path, maxDimension: 2400)
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .video, .animation, .videoNote:
                    if let player {
                        VideoPlayer(player: player)
                            .onAppear { player.play() }
                    } else {
                        ProgressView().tint(.white)
                    }
                case .audio, .voice:
                    VStack(spacing: 24) {
                        Image(systemName: "waveform")
                            .font(.system(size: 70))
                            .foregroundStyle(.white)
                        Text(media.fileName.isEmpty ? media.kind.label : media.fileName)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Button {
                            guard let player else { return }
                            if isAudioPlaying { player.pause() }
                            else { player.play() }
                            isAudioPlaying.toggle()
                        } label: {
                            Label(isAudioPlaying ? "Пауза" : "Воспроизвести",
                                  systemImage: isAudioPlaying ? "pause.circle" : "play.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(player == nil)
                    }
                    .padding(20)
                case .document:
                    Text("Документ")
                        .foregroundStyle(.white)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                player?.pause()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.65), in: Circle())
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .onAppear {
            switch media.kind {
            case .video, .animation, .videoNote, .audio, .voice:
                player = AVPlayer(url: URL(fileURLWithPath: path))
            default: break
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
