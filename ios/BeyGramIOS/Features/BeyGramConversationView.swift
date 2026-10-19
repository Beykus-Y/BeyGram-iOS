import SwiftUI

/// Android-inspired conversation layout: custom warm palette, asymmetric
/// bubbles (20pt / 6pt tail), footer time aligned independently of text.
struct BeyGramConversationView: View {
    @ObservedObject var conversations: TelegramConversations
    let chat: TelegramChatPreview

    @Environment(\.colorScheme) private var scheme
    @AppStorage("beygram.appearance.preset") private var appearancePreset = "warm"
    @State private var draft = ""
    @State private var replyTarget: TelegramChatMessage?
    @State private var editTarget: TelegramChatMessage?
    @State private var actionTarget: TelegramChatMessage?
    @FocusState private var composerFocused: Bool

    private var colors: BeyGramChatColors { .selected(scheme, preset: appearancePreset) }
    private var messages: [TelegramChatMessage] { conversations.histories[chat.id] ?? [] }
    private var isLoading: Bool { conversations.loadingHistory.contains(chat.id) }

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(colors.divider)

            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if !conversations.exhaustedHistory.contains(chat.id) && !messages.isEmpty {
                            Button {
                                conversations.loadOlder(chat.id)
                            } label: {
                                if isLoading {
                                    ProgressView().tint(colors.accent)
                                } else {
                                    Text("Показать более ранние сообщения")
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(colors.accent)
                            .disabled(isLoading)
                            .padding(.vertical, 12)
                        }

                        if messages.isEmpty {
                            VStack(spacing: 12) {
                                if isLoading { ProgressView() }
                                Text(isLoading ? "Загружаем историю…" : "Сообщений пока нет")
                                    .foregroundStyle(colors.secondary)
                            }
                            .padding(.top, 80)
                        }

                        ForEach(messages) { message in
                            BeyGramMessageBubble(
                                message: message,
                                conversations: conversations,
                                colors: colors,
                                onActions: { actionTarget = message }
                            )
                            .id(message.id)
                            .onAppear {
                                conversations.messageBecameVisible(chatID: chat.id, messageID: message.id)
                            }
                            .onDisappear {
                                conversations.messageBecameHidden(chatID: chat.id, messageID: message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                }
                .onChange(of: messages.count) { _ in
                    if let id = messages.last?.id {
                        withAnimation(.easeOut(duration: 0.22)) {
                            reader.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    conversations.openChat(chat.id)
                }
                .onDisappear {
                    conversations.closeChat(chat.id)
                }
            }

            if let error = conversations.errorMessage, !error.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error)
                        .font(.caption)
                        .lineLimit(3)
                    Spacer()
                    Button {
                        conversations.clearError()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
                .foregroundStyle(Color.red)
                .padding(10)
            }
        }
        .background(colors.screen.ignoresSafeArea())
        .sheet(item: $actionTarget) { message in
            BeyGramMessageActionsSheet(
                message: message,
                conversations: conversations,
                onReply: {
                    editTarget = nil
                    replyTarget = message
                    composerFocused = true
                },
                onEdit: {
                    replyTarget = nil
                    editTarget = message
                    draft = message.text
                    composerFocused = true
                }
            )
        }
        .navigationTitle(chat.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if let target = editTarget ?? replyTarget {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colors.accent)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(editTarget != nil ? "Редактирование" : "Ответ")
                            .font(.caption.bold())
                            .foregroundStyle(colors.accent)
                        Text(target.text)
                            .font(.caption)
                            .foregroundStyle(colors.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        editTarget = nil
                        replyTarget = nil
                        draft = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(colors.secondary)
                    }
                    .accessibilityLabel("Отменить действие")
                }
                .frame(height: 36)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }

            HStack(alignment: .bottom, spacing: 10) {
            TextField("Сообщение", text: $draft, axis: .vertical)
                .focused($composerFocused)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(colors.surface2, in: RoundedRectangle(cornerRadius: 21))
                .tint(colors.accent)
                .submitLabel(.return)

            Button {
                if let editTarget {
                    if conversations.editText(draft, in: editTarget) {
                        draft = ""
                        self.editTarget = nil
                    }
                } else if conversations.sendText(draft, to: chat.id, replyTo: replyTarget?.id) {
                    draft = ""
                    replyTarget = nil
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(colors.onAccent)
                    .frame(width: 42, height: 42)
                    .background(colors.accent, in: Circle())
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            .accessibilityLabel("Отправить сообщение")
        }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(colors.surface)
    }
}

private struct BeyGramMessageBubble: View {
    let message: TelegramChatMessage
    @ObservedObject var conversations: TelegramConversations
    let colors: BeyGramChatColors
    let onActions: () -> Void

    var body: some View {
        HStack {
            if message.outgoing { Spacer(minLength: 55) }

            VStack(alignment: .leading, spacing: 5) {
                if let media = message.media {
                    BeyGramMediaAttachmentView(
                        media: media,
                        conversations: conversations,
                        colors: colors
                    )
                } else if message.isText {
                    Text(message.text)
                        .font(.system(size: 15))
                        .foregroundStyle(colors.primary)
                        .textSelection(.enabled)
                } else {
                    Text(message.text)
                        .font(.system(size: 15))
                        .foregroundStyle(colors.primary)
                }

                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Text(message.time)
                        .font(.system(size: 11))
                        .foregroundStyle(colors.secondary)

                    if message.outgoing {
                        Image(systemName: message.status == "messageSendingStatePending"
                            ? "clock" : message.status == "messageSendingStateFailed"
                            ? "exclamationmark.circle" : "checkmark")
                            .font(.system(size: 10))
                            .foregroundStyle(colors.accent)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(message.outgoing ? colors.outgoingBubble : colors.surface,
                        in: BeyGramTailBubble(outgoing: message.outgoing))
            .contextMenu {
                Button {
                    onActions()
                } label: {
                    Label("Действия с сообщением", systemImage: "ellipsis.circle")
                }
            }

            if !message.outgoing { Spacer(minLength: 55) }
        }
    }
}

private struct BeyGramTailBubble: Shape {
    let outgoing: Bool

    func path(in rect: CGRect) -> Path {
        let main: CGFloat = 20
        let tail: CGFloat = 6
        let rTL = main
        let rTR = main
        let rBL = outgoing ? main : tail
        let rBR = outgoing ? tail : main
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + rTL, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rTR, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rTR),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rBR))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rBR, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rBL, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - rBL),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rTL))
        path.addQuadCurve(to: CGPoint(x: rect.minX + rTL, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}
