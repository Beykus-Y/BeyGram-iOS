import Foundation
import SwiftSignalKit
import Postbox
internal import TelegramApi

// BG Push: регистрация web push токена (token_type 10) в Telegram под сессией аккаунта.
//
// Файл новый и не меняет существующий путь APNs и VoIP (RegisterNotificationToken.swift).
// Токен здесь не hex-кодируется: это JSON-строка с endpoint и ключами PWA.
// Поле secret пока пустое: нужен ли ключ уведомлений, решит прототип на iPhone (issue #30 в BeyGram-Diagnostics-Server).

private let beyGramWebPushTokenType: Int32 = 10

/// Регистрирует web push токен. Результат: true, если Telegram принял запрос, и false при любой ошибке.
public func beyGramRegisterWebPushToken(account: Account, token: String, otherAccountUserIds: [PeerId.Id]) -> Signal<Bool, NoError> {
    return account.network.request(Api.functions.account.registerDevice(flags: 0, tokenType: beyGramWebPushTokenType, token: token, appSandbox: .boolFalse, secret: Buffer(data: Data()), otherUids: otherAccountUserIds.map({ $0._internalGetInt64Value() })))
    |> map { _ -> Bool in
        return true
    }
    |> `catch` { _ -> Signal<Bool, NoError> in
        return .single(false)
    }
}

/// Снимает web push токен с сессии аккаунта.
public func beyGramUnregisterWebPushToken(account: Account, token: String, otherAccountUserIds: [PeerId.Id]) -> Signal<Never, NoError> {
    return account.network.request(Api.functions.account.unregisterDevice(tokenType: beyGramWebPushTokenType, token: token, otherUids: otherAccountUserIds.map({ $0._internalGetInt64Value() })))
    |> retryRequest
    |> ignoreValues
}
