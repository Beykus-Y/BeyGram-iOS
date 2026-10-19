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
        case .unread: return chat.hasUnread
        }
    }
}

struct BeyGramChatsView: View {
    @ObservedObject var conversations: TelegramConversations
    @Environment(\.colorScheme) private var scheme
    @AppStorage("beygram.appearance.preset") private var appearancePreset = "warm"
    @AppStorage("beygram.chatList.density") private var listDensity = "comfortable"
    @State private var search = ""
    @State private var filter = BeyGramChatFilter.all
    @State private var showingArchive = false
    @State private var showingGlobalSearch = false
    @State private var chatToDelete: TelegramChatPreview?
    @State private var chatActionError: String?
    @State private var openSwipeChatID: Int64?
    @State private var navigationPath: [Int64] = []

    private var colors: BeyGramChatColors { .selected(scheme, preset: appearancePreset) }

    private var rowPadding: CGFloat {
        switch listDensity {
        case "compact": return 6
        case "spacious": return 14
        default: return 10
        }
    }

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
        NavigationStack(path: $navigationPath) {
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
                                archiveCard
                            }

                            // Android only separates pinned chats in the
                            // unfiltered main list.
                            let showPinned = filter == .all && search.isEmpty
                            let pinned = showPinned ? filtered.filter(\.isPinned) : []
                            let regular = showPinned ? filtered.filter { !$0.isPinned } : filtered

                            if !pinned.isEmpty {
                                sectionHeader("ЗАКРЕПЛЁННЫЕ")
                                chatRows(pinned)
                            }
                            if !regular.isEmpty {
                                sectionHeader("ВСЕ ЧАТЫ")
                                chatRows(regular)
                            }

