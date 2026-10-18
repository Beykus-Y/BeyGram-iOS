import SwiftUI

struct TelegramStatusView: View {
    @StateObject private var service = TelegramService()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(BeyGramPalette.accent)

            Text("BeyGram для iPhone")
                .font(.title2.bold())

            switch service.state {
            case .unavailable(let reason):
                Text(reason)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .disconnected:
                Text("Нет подключения")
            case .connecting:
                ProgressView("Подключение…")
            case .ready:
                Text("Подключено")
            }
        }
        .padding(32)
        .frame(maxWidth: 420)
        .accessibilityElement(children: .combine)
    }
}
