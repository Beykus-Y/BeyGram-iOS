import SwiftUI

struct TelegramLoginView: View {
    @ObservedObject var service: TelegramService

    @State private var phoneNumber = ""
    @State private var code = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            ZStack {
                BeyGramPalette.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 54, weight: .light))
                            .foregroundStyle(BeyGramPalette.accent)
                            .accessibilityHidden(true)

                        Text("BeyGram")
                            .font(.largeTitle.bold())

                        phaseContent

                        if let error = service.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity)
                    .padding(26)
                    .padding(.top, 24)
                }
            }
            .navigationTitle("Чаты")
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch service.phase {
        case .missingConfiguration:
            description("В сборке отсутствуют Telegram API ID и API Hash. Проверьте настройки CI.")
        case .initializing:
            ProgressView("Запускаем Telegram…")
        case .phoneNumber:
            Text("Войдите в аккаунт Telegram")
                .font(.headline)

            TextField("+79991234567", text: $phoneNumber)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Номер телефона")

            actionButton("Получить код") {
                service.submitPhone(phoneNumber)
            }
        case .code:
            Text("Введите код подтверждения")
                .font(.headline)

            if let details = service.codeDeliveryInfo {
                description(details.instructions)
            } else {
                description("Telegram запрашивает код. Проверьте активные сеансы Telegram и SMS.")
            }

            TextField("Код подтверждения", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Код подтверждения")

            actionButton("Подтвердить") {
                service.submitCode(code)
            }

            if let details = service.codeDeliveryInfo, let nextMethod = details.nextMethod {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = max(0, Int(ceil(details.resendAvailableAt.timeIntervalSince(context.date))))
                    Button {
                        service.resendCode()
                    } label: {
                        Text(seconds > 0
                             ? "Другой способ через \(seconds) с"
                             : "Запросить код повторно: \(nextMethod)")
                    }
                    .buttonStyle(.bordered)
                    .disabled(seconds > 0 || service.isSubmitting)
                }
            } else {
                description("Telegram пока не предложил повторную отправку кода.")
            }
        case .password:
            Text("Двухэтапная аутентификация")
                .font(.headline)

            SecureField("Облачный пароль", text: $password)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)

            actionButton("Войти") {
                service.submitPassword(password)
                password = ""
            }
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Вы вошли в Telegram")
                .font(.headline)
            description("Сессия сохранена на устройстве. Экран чатов и отправка сообщений появятся в следующем этапе.")
        case .actionRequired(let message):
            description(message)
        case .failed(let message):
            description(message)
        }
    }

    private func description(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private func actionButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if service.isSubmitting {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text(label)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(BeyGramPalette.accent)
        .disabled(service.isSubmitting)
    }
}
