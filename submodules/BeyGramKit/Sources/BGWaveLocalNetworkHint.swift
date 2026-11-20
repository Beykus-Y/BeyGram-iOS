import Foundation

/// The hint that the BG Wave screen shows after a listener session fails where a denied Local Network permission may be
/// the cause. The session layer decides when that is (`BGWaveListenerFailure.localNetworkSuspected`).
///
/// iOS reports that denial to no API, so the text says "may be blocked", never "is blocked". This module does not present
/// the alert: that needs UIKit, and the screen owns UIKit.
public struct BGWaveLocalNetworkHint: Equatable {
    public let title: String
    public let message: String
    public let settingsButtonTitle: String
    public let dismissButtonTitle: String

    /// Opens this app's page in Settings. It equals `UIApplication.openSettingsURLString`, written out so that this module
    /// needs no UIKit import.
    public static let settingsURLString = "app-settings:"

    public static func make(languageCode: String? = nil) -> BGWaveLocalNetworkHint {
        let l10n = BeyGramL10n.shared
        return BGWaveLocalNetworkHint(
            title: l10n.string(.bgWaveLocalNetworkTitle, languageCode: languageCode),
            message: l10n.string(.bgWaveLocalNetworkMessage, languageCode: languageCode),
            settingsButtonTitle: l10n.string(.bgWaveLocalNetworkSettings, languageCode: languageCode),
            dismissButtonTitle: l10n.string(.bgWaveLocalNetworkNotNow, languageCode: languageCode)
        )
    }
}
