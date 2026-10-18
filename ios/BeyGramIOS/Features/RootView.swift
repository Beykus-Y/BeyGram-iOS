import SwiftUI

struct RootView: View {
    @StateObject private var telegram = TelegramService()
    @AppStorage("beygram.appearance.mode") private var appearanceMode = "system"
    @AppStorage("beygram.appearance.preset") private var appearancePreset = "warm"

    private var chosenScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

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

            Group {
                if telegram.phase == .ready {
                    BeyGramContactsView(conversations: telegram.conversations)
                } else {
                    placeholder(
                        title: "Контакты",
                        symbol: "person.crop.circle",
                        heading: "Контакты",
                        detail: "Контакты Telegram доступны после авторизации."
                    )
                }
            }
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

            BeyGramSettingsView()
                .tabItem {
                Label("Настройки", systemImage: "gearshape")
            }
        }
        .preferredColorScheme(chosenScheme)
        .tint(appearancePreset == "graphite" ? Color(red: 59/255, green: 91/255, blue: 219/255) : BeyGramPalette.accent)
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