                            if !search.isEmpty {
                                Button {
                                    showingGlobalSearch = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "text.magnifyingglass")
                                        Text("Искать «\(search)» во всех сообщениях")
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                    }
                                    .font(.system(size: 15))
                                    .foregroundStyle(colors.accentInk)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(.plain)
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
            .confirmationDialog(
                "Удалить чат «\(chatToDelete?.title ?? "")»?",
                isPresented: Binding(
                    get: { chatToDelete != nil },
                    set: { if !$0 { chatToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let chat = chatToDelete {
                    Button("Удалить чат только у меня", role: .destructive) {
                        conversations.deleteChatForSelf(chat) { chatActionError = $0 }
                        chatToDelete = nil
                    }
                }
                Button("Отмена", role: .cancel) { chatToDelete = nil }
            } message: {
                Text("История чата будет удалена из вашего аккаунта. У других участников сообщения останутся.")
            }
            .alert(
                "Не удалось выполнить действие",
                isPresented: Binding(
                    get: { chatActionError != nil },
                    set: { if !$0 { chatActionError = nil } }
                )
            ) {
                Button("Понятно", role: .cancel) { chatActionError = nil }
            } message: {
                Text(chatActionError ?? "")
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
                        .tracking(-0.3)
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
                    HStack(spacing: 8) {
                        ForEach(BeyGramChatFilter.allCases) { item in
                            Button {
                                filter = item
                            } label: {
                                HStack(spacing: 6) {
                                    Text(item.rawValue)
                                        .fontWeight(filter == item ? .semibold : .medium)
                                    if item == .unread {
                                        let count = conversations.mainChats.reduce(0) { $0 + $1.unreadCount }
                                        if count > 0 {
                                            Text("\(count)")
                                                .fontWeight(.bold)
                                                .foregroundStyle(
                                                    filter == item ? colors.onAccent : colors.accent
                                                )
                                        }
                                    }
                                }
                                .font(.system(size: 14))
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .foregroundStyle(filter == item ? colors.onAccent : colors.primary)
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

    private var archiveCard: some View {
        let count = conversations.archivedChats.count
        let unread = conversations.archivedChats.reduce(0) { $0 + $1.unreadCount }
        return Button {
            showingArchive = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(colors.accentInk)
                    .frame(width: 44, height: 44)
                    .background(colors.surface2, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Архив")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.primary)
                    Text(unread > 0
                        ? "\(count) \(plural(count, one: "чат", few: "чата", many: "чатов")) · \(unread) непрочитанных"
                        : "\(count) \(plural(count, one: "чат", few: "чата", many: "чатов"))")
                        .font(.system(size: 13))
                        .foregroundStyle(colors.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 18))
                    .foregroundStyle(colors.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(colors.surface, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func plural(
        _ count: Int, one: String, few: String, many: String
    ) -> String {
        let mod100 = count % 100
        let mod10 = count % 10
        if (11...14).contains(mod100) { return many }
        if mod10 == 1 { return one }
        if (2...4).contains(mod10) { return few }
        return many
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
            let listed = chat.mainOrder > 0 || chat.archiveOrder > 0
            BeyGramSwipeChatRow(
                chat: chat, colors: colors, canSwipe: listed,
                openChatID: $openSwipeChatID,
                onRead: {
                    conversations.setChatUnread(
                        chat, unread: !chat.hasUnread
                    ) { chatActionError = $0 }
                },
                onArchive: {
                    conversations.moveChat(
                        chat, toArchive: chat.archiveOrder == 0
                    ) { chatActionError = $0 }
                }
            ) {
                Button {
                    if openSwipeChatID == chat.id {
                        withAnimation(.easeOut(duration: 0.19)) {
                            openSwipeChatID = nil
                        }
                    } else {
                        navigationPath.append(chat.id)
                    }
                } label: {
                    BeyGramChatRow(
                        chat: chat, conversations: conversations, colors: colors,
                        verticalPadding: rowPadding
                    )
                }
                .buttonStyle(.plain)
            }
            .contextMenu {
                // Context actions operate only on actual main/archive rows,
                // never on unlisted matches from Telegram server search.
                if chat.mainOrder > 0 || chat.archiveOrder > 0 {
                    Button {
                        conversations.moveChat(
                            chat, toArchive: chat.archiveOrder == 0
                        ) { chatActionError = $0 }
                    } label: {
                        Label(
                            chat.archiveOrder > 0 ? "Вернуть из архива" : "В архив",
                            systemImage: chat.archiveOrder > 0 ? "tray.and.arrow.up" : "archivebox"
                        )
                    }

                    Button {
                        conversations.setChatPinned(
                            chat, pinned: !chat.isPinned
                        ) { chatActionError = $0 }
                    } label: {
                        Label(
                            chat.isPinned ? "Открепить" : "Закрепить",
                            systemImage: chat.isPinned ? "pin.slash" : "pin"
                        )
                    }

                    Button {
                        conversations.setChatUnread(
                            chat, unread: !chat.hasUnread
                        ) { chatActionError = $0 }
                    } label: {
                        Label(
                            chat.hasUnread ? "Отметить прочитанным" : "Пометить непрочитанным",
                            systemImage: chat.hasUnread ? "envelope.open" : "envelope.badge"
                        )
                    }

                    Menu {
                        Button {
                            conversations.setChatMuted(chat, muted: true) {
                                chatActionError = $0
                            }
                        } label: {
                            Label("Выключить звук", systemImage: "bell.slash")
                        }
                        Button {
                            conversations.setChatMuted(chat, muted: false) {
                                chatActionError = $0
                            }
                        } label: {
                            Label("Включить звук", systemImage: "bell")
                        }
                    } label: {
                        Label("Звук уведомлений", systemImage: "bell")
                    }

                    if chat.canDeleteForSelf {
                        Divider()
                        Button(role: .destructive) {
                            chatToDelete = chat
                        } label: {
                            Label("Удалить чат…", systemImage: "trash")
                        }
                    }
                }
            }
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
    @ObservedObject var conversations: TelegramConversations
    let colors: BeyGramChatColors
    let verticalPadding: CGFloat

    var body: some View {
        HStack(spacing: 14) {
            BeyGramTelegramAvatarView(
                conversations: conversations, file: chat.avatarFile,
                initials: chat.initials, entityID: chat.id, size: 54
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(chat.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.primary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text(chat.lastMessageTime)
                        .font(.system(size: 12,
                                      weight: chat.hasUnread ? .semibold : .regular))
                        .foregroundStyle(chat.hasUnread ? colors.accent : colors.secondary)
                }

                HStack(spacing: 6) {
                    if chat.isMuted {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 15))
                            .foregroundStyle(colors.secondary)
                    }

                    Text(chat.previewLine)
                        .font(.system(size: 14))
                        .foregroundStyle(colors.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if chat.lastMessageOutgoing {
                        switch chat.lastMessageState {
                        case "sending":
                            Image(systemName: "clock")
                                .foregroundStyle(colors.secondary)
                        case "failed":
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.red)
                        case "read":
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(colors.accent)
                        default:
                            Image(systemName: "checkmark")
                                .foregroundStyle(colors.secondary)
                        }
                    }

                    if chat.hasUnread {
                        Text(chat.unreadCount > 99 ? "99+" :
                             (chat.unreadCount > 0 ? String(chat.unreadCount) : "•"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(chat.isMuted ? colors.surface : colors.onAccent)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(
                                chat.isMuted ? colors.secondary : colors.accent,
                                in: Capsule()
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
    }
}
