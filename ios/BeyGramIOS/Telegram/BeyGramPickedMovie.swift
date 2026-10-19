import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// PhotosPicker hands us a temporary provider file. FileRepresentation's
/// callback is the only safe place to make an owned copy before the provider
/// deletes its URL. Video bytes never pass through a Data object.
struct BeyGramPickedMovie: Transferable {
    let localURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("BeyGramPicked-" + UUID().uuidString)
                .appendingPathExtension("mov")
            try FileManager.default.copyItem(at: received.file, to: temporary)
            return Self(localURL: temporary)
        }
    }
}
