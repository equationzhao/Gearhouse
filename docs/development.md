# Development

## Toolchain

- macOS with Xcode. Local verification uses Xcode 27.1; the `.icon` asset needs Xcode 26 or later.
- Python 3 using only the standard library.
- Swift Package Manager, supplied with Xcode.
- Node.js only for `scripts/make-preview.mjs` (synthetic fixture generation).

Select Xcode in **Xcode → Settings → Locations → Command Line Tools** before building. Core tests require macOS because the rules engine uses Apple's JavaScriptCore framework.

## Generate and test

Run from the repository root:

```sh
python3 scripts/bundle-rules.py
python3 scripts/generate-project.py
python3 scripts/check-repository.py
swift test
```

After changing rules, regenerate the bundle. After adding, moving, or removing Swift files, regenerate the Xcode project. Both generators support `--check` and do not read private signing settings.

Build for a simulator:

```sh
xcodebuild -project GearhouseApp.xcodeproj -scheme GearhouseApp \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/xcode build
```

CI also compiles a Release iPhoneOS build with signing disabled. Unsigned builds verify compilation; they cannot be installed on an iPhone.

## Personal signing

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
open GearhouseApp.xcodeproj
```

Fill in `DEVELOPMENT_TEAM` and `GEARHOUSE_BUNDLE_IDENTIFIER` in the local file. App and UI test targets inherit the same configuration. Keep your existing Bundle ID and signing team when updating an installed app whose local data you want to retain.

Do not put an API Key in source code or configuration files. Enter it inside the app.

## UI verification

Equipment and drag UI tests launch with `-preview-route tree`. The preview library is stored separately, uses synthetic activity data, and does not load the saved Intervals.icu key.

```sh
xcodebuild -project GearhouseApp.xcodeproj -scheme GearhouseApp \
  -destination 'platform=iOS Simulator,name=YOUR_SIMULATOR_NAME' \
  -only-testing:GearhouseUITests/GearEquipmentUITests test
```

Replace the simulator name with one listed by `xcrun simctl list devices available`. To use an unlocked, paired iPhone, use `-destination 'platform=iOS,id=YOUR_DEVICE_ID'` instead. A simulator needs normal local signing to exercise Keychain; do not disable signing for a UI test run.

`GearBackupUITests` additionally requires choosing an iCloud Drive test folder through the system picker. Run it explicitly; it is not part of unattended CI.

The Debug self-tests (`-native-self-test`, `-backup-self-test`, `-reminder-self-test`, `-keychain-self-test`) use isolated data or dedicated credentials. `-cloud-backup-self-test` uses an explicitly selected preview folder. Reports are local development artifacts and must not be submitted as user data.

## Fixtures and compatibility

The committed preview fixture is synthetic and contains no connected account. `node scripts/make-preview.mjs` regenerates it; generated IDs and timestamps can change. Tests must use synthetic fixtures or explicitly supplied local files. Optional migration comparisons use `GEARHOUSE_MIGRATION_SOURCE`, or the pair `GEARHOUSE_PARITY_SOURCE` / `GEARHOUSE_PARITY_EXPECTED`, and skip when those files are absent.

`scripts/export-web-backup.py` converts an explicitly selected legacy local database to an import file. It does not need the old web source or server. Treat its output as private data.
