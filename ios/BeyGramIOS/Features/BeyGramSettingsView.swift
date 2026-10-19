import SwiftUI

/// Native settings for the Android BeyGram Warm / Graphite design tokens.
struct BeyGramSettingsView: View {
    @AppStorage("beygram.appearance.mode") private var appearanceMode = "system"
    @AppStorage("beygram.appearance.preset") private var appearancePreset = "warm"
    @AppStorage("beygram.chatList.density") private var chatListDensity = "comfortable"
    @Environment(\.colorScheme) private var scheme

    private var colors: BeyGramChatColors {
        .selected(scheme, preset: appearancePreset)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BEYGRAM")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1.3)
                            .foregroundStyle(colors.accent)
                        Text("Настройки")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(colors.primary)
                    }

                    section("ОФОРМЛЕНИЕ") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Цветовая палитра")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(colors.primary)

                            HStack(spacing: 12) {
                                presetTile("Тёплая", value: "warm",
                                    fill: Color(red: 106/255, green: 79/255, blue: 220/255))
                                presetTile("Графит", value: "graphite",
                                    fill: Color(red: 59/255, green: 91/255, blue: 219/255))
                            }

                            Divider()

                            Text("Режим отображения")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(colors.primary)

                            Picker("Режим отображения", selection: $appearanceMode) {
                                Text("Система").tag("system")
                                Text("Светлая").tag("light")
                                Text("Тёмная").tag("dark")
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    section("СПИСОК ЧАТОВ") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Плотность строк")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(colors.primary)

                            Picker("Плотность строк", selection: $chatListDensity) {
                                Text("Компактно").tag("compact")
                                Text("Обычно").tag("comfortable")
                                Text("Просторно").tag("spacious")
                            }
                            .pickerStyle(.segmented)

                            Text("Те же три варианта, что в Android BeyGram. Изменение применяется сразу.")
                                .font(.caption)
                                .foregroundStyle(colors.secondary)
                        }
                    }

                    section("О ПРИЛОЖЕНИИ") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("BeyGram для iOS")
                                .font(.headline)
                                .foregroundStyle(colors.primary)
                            Text("Нативная версия на SwiftUI и TDLib.")
                                .font(.subheadline)
                                .foregroundStyle(colors.secondary)
                            Text("Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
                                .font(.footnote)
                                .foregroundStyle(colors.secondary)
                        }
                    }

                    section("В РАЗРАБОТКЕ") {
                        Text("Mihomo, настройка прокси, расширенные темы, уведомления и медиа будут перенесены отдельно. Эти переключатели пока не показываются, чтобы не вводить в заблуждение.")
                            .font(.subheadline)
                            .foregroundStyle(colors.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .background(colors.screen.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }

    private func section<Content: View>(
        _ heading: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(heading)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(colors.secondary)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
                .background(colors.surface, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func presetTile(_ title: String, value: String, fill: Color) -> some View {
        Button {
            appearancePreset = value
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(fill)
                        .frame(width: 30, height: 30)
                    Spacer()
                    if appearancePreset == value {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(colors.accent)
                    }
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.primary)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surface2, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(appearancePreset == value ? colors.accent : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
