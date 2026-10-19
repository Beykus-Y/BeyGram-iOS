import SwiftUI

/// TDLib's small chat/user photo, decoded from a completed local JPEG only.
/// Keeps the same stable Android-inspired colored-initial fallback.
struct BeyGramTelegramAvatarView: View {
    @ObservedObject var conversations: TelegramConversations
    let file: TelegramMediaFile?
    let initials: String
    let entityID: Int64
    let size: CGFloat

    private var currentPath: String? {
        guard let file else { return nil }
        let state = conversations.mediaFileState(file)
        return state.isOnDisk ? state.completedPath : nil
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(BeyGramAvatarStyle.color(for: entityID))

            Text(initials)
                .font(.system(size: max(12, size * 0.30), weight: .bold))
                .foregroundStyle(.white)

            if let path = currentPath {
                BeyGramLocalMediaImage(path: path, maxDimension: 240)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            conversations.ensureAvatarAvailable(file)
        }
        .onChange(of: file?.id) { _ in
            conversations.ensureAvatarAvailable(file)
        }
    }
}
