import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            placeholder(
                title: "Чаты",
                symbol: "bubble.left.and.bubble.right",
                heading: "BeyGram для iPhone",
                detail: "Это первая iOS-сборка. Подключение к Telegram через TDLib ещё не реализовано."
            )
            .tabItem {
                Label("Чаты", systemImage: "bubble.left.and.bubble.right")
            }

            placeholder(
                title: "Контакты",
                symbol: "person.crop.circle",
                heading: "Контакты",
                detail: "Раздел появится после подключения Telegram-сессии."
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
