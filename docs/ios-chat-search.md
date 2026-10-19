# BeyGram iOS — TDLib-known chat search

## Android parity
The Android client searches beyond visible rows in the initial chat list. iOS previously filtered only the first 100 loaded chat previews.

## Implementation
- TDLib `searchChats` finds known chats in the local index.
- TDLib `searchChatsOnServer` searches known chats remotely (not arbitrary public accounts or usernames).
- Text input is debounced 350ms in SwiftUI. Search revision tokens reject out-of-order responses.
- The first 35 IDs from each source are deduplicated, fetched with TDLib `getChat`, then displayed under "ЕЩЁ В TELEGRAM".
- Same All / People / Groups / Unread filter rules apply, and navigation can open returned chats.
- Clearing search invalidates pending requests and clears the results. Server errors do not fabricate results.
- Never log or store search queries outside TDLib; no third-party search APIs.

## Deferred
Global message content search, public chat discovery, pagination, suggestions and advanced filters.
Requires a working authenticated account to validate.
