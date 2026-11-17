# AGENTS.md

macOS menu bar app (Swift 6, SwiftPM, no Xcode project) that notifies SMN (Argentina) weather alerts for the user's cities.

## Commands

```sh
swift test                         # all logic tests; offline (network and disk are faked)
./build-app.sh 1.0.0 --dev         # dev app in build/, with demo states and --snapshots
"build/Truenito.app/Contents/MacOS/Truenito" --snapshots /tmp/caps   # PNG of every panel state, light and dark
./smoke-test.sh                    # launches the built app and checks it reaches the SMN
```

Run `swift test` after any change to `Sources/SMNCore`. After a UI change, build with `--dev`, take snapshots and look at them.

## Layout

- `Sources/SMNCore`: everything that can be tested without UI. CAP parsing, polygon matching, notice rules (`Notices.swift`), forecast risk windows, `AlertMonitor` (the polling loop). HTTP, disk and clock are injected.
- `Sources/Truenito`: AppKit + SwiftUI app. `AppModel` is the single source of truth; views only read it.
- `Tests/SMNCoreTests`: Swift Testing. `Fixtures/` holds real SMN CAP files.

## Rules

- **Low resource use is a feature.** The app runs all day: no timers faster than needed, no work while the panel is closed, cache formatters, never poll the SMN more than every 5 min. The SMN allows 180 XML downloads per 10 min per IP; keep `maxDownloadsPerCheck` under that.
- **An alert must never be lost because of something else.** Weather and forecast failures are swallowed; only the SMN feed can fail a check.
- No new dependencies. Sparkle (updates) is the only one.
- Swift 6 strict concurrency; UI code is `@MainActor`.
- UI text is Argentine Spanish (voseo: "elegí", "tocá"). Code, comments and commit messages are English.
- Comments say why, not what.
- New logic in `SMNCore` gets a test.
- Development builds (`DEV_TOOLS`) must not ship: no updater, no move-to-Applications prompt.

## Releasing

`./build-app.sh X.Y.Z` (no `--dev`) signs the zip and writes `build/appcast.xml` with the EdDSA key in the maintainer's Keychain. Only the maintainer can publish releases.
