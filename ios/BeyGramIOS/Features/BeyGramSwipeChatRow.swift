import SwiftUI

/// The Android BeyGram gesture row adapted to iOS ScrollView/LazyVStack.
/// A simultaneous horizontal drag lets the vertical scroll view keep its gesture.
struct BeyGramSwipeChatRow<Content: View>: View {
    let chat: TelegramChatPreview
    let colors: BeyGramChatColors
    let canSwipe: Bool
    @Binding var openChatID: Int64?
    let onRead: () -> Void
    let onArchive: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggingOffset: CGFloat?

    private let actionWidth: CGFloat = 84
    private var revealWidth: CGFloat { actionWidth * 2 }
    private var opened: Bool { openChatID == chat.id }

    private var currentOffset: CGFloat {
        draggingOffset ?? (opened ? -revealWidth : 0)
    }

    private var motion: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.19)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                // Revealed on a rightward gesture. The action itself is
                // performed only when the finger is released past the threshold.
                Label(
                    chat.hasUnread ? "Прочитано" : "Непрочитано",
                    systemImage: chat.hasUnread ? "envelope.open" : "envelope.badge"
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colors.accentInk)
                .frame(width: 116)
                .opacity(currentOffset > 12 ? 1 : 0)
                .accessibilityHidden(true)

                Spacer(minLength: 0)

                actionButton(
                    chat.hasUnread ? "Прочитано" : "Непрочитано",
                    icon: chat.hasUnread ? "envelope.open" : "envelope.badge",
                    background: colors.accentSoft,
                    foreground: colors.accentInk
                ) {
                    close()
                    onRead()
                }
                actionButton(
                    chat.archiveOrder > 0 ? "Вернуть" : "В архив",
                    icon: chat.archiveOrder > 0 ? "tray.and.arrow.up" : "archivebox",
                    background: colors.accent,
                    foreground: colors.onAccent
                ) {
                    close()
                    onArchive()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .accessibilityHidden(!opened)

            content
                .background(colors.screen)
                .offset(x: currentOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 22)
                        .onChanged { value in
                            guard canSwipe else { return }
                            let x = value.translation.width
                            let y = value.translation.height
                            guard abs(x) > abs(y) * 1.5 else { return }
                            let origin: CGFloat = opened ? -revealWidth : 0
                            draggingOffset = min(100, max(-revealWidth, origin + x))
                        }
                        .onEnded { value in
                            guard canSwipe else { return }
                            let x = value.translation.width
                            let y = value.translation.height
                            defer { draggingOffset = nil }
                            guard abs(x) > abs(y) * 1.5 else { return }
                            if x < -64 {
                                withAnimation(motion) { openChatID = chat.id }
                            } else if x > 70 {
                                if opened {
                                    close()
                                } else {
                                    onRead()
                                }
                            } else if opened && x > 35 {
                                close()
                            }
                        },
                    including: canSwipe ? .all : .none
                )
        }
        .clipped()
        .animation(motion, value: openChatID)
        .accessibilityAction(named: Text(chat.archiveOrder > 0 ? "Вернуть из архива" : "В архив")) {
            if canSwipe { onArchive() }
        }
        .accessibilityAction(named: Text(chat.hasUnread ? "Отметить прочитанным" : "Пометить непрочитанным")) {
            if canSwipe { onRead() }
        }
    }

    private func close() {
        withAnimation(motion) { openChatID = nil }
    }

    private func actionButton(
        _ title: String,
        icon: String,
        background: Color,
        foreground: Color,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(foreground)
            .frame(width: actionWidth)
            .frame(maxHeight: .infinity)
            .background(background)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }
}
