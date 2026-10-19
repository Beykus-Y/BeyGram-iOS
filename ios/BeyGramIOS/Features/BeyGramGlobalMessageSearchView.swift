import SwiftUI

private struct BeyGramSearchDestination: Hashable {
    let chatID: Int64
    let messageID: Int64
}

/// Searches messages across the authorized Telegram account using TDLib.
/// The server deliberately excludes secret chats from global search.
struct BeyGramGlobalMessageSearchView: View {
    @ObservedObject var conversations: TelegramConversations

    @Environment(\.colorScheme) private var scheme
    @AppStorage("beygram.appearance.preset") private var preset = "warm"
    @State private var query = ""
    @FocusState private var queryFocused: Bool

    private var colors: BeyGramChatColors { .selected(scheme, preset: preset) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(colors.secondary)

                    TextField("Искать сообщения во всех чатах", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($queryFocused)
                        .submitLabel(.search)
                        .tint(colors.accent)

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(colors.secondary)
                        }
                        .accessibilityLabel("Очистить поиск")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(colors.surface2, in: RoundedRectangle(cornerRadius: 15))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                            messageState(
                                "Введите минимум два символа",
                                subtitle: "Поиск по сообщениям Telegram. Секретные чаты исключены.",
                                icon: "text.magnifyingglass"
                            )
                        } else {
                            if conversations.globalMessageTotalCount > 0 {
                                Text("НАЙДЕНО: \(conversations.globalMessageTotalCount)")
                                    .font(.caption.weight(.semibold))
                                    .tracking(0.5)
                                    .foregroundStyle(colors.secondary)
                                    .padding(.horizontal, 18)
                                    .padding(.top, 8)
                                    .padding(.bottom, 10)
                            }

                            ForEach(conversations.globalMessageResults) { hit in
                                if let chat = conversations.chat(for: hit.chatID) {
                                    NavigationLink(value: BeyGramSearchDestination(
                                        chatID: hit.chatID, messageID: hit.messageID
                                    )) {
                                        searchResultRow(hit: hit, chat: chat)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    // getChat is in progress for an archived or old chat.
                                    HStack(spacing: 12) {
                                        ProgressView()
                                        Text(hit.text)
                                            .lineLimit(2)
                                            .foregroundStyle(colors.secondary)
                                    }
                                    .padding(18)
                                }
                            }

                            if conversations.globalMessageSearchBusy {
                                HStack {
                                    Spacer()
                                    ProgressView("Поиск в Telegram…")
                                        .tint(colors.accent)
                                    Spacer()
                                }
                                .padding(20)
                            } else if let error = conversations.globalMessageSearchError {
                                VStack(spacing: 12) {
                                    Label(error, systemImage: "exclamationmark.triangle")
                                        .font(.footnote)
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(.red)
                                    Button("Повторить поиск") {
                                        conversations.beginGlobalMessageSearch(query)
                                    }
                                    .tint(colors.accent)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(25)
                            } else if conversations.globalMessageResults.isEmpty {
                                messageState(
                                    "Сообщения не найдены",
                                    subtitle: "Попробуйте другое слово или фразу.",
                                    icon: "text.magnifyingglass"
                                )
                            }

                            if conversations.globalMessageHasMore &&
                               !conversations.globalMessageSearchBusy {
                                Button {
                                    conversations.loadMoreGlobalMessageResults()
                                } label: {
                                    Text("Показать ещё сообщения")
                                        .font(.subheadline.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(15)
                                }
                                .foregroundStyle(colors.accent)
                            }
                        }
                    }
                    .padding(.bottom, 35)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(colors.screen.ignoresSafeArea())
            .navigationTitle("Поиск сообщений")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: query) {
                conversations.clearGlobalMessageSearch()
                let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard normalized.count >= 2 else { return }
                // Avoid sending a Telegram query for every keystroke.
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                conversations.beginGlobalMessageSearch(normalized)
            }
            .navigationDestination(for: BeyGramSearchDestination.self) { destination in
                if let chat = conversations.chat(for: destination.chatID) {
                    BeyGramConversationView(
                        conversations: conversations,
                        chat: chat,
                        initialMessageID: destination.messageID
                    )
                } else {
                    ProgressView("Загружаем чат…")
                }
            }
            .onDisappear {
                // Invalidate pending responses when closing the search screen.
                conversations.clearGlobalMessageSearch()
            }
        }
    }

    private func searchResultRow(
        hit: TelegramGlobalSearchHit,
        chat: TelegramChatPreview
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(chat.initials)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(BeyGramAvatarStyle.color(for: chat.id), in: Circle())

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(chat.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(colors.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(hit.formattedDate)
                        .font(.caption2)
                        .foregroundStyle(colors.secondary)
                        .lineLimit(1)
                }

                Text(hit.text)
                    .font(.subheadline)
                    .foregroundStyle(colors.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func messageState(
        _ title: String, subtitle: String, icon: String
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundStyle(colors.accent)
            Text(title)
                .font(.headline)
                .foregroundStyle(colors.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(colors.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(35)
        .padding(.top, 40)
    }
}
