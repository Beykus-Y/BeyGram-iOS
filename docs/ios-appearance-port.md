# Android → iOS: appearance preferences

Based on `BeyGram/ui/theme/Color.kt` at Android DEV.

- Exact Warm light/dark token values.
- Exact Graphite light/dark token values.
- Mode override: System, Light, Dark.
- Shared `@AppStorage` preferences persist between runs and apply to the chat list, conversation screen, contacts, Settings and tab accent.
- Settings only shows options that are implemented; networking/Mihomo/notifications are explicitly deferred.

Still missing for complete Android parity: reactive arbitrary theme tokens, per-chat overrides, UI density, wallpaper, custom bubble shapes, theme export/import, icon packs, and complete coloring of authentication and placeholder screens.

No credentials, account/session state or Keychain data are altered.
