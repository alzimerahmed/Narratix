# Narratix — Audiobook Player for iOS & watchOS

Narratix is an open-source audiobook player for iPhone, iPad, Apple Watch, and CarPlay.
It plays your own M4B/M4A/MP3 audiobooks — offline, in the background, and synced across devices.

Forked from [BookPlayer](https://github.com/TortugaPower/BookPlayer) (GPL-3.0).

## Features

- **Import** — AirDrop, Files, iTunes File Sharing, zip archives, share extension, or your own Jellyfin / AudiobookShelf server
- **Listen** — chapters, playback speed, smart rewind, volume boost, sleep timer, lock-screen & headset controls, VoiceOver, dark mode + themes
- **Manage** — folders & bound books, bookmarks with notes, drag & drop sorting, Hardcover reading-progress sync
- **Pro sync** — cloud library sync, standalone Apple Watch playback, additional themes and app icons

## Building

Requires **Xcode 27.1** (iOS 26 / watchOS 10 SDKs).

```bash
cp BuildConfiguration/Debug.template.xcconfig BuildConfiguration/Debug.xcconfig
# fill in the BP_* values, then:
xcodebuild -resolvePackageDependencies
open BookPlayer.xcodeproj
```

CI (`.github/workflows/ci.yml`) builds and runs `BookPlayerTests` on every push to `develop`/`main` and PR to `develop`.

## License

GPL-3.0 — see `LICENSE`. Copyright of upstream BookPlayer contributors is preserved per the license.
