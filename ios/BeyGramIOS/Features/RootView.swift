import SwiftUI

struct RootView: View {
    @StateObject private var telegram = TelegramService()

    var body: some View {
        TabView {
            Group {
                if telegram.phase == .ready {
                    BeyGramChatsView(conversations: telegram.conversations)
                } else {
                    TelegramLoginView(service: telegram)
                }
            }
                .tabItem {
                    Label("Чаты", systemImage: "bubble.left.and.bubble.right")
                }

            placeholder(
                title: "Контакты",
                symbol: "person.crop.circle",
                heading: "Контакты",
                detail: "Контакты Telegram станут доступны после следующего этапа переноса."
            )
            .tabItem {
                Label("Контакты", systemImage: "person.crop.circle")
            }

            placeholder(
                title: "Звонки",
                symbol: "phone",
                heading: "Звонки",
                detail: "Поддержка звонков будет реализована отдельно."
            )
            .tabItem {
                Label("Звонки", systemImage: "phone")
            }

            placeholder(
                title: "Настройки",
                symbol: "gearshape",
                heading: "Настройки BeyGram",
                detail: "В следующих этапах здесь появятся темы, приватность и управление прокси."
            )
            .tabItem {
                Label("Настройки", systemImage: "gearshape")
            }
        }
        .tint(BeyGramPalette.accent)
    }

    private func placeholder(
        title: String,
        symbol: String,
        heading: String,
        detail: String
    ) -> some View {
        NavigationStack {
            ZStack {
                BeyGramPalette.background.ignoresSafeArea()

                VStack(spacing: 18) {
                    Image(systemName: symbol)
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(BeyGramPalette.accent)
                        .accessibilityHidden(true)

                    Text(heading)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text(detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
                .frame(maxWidth: 420)
            }
            .navigationTitle(title)
        }
    }
}
