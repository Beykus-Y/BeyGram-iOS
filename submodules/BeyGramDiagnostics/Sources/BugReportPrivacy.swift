import Foundation

/// On-device redaction for diagnostic report text (port of Android `ReportPrivacy`).
///
/// The server sanitizer is the second line, not a replacement: text that enters a report must already be
/// free of URLs, addresses, tokens and keyed secrets. A removed value leaves the marker `[скрыто: <класс>]`,
/// so the class of the value stays visible. The passes run in the same order as on Android.
///
/// The patterns are compiled with `NSRegularExpression` (ICU), which backtracks, as Android's Java regex does.
/// Callers must cap the input length before calling: the hostname pattern can take quadratic time on long
/// inputs with many dots or hyphens.
public enum BugReportPrivacy {
    private static let botToken = compile(#"\b\d{6,12}:[A-Za-z0-9_-]{30,}(?![A-Za-z0-9_-])"#)
    private static let jwt = compile(#"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#)
    private static let subscriptionScheme = compile(#"(?i)\b(?:vmess|vless|trojan|ss|ssr|hysteria2?|tuic|socks5?|https?)://[^\s<>"']+"#)
    private static let url = compile(#"(?i)\b[a-z][a-z0-9+.-]{1,31}://[^\s<>"']+"#)
    private static let ipv4 = compile(#"\b(?:\d{1,3}\.){3}\d{1,3}(?::\d{1,5})?\b"#)
    /// Bracketed IPv6, or at least two colon-separated hex groups. The count of colons decides later.
    private static let ipv6Candidate = compile(#"\[[0-9a-fA-F:]+\]|(?:[0-9a-fA-F]{1,4}:){2,7}[0-9a-fA-F]{0,4}"#)
    private static let hostname = compile(#"\b(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,24}(?::\d{1,5})?\b"#, options: [.caseInsensitive])
    private static let phoneNumber = compile(#"\+\d[\d ().-]{6,}\d|\b\d{7,}\b"#)
    private static let longHex = compile(#"\b[0-9a-fA-F]{32,}\b"#)
    private static let longBase64Like = compile(#"\b[A-Za-z0-9+/=_-]{40,}\b"#)
    private static let keyedSecret = compile(#"(?i)\b(api[_-]?hash|api[_-]?id|token|password|passwd|secret|authorization|credential|key|cookie|session|phone|nonce|login|user(?:name)?|host|server|endpoint|proxy|subscribe(?:_url)?|url|link)(\s*[=:]\s*)(\[[^\]\n]*\]|\S+)"#)

    /// Replaces secrets and addresses with markers. Call it once per string: the passes are not idempotent.
    /// The URL pass matches a generic link's marker again when it runs a second time, as on Android.
    public static func redact(_ text: String) -> String {
        var result = text
        result = replacing(botToken, in: result) { _, _ in "[скрыто: токен]" }
        result = replacing(jwt, in: result) { _, _ in "[скрыто: токен]" }
        result = replacing(subscriptionScheme, in: result) { _, _ in "[скрыто: ссылка]" }
        result = replacing(url, in: result) { match, source in
            // The scheme stays and the address goes: the kind of link is useful, its contents are not.
            let value = source.substring(with: match.range)
            let scheme = value.range(of: "://").map { String(value[..<$0.lowerBound]) } ?? value
            return "\(scheme)://[скрыто: ссылка]"
        }
        result = replacing(ipv4, in: result) { _, _ in "[скрыто: адрес]" }
        result = replacing(ipv6Candidate, in: result) { match, source in
            let value = source.substring(with: match.range)
            let isBracketed = value.hasPrefix("[")
            let colonCount = value.filter { $0 == ":" }.count
            return isBracketed || colonCount >= 3 ? "[скрыто: адрес]" : value
        }
        result = replacing(hostname, in: result) { _, _ in "[скрыто: хост]" }
        result = replacing(phoneNumber, in: result) { _, _ in "[скрыто: номер]" }
        result = replacing(longHex, in: result) { _, _ in "[скрыто: ключ]" }
        result = replacing(longBase64Like, in: result) { _, _ in "[скрыто: ключ]" }
        result = replacing(keyedSecret, in: result) { match, source in
            // The key and its separator stay; only the value is replaced.
            source.substring(with: match.range(at: 1)) + source.substring(with: match.range(at: 2)) + "[скрыто]"
        }
        return result
    }

    /// Removes control characters except line breaks and tabs, as the server does before it stores text.
    public static func stripControls(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where scalar == "\n" || scalar == "\t" || scalar.value >= 32 {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// Cleans, redacts and shortens a value. `maxLength` counts UTF-16 code units, as Android counts characters.
    /// A cut never splits a surrogate pair.
    public static func sanitize(_ text: String, maxLength: Int) -> String {
        let cleaned = redact(stripControls(text)).trimmingCharacters(in: CharacterSet(charactersIn: "\n\r \t"))
        let units = Array(cleaned.utf16)
        guard units.count > maxLength else {
            return cleaned
        }
        var end = max(maxLength, 0)
        while end > 0, (0xD800 ... 0xDBFF).contains(units[end - 1]) {
            end -= 1
        }
        return String(decoding: units[0 ..< end], as: UTF16.self)
    }

    // MARK: - Private

    private static func compile(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // The patterns are constants, and the tests compile each one. A failure here is a programming error.
        return try! NSRegularExpression(pattern: pattern, options: options)
    }

    /// Replaces every match, left to right. `transform` receives the match and the text it was found in.
    private static func replacing(
        _ regex: NSRegularExpression,
        in text: String,
        _ transform: (NSTextCheckingResult, NSString) -> String
    ) -> String {
        let source = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: source.length))
        if matches.isEmpty {
            return text
        }
        var result = ""
        var position = 0
        for match in matches {
            result += source.substring(with: NSRange(location: position, length: match.range.location - position))
            result += transform(match, source)
            position = match.range.location + match.range.length
        }
        result += source.substring(from: position)
        return result
    }
}
