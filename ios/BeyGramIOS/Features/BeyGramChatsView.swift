import SwiftUI

private enum BeyGramChatFilter: String, CaseIterable, Identifiable {
    case all = "Все"
    case people = "Люди"
    case groups = "Группы"
    case unread = "Непрочитанные"

    var id: Self { self }

    func matches(_ chat: TelegramChatPreview) -> Bool {
        switch self {
        case .all: return true
        case .people: return !chat.isGroup
        case .groups: return chat.isGroup
        case .unread: return chat.unreadCount > 0
        }
    }
}

struct BeyGramChatsView: View {
    @ObservedObject var conversations: TelegramConversations
    @Environment(\.colorScheme) private var scheme
    @AppStorage("beygram.appearance.preset") private var appearancePreset = "warm"
    @State private var search = ""
    @State private var filter = BeyGramChatFilter.all
    @State private var showingArchive = false
    @State private var showingGlobalSearch = false

    private var colors: BeyGramChatColors { .selected(scheme, preset: appearancePreset) }

    private var remoteOnly: [TelegramChatPreview] {
        guard !search.isEmpty else { return [] }
        let visibleIDs = Set(filtered.map(\.id))
        return conversations.matchingChats.filter {
            filter.matches($0) && !visibleIDs.contains($0.id)
        }
    }

    private var filtered: [TelegramChatPreview] {
        conversations.mainChats.filter { chat in
            filter.matches(chat) &&
            (search.isEmpty || chat.title.localizedCaseInsensitiveContains(search) ||
             chat.lastMessage.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if showingArchive {
                            Button {
                                showingArchive = false
                            } label: {
                                Label("Назад к чатам", systemImage: "arrow.left")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(18)
                            }
                            .tint(colors.accent)

                            chatRows(conversations.archivedChats)
                        } else {
                            if !conversations.archivedChats.isEmpty,
                               filter == .all, search.isEmpty {
                                Button {
                                    showingArchive = true
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "archivebox.fill")
                                            .font(.title3)
                                            .foregroundStyle(colors.accent)
                                            .frame(width: 48, height: 48)
                                            .background(colors.accentSoft, in: Circle())
                                        Text("Архив")
                                            .font(.headline)
                                            .foregroundStyle(colors.primary)
                                        Spacer()
                                        Text("\(conversations.archivedChats.count)")
                                            .foregroundStyle(colors.secondary)
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(colors.secondary)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                            }

                            let pinned = filtered.filter(\.isPinned)
                            let regular = filtered.filter { !$0.isPinned }

                            if !pinned.isEmpty {
                                sectionHeader("ЗАКРЕПЛЁННЫЕ")
                                chatRows(pinned)
                            }
                            if !regular.isEmpty {
                                sectionHeader("ВСЕ ЧАТЫ")
                                chatRows(regular)
                            }

                            if !remoteOnly.isEmpty {
                                sectionHeader("ЕЩЁ В TELEGRAM")
                                chatRows(remoteOnly)
                            }

                            if conversations.isSearchingChats && !search.isEmpty {
                                ProgressView("Ищем чаты в Telegram…")
                                    .font(.footnote)
                                    .tint(colors.accent)
                                    .padding(.vertical, 18)
                            }

                            if filtered.isEmpty && remoteOnly.isEmpty &&
                               !conversations.isSearchingChats {
                                emptyState
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .refreshable {
                    conversations.refreshChatList()
                }
            }
            .background(colors.screen.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $showingGlobalSearch) {
                BeyGramGlobalMessageSearchView(conversations: conversations)
            }
            .task(id: search) {
                // Immediately hide stale results while waiting for debounce.
                conversations.clearChatSearch()
                let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return }
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                conversations.searchKnownChats(query)
            }
            .navigationDestination(for: Int64.self) { id in
                if let chat = (conversations.mainChats + conversations.archivedChats +
                   conversations.matchingChats).first(where: { $0.id == id }) {
                    BeyGramConversationView(conversations: conversations, chat: chat)
                } else {
                    Text("Чат больше недоступен.")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BEYGRAM")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(colors.accent)

                HStack(spacing: 12) {
                    Text(showingArchive ? "Архив" : "Чаты")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(colors.primary)

                    Spacer()

                    if !showingArchive {
                        Button {
                            showingGlobalSearch = true
                        } label: {
                            Image(systemName: "text.magnifyingglass")
                                .font(.system(size: 21))
                                .foregroundStyle(colors.accent)
                                .frame(width: 40, height: 40)
                                .background(colors.accentSoft, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Поиск по всем сообщениям")
                    }
                }
            }
            .padding(.top, 10)

            if !showingArchive {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(colors.secondary)
                    TextField("Поиск по чатам", text: $search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .tint(colors.accent)
                }
                .padding(.horizontal, 14)
                .frame(height: 43)
                .background(colors.surface2, in: RoundedRectangle(cornerRadius: 14))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(BeyGramChatFilter.allCases) { item in
                            Button {
                                filter = item
                            } label: {
                                HStack(spacing: 6) {
                                    Text(item.rawValue)
                                    if item == .unread {
                                        let count = conversations.mainChats.reduce(0) { $0 + $1.unreadCount }
                                        if count > 0 { Text("\(count)") }
                                    }
                                }
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .foregroundStyle(filter == item ? colors.onAccent : colors.secondary)
                                .background(filter == item ? colors.accent : colors.surface2,
                                            in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(colors.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 17)
            .padding(.bottom, 6)
    }

    private func chatRows(_ rows: [TelegramChatPreview]) -> some View {
        ForEach(rows) { chat in
            NavigationLink(value: chat.id) {
                BeyGramChatRow(chat: chat, colors: colors)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 42))
                .foregroundStyle(colors.accent)
            Text(search.isEmpty ? "Чатов пока нет" : "Ничего не найдено")
                .font(.headline)
                .foregroundStyle(colors.primary)
            Text(search.isEmpty
                 ? "Чаты появятся здесь после загрузки из Telegram."
                 : "Попробуйте другое имя или название чата.")
                .font(.footnote)
                .foregroundStyle(colors.secondary)
                .multilineTextAlignment(.center)
            Button("Обновить") { conversations.refreshChatList() }
                .tint(colors.accent)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

private struct BeyGramChatRow: View {
    let chat: TelegramChatPreview
    let colors: BeyGramChatColors

    var body: some View {
        HStack(spacing: 13) {
            Text(chat.initials)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(BeyGramAvatarStyle.color(for: chat.id), in: Circle())

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Text(chat.title)
                        .font(.system(size: 16, weight: chat.unreadCount > 0 ? .bold : .semibold))
                        .foregroundStyle(colors.primary)
                        .lineLimit(1)

                    if chat.isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(colors.secondary)
                    }
                    Spacer(minLength: 6)
                    Text(chat.lastMessageTime)
                        .font(.system(size: 11))
                        .foregroundStyle(colors.secondary)
                }

                HStack(spacing: 7) {
                    Text(chat.lastMessage.isEmpty ? "Нет сообщений" : chat.lastMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(colors.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)
                    if chat.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(colors.secondary)
                    }

                    if chat.unreadCount > 0 {
                        Text(chat.unreadCount > 99 ? "99+" : String(chat.unreadCount))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(chat.isMuted ? colors.secondary : colors.onAccent)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(chat.isMuted ? colors.surface2 : colors.accent, in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
