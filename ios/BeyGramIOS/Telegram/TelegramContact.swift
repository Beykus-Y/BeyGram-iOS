import Foundation

/// Contact data from TDLib getContacts/getUser, not the local iOS address book.
struct TelegramContact: Identifiable, Equatable {
    let id: Int64
    let firstName: String
    let lastName: String
    let username: String
    let online: Bool

    var fullName: String {
        let name = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? (username.isEmpty ? "Пользователь" : "@"+username) : name
    }

    var initials: String {
        let letters = [firstName.first, lastName.first].compactMap { $0 }
        return letters.isEmpty ? "?" : letters.map(String.init).joined().uppercased()
    }

    func withOnline(_ status: Bool) -> Self {
        Self(id: id, firstName: firstName, lastName: lastName,
             username: username, online: status)
    }

    static func from(_ raw: [String: Any]) -> Self? {
        let id = TelegramJSON.int64(raw["id"])
        guard id != 0 else { return nil }
        let usernames = TelegramJSON.object(raw["usernames"])
        let active = usernames["active_usernames"] as? [String] ?? []
        let username = active.first ?? TelegramJSON.string(raw["username"])
        let status = TelegramJSON.object(raw["status"])
        return Self(
            id: id,
            firstName: TelegramJSON.string(raw["first_name"]),
            lastName: TelegramJSON.string(raw["last_name"]),
            username: username,
            online: TelegramJSON.string(status["@type"]) == "userStatusOnline"
        )
    }
}
