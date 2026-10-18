import SwiftUI

/// Android's Telegram contacts screen ported with the same Warm tokens.
struct BeyGramContactsView: View {
    @ObservedObject var conversations: TelegramConversations
    @Environment(\.colorScheme) private var scheme
    @AppStorage("beygram.appearance.preset") private var appearancePreset = "warm"
    @State private var query = ""
    @State private var path: [Int64] = []

    private var colors: BeyGramChatColors { .selected(scheme, preset: appearancePreset) }

    private var results: [TelegramContact] {
        conversations.contacts.filter {
            query.isEmpty ||
            $0.fullName.localizedCaseInsensitiveContains(query) ||
            $0.username.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("BEYGRAM")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(colors.accent)

                    Text("Контакты")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(colors.primary)

                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(colors.secondary)
                        TextField("Поиск контакта", text: $query)
                            .textInputAutocapitalization(.never)
                            .tint(colors.accent)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 43)
                    .background(colors.surface2, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 14)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if conversations.contactsLoading {
                            ProgressView("Загружаем контакты…")
                                .tint(colors.accent)
                                .padding(.top, 40)
                        } else if results.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 42))
                                    .foregroundStyle(colors.accent)
                                Text(query.isEmpty ? "Контактов пока нет" : "Не найдено")
                                    .font(.headline)
                                    .foregroundStyle(colors.primary)
                                Text("Будут показаны контакты из Telegram.")
                                    .foregroundStyle(colors.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 70)
                        }

                        ForEach(results) { user in
                            Button {
                                conversations.openPrivateChat(user.id) { id in
                                    if let id { path.append(id) }
                                }
                            } label: {
                                HStack(spacing: 13) {
                                    Text(user.initials)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 50, height: 50)
                                        .background(
                                            BeyGramAvatarStyle.color(for: user.id),
                                            in: Circle()
                                        )

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(user.fullName)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(colors.primary)
                                        Text(user.online ? "в сети"
                                             : user.username.isEmpty ? "Telegram" : "@"+user.username)
                                            .font(.system(size: 13))
                                            .foregroundStyle(user.online ? colors.accent : colors.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(colors.secondary)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .refreshable { conversations.loadContacts() }
            }
            .background(colors.screen.ignoresSafeArea())
            .navigationBarHidden(true)
            .navigationDestination(for: Int64.self) { id in
                if let chat = conversations.chat(for: id) {
                    BeyGramConversationView(conversations: conversations, chat: chat)
                } else {
                    Text("Не удалось открыть личный чат.")
                }
            }
            .onAppear {
                if conversations.contacts.isEmpty { conversations.loadContacts() }
            }
        }
    }
}
