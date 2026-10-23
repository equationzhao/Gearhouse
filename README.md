# Gearhouse

[简体中文](README.zh-CN.md)

An iPhone app for tracking cycling equipment, component wear, and maintenance. Sync activities directly with [Intervals.icu](https://intervals.icu/), without running your own server.

## Features

- Build an equipment tree: bike → wheelset → tyre, rotor, or cassette.
- Track installation dates when components move between bikes, and preview usage recalculations.
- Keep spare parts in inventory. Group identical items by quantity while preserving each item's history.
- Decide which equipment categories include indoor and virtual riding distance.
- Record maintenance, crashes, drip waxing, and hot waxing; add usage or date reminders.
- View equipment activity history, date-range totals, and a component timeline.
- Attach photos, receipts, manuals, and warranty documents.
- Back up to an iCloud Drive folder and restore earlier versions.

Gearhouse currently uses Simplified Chinese in the app. Data is stored on one device; iCloud Drive provides backup and recovery, not live multi-device sync. iOS controls when background activity sync and backup can run.

## Build

You need a Mac with Xcode (the current project is verified with Xcode 27.1) and Python 3. The app targets iOS 17 or later. The Icon Composer `.icon` asset requires a recent Xcode; Xcode 26 or later is recommended. Node.js is only needed to regenerate the synthetic demo fixture.

```sh
python3 scripts/bundle-rules.py
python3 scripts/generate-project.py
swift test
open GearhouseApp.xcodeproj
```

For an iPhone, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, set your development team and a unique Bundle ID, then select your iPhone in Xcode and run `GearhouseApp`. The local file is ignored by Git. Device installation also requires Developer Mode and trust pairing.

In the app, open **同步 → Intervals.icu 连接** and enter your personal API Key from [Intervals.icu settings](https://intervals.icu/settings). Credentials stay in Keychain and are excluded from backups.

To explore synthetic equipment without connecting an account, add `-preview-route tree` to the scheme's launch arguments in a Debug build. This uses a separate preview library and an in-memory credential store.

## Source layout

```text
GearhouseApp/        SwiftUI application, features, and iOS services
Sources/            GearhouseCore Swift package
SharedRules/        Equipment and activity rules executed by JavaScriptCore
Tests/              Core unit and integration tests
UITests/            Isolated iPhone UI tests
Config/             Shared configuration and personal signing template
scripts/            Project generation, rules bundling, and repository checks
docs/               User guide, architecture, development, and privacy
```

The app does not require the archived web app or a Node.js runtime. The JavaScript rules and demo fixture are bundled with the app.

## Documentation

- [使用说明](docs/user-guide.zh-CN.md)
- [Development and testing](docs/development.md)
- [Architecture](docs/architecture.md)
- [Privacy and data](docs/privacy.md)
- [Contributing](CONTRIBUTING.md)
- [Security reports](SECURITY.md)

## License

[MIT](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md) for platform and asset information.

Gearhouse is an independent project and is not affiliated with Intervals.icu or the equipment brands shown in examples.
