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

Use the iOS Simulator for UI development and verification. Use an isolated synthetic preview library; do not use a physical device or real user data unless explicitly requested. Equipment and drag UI tests launch with `-preview-route tree`. The preview library is stored separately and does not load the saved Intervals.icu key.

Every UI change requires visual review before completion:

1. Run the affected screens in the simulator and inspect screenshots of the actual rendered interface.
2. Check the relevant light and dark appearances, images and missing images, large text, and key interactions. Include expanded trees, selection, and dragging when affected.
3. Fix visible hierarchy, spacing, clipping, contrast, and interaction problems, then inspect the updated screens again.
4. Record the screens and states reviewed, and keep local screenshots available for review.

A successful build or automated test run does not count as visual acceptance.

```sh
xcodebuild -project GearhouseApp.xcodeproj -scheme GearhouseApp \
  -destination 'platform=iOS Simulator,name=YOUR_SIMULATOR_NAME' \
  -only-testing:GearhouseUITests/GearEquipmentUITests test
```

Replace the simulator name with one listed by `xcrun simctl list devices available`. A simulator needs normal local signing to exercise Keychain; do not disable signing for a UI test run.

`GearBackupUITests` additionally requires choosing an iCloud Drive test folder through the system picker. Run it explicitly; it is not part of unattended CI.

The Debug self-tests (`-native-self-test`, `-backup-self-test`, `-reminder-self-test`, `-keychain-self-test`) use isolated data or dedicated credentials. `-cloud-backup-self-test` uses an explicitly selected preview folder. Reports are local development artifacts and must not be submitted as user data.

## Fixtures and compatibility

The committed preview fixture is synthetic and contains no connected account. `node scripts/make-preview.mjs` regenerates it; generated IDs and timestamps can change. Tests must use synthetic fixtures or explicitly supplied local files. Optional migration comparisons use `GEARHOUSE_MIGRATION_SOURCE`, or the pair `GEARHOUSE_PARITY_SOURCE` / `GEARHOUSE_PARITY_EXPECTED`, and skip when those files are absent.

`scripts/export-web-backup.py` converts an explicitly selected legacy local database to an import file. It does not need the old web source or server. Treat its output as private data.

## 图标、数据迁移与通知排程

图标源文件为 `GearhouseApp/GearhouseIcon.icon`，可用 Xcode 附带的 Icon Composer 打开。1024 × 1024 的链节 G 主体与链轴细节使用独立 SVG 图层；默认外观为暖白底、蓝色 G，深色外观为深蓝底、银白 G。Mono 使用白色主体与灰色链轴，由系统应用透明和着色外观。玻璃效果保留轮廓高光，关闭额外投影。

项目资源阶段编译 `.icon` 文件，主图标名设为 `GearhouseIcon`。系统负责圆角遮罩和各场景尺寸，修改图层后重新构建。个人开发团队和 Bundle ID 可在 `Config/Local.xcconfig` 中设置。

原生原型数据迁移到 `state-v2.json`；旧 `state.json` 保留。固定日期重复通知预排后续 12 轮，系统待发请求总数控制在 60 条以内，应用运行时补充；不能据此承诺长期关闭应用仍会持续补排。
