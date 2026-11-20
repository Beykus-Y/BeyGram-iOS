import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import BeyGramKit
import BeyGramYandexMusic

private final class BeyGramYandexArguments {
    let accept: () -> Void
    let revoke: () -> Void
    let signIn: () -> Void
    let cancelSignIn: () -> Void
    let openVerification: () -> Void
    let signOut: () -> Void

    init(accept: @escaping () -> Void, revoke: @escaping () -> Void, signIn: @escaping () -> Void, cancelSignIn: @escaping () -> Void, openVerification: @escaping () -> Void, signOut: @escaping () -> Void) {
        self.accept = accept
        self.revoke = revoke
        self.signIn = signIn
        self.cancelSignIn = cancelSignIn
        self.openVerification = openVerification
        self.signOut = signOut
    }
}

private enum BeyGramYandexSection: Int32 {
    case warning
    case account
    case info
}

/// The screen state that the entries are drawn from.
private struct BeyGramYandexState: Equatable {
    var accepted: Bool
    var configured: Bool
    var signedIn: Bool
    var waitingCode: String?
    var verificationUrl: String?
    var failure: String?
}

private enum BeyGramYandexEntry: ItemListNodeEntry {
    case warning(String)
    case accept(String)
    case notConfigured(String)
    case signIn(String)
    case code(String)
    case openVerification(String)
    case cancelSignIn(String)
    case signedIn(String)
    case signOut(String)
    case revoke(String)
    case failure(String)

    var section: ItemListSectionId {
        switch self {
        case .warning, .accept:
            return BeyGramYandexSection.warning.rawValue
        case .notConfigured, .signIn, .code, .openVerification, .cancelSignIn, .signedIn, .signOut, .failure:
            return BeyGramYandexSection.account.rawValue
        case .revoke:
            return BeyGramYandexSection.info.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .warning: return 0
        case .accept: return 1
        case .notConfigured: return 2
        case .signIn: return 3
        case .code: return 4
        case .openVerification: return 5
        case .cancelSignIn: return 6
        case .signedIn: return 7
        case .signOut: return 8
        case .failure: return 9
        case .revoke: return 10
        }
    }

    static func ==(lhs: BeyGramYandexEntry, rhs: BeyGramYandexEntry) -> Bool {
        return lhs.stableId == rhs.stableId && lhs.text == rhs.text
    }

    static func <(lhs: BeyGramYandexEntry, rhs: BeyGramYandexEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    var text: String {
        switch self {
        case let .warning(text), let .accept(text), let .notConfigured(text), let .signIn(text), let .code(text),
             let .openVerification(text), let .cancelSignIn(text), let .signedIn(text), let .signOut(text), let .failure(text), let .revoke(text):
            return text
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! BeyGramYandexArguments
        switch self {
        case let .warning(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .accept(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.accept()
            })
        case let .notConfigured(text), let .code(text), let .signedIn(text), let .failure(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .signIn(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.signIn()
            })
        case let .openVerification(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.openVerification()
            })
        case let .cancelSignIn(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.cancelSignIn()
            })
        case let .signOut(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.signOut()
            })
        case let .revoke(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.revoke()
            })
        }
    }
}

private func beyGramYandexEntries(state: BeyGramYandexState, isRussian: Bool) -> [BeyGramYandexEntry] {
    var entries: [BeyGramYandexEntry] = []
    entries.append(.warning(BGYandexWarning.text(isRussian: isRussian)))
    if !state.accepted {
        entries.append(.accept(isRussian ? "Принимаю риск и включаю" : "I accept the risk and turn it on"))
        return entries
    }
    if !state.configured {
        entries.append(.notConfigured(isRussian
            ? "В этой сборке не задана OAuth-пара Яндекса, поэтому источник скрыт."
            : "This build has no Yandex OAuth pair, so the source stays hidden."))
        entries.append(.revoke(isRussian ? "Отозвать согласие" : "Revoke consent"))
        return entries
    }
    if state.signedIn {
        entries.append(.signedIn(isRussian ? "Вход выполнен. Токен хранится в Keychain." : "Signed in. The token is kept in the Keychain."))
        entries.append(.signOut(isRussian ? "Выйти и удалить кэш треков" : "Sign out and delete cached tracks"))
    } else if let code = state.waitingCode {
        entries.append(.code(isRussian ? "Введите код на странице Яндекса: \(code)" : "Enter this code on the Yandex page: \(code)"))
        entries.append(.openVerification(isRussian ? "Открыть страницу входа" : "Open the sign-in page"))
        entries.append(.cancelSignIn(isRussian ? "Отменить вход" : "Cancel sign-in"))
    } else {
        entries.append(.signIn(isRussian ? "Войти через Яндекс" : "Sign in with Yandex"))
    }
    if let failure = state.failure {
        entries.append(.failure(failure))
    }
    entries.append(.revoke(isRussian ? "Отозвать согласие и выйти" : "Revoke consent and sign out"))
    return entries
}

/// The Yandex Music screen: the warning, acceptance, device sign-in, and sign-out. Off unless the flag is on.
public func beyGramYandexMusicController(context: AccountContext) -> ViewController {
    let service = BGYandexService(
        credentials: BGYandexCredentials.fromBundle(),
        cacheDirectory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("beygram/yandex", isDirectory: true)
    )
    let consent = BGYandexConsent(defaults: .standard)
    var state = BeyGramYandexState(accepted: consent.isAccepted, configured: service.credentials.isConfigured, signedIn: service.isSignedIn, waitingCode: nil, verificationUrl: nil, failure: nil)
    var refreshCount = 0
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    let update: () -> Void = {
        refreshCount += 1
        refresh.set(refreshCount)
    }

    let arguments = BeyGramYandexArguments(
        accept: {
            consent.accept()
            state.accepted = true
            update()
        },
        revoke: {
            service.cancelSignIn()
            service.signOut()
            consent.revoke()
            state = BeyGramYandexState(accepted: false, configured: state.configured, signedIn: false, waitingCode: nil, verificationUrl: nil, failure: nil)
            update()
        },
        signIn: {
            state.failure = nil
            state.waitingCode = nil
            service.startSignIn { event in
                switch event {
                case let .code(code):
                    state.waitingCode = code.userCode
                    state.verificationUrl = code.verificationUrl
                case .finished:
                    state.waitingCode = nil
                    state.verificationUrl = nil
                    state.signedIn = true
                case let .failed(reason):
                    state.waitingCode = nil
                    state.verificationUrl = nil
                    state.failure = "\(reason)"
                }
                update()
            }
            update()
        },
        cancelSignIn: {
            service.cancelSignIn()
            state.waitingCode = nil
            state.verificationUrl = nil
            update()
        },
        openVerification: {
            if let url = state.verificationUrl {
                context.sharedContext.applicationBindings.openUrl(url)
            }
        },
        signOut: {
            service.signOut()
            state.signedIn = false
            update()
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.primaryComponent.languageCode == "ru"
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Яндекс Музыка"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: beyGramYandexEntries(state: state, isRussian: isRussian), style: .blocks)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
