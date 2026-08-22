# Max for macOS 26 Tahoe

Native SwiftUI client for macOS 26. The Mac app carries the iPhone product
surfaces into a desktop-first `NavigationSplitView`, native Settings scene,
keyboard commands, resizable windows, and pointer-aware Liquid Glass controls.

## Product coverage

- Vault search, type filtering, sorting, context actions, upload, and transfers.
- Native media detail/player, save, offline, share-to-chat, and independent dual ratings.
- Library overview, Saved, Ratings, Offline, Collections, and Trash.
- Shared files, spaces, members, and workspace media.
- Chats, media messages, reactions, composer, conversation details, and new conversation.
- Profile, editing, account controls, themes, English/Arabic RTL, privacy, server, and Double Lock settings.
- Memories, plugin store, and the global Command-K palette.

The deterministic Demo fixtures keep CI screenshots repeatable and offline. The
included `MaxAPIClient` speaks to the same `/api/v2` origin used by the iPhone
client when a real server is configured.

## Generate and build

```sh
cd apps/macos
xcodegen generate --spec project.yml
xcodebuild -project MaxMac.xcodeproj -scheme MaxMac -destination 'platform=macOS' build
```

The GitHub Actions workflow runs on the GA `macos-26` Apple Silicon image,
builds and tests the app, drives the real `.app` with XCUIAutomation, and
uploads the built app, `.xcresult`, and PNG screenshot gallery.

