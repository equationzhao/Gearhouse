# Architecture

Gearhouse is a single-device SwiftUI app. It stores equipment, activities, installation history, maintenance, and reminder rules locally. Its only activity backend is Intervals.icu.

## Modules

| Location | Responsibility |
| --- | --- |
| `GearhouseApp/Application` | App lifecycle, navigation, editor routing, background refresh registration |
| `GearhouseApp/Features` | Equipment, activities, reminders, sync, backup, and media screens |
| `GearhouseApp/Services` | State storage, Keychain, notification delivery, iCloud Drive backup |
| `GearhouseApp/Support/SelfTests` | Debug-only isolated integration checks |
| `Sources/GearhouseCore/Domain` | JavaScriptCore bridge, generic values, user-facing errors, inventory and reminder calculations |
| `Sources/GearhouseCore/Equipment` | Tree indexes, drag planning, and timeline construction |
| `Sources/GearhouseCore/Activities` | Date-range activity summaries |
| `Sources/GearhouseCore/Backup` | Backup validation, checksums, and version packaging |
| `Sources/GearhouseCore/Media` | Attachment validation |
| `Sources/GearhouseCore/Intervals` | API models, HTTP client, and the earlier typed-state repository used by compatibility tests |
| `SharedRules/lib` | Equipment, history, inventory, sync merging, and recalculation rules |
| `SharedRules/public` | Pure snapshot and activity-history functions retained from the earlier UI |

`NativeStore` coordinates screens, persistence, Intervals.icu requests, and refreshes. `NativeDomain` runs the bundled rules inside JavaScriptCore. The Xcode app compiles the same core Swift files that Swift Package Manager tests; it does not build a second implementation.

## Data flow

```text
SwiftUI action → NativeStore → NativeDomain → validated next state
                                ↓                     ↓
                           SharedRules            local JSON
                                                      ↓
                                       refreshed indexes and screens
```

Activities retain equipment snapshots. Changing a tree or category does not silently rewrite earlier activity membership or distance policy. Explicit recalculation previews changes before applying them. Installation records use calendar dates.

Initial gear import reads Intervals.icu equipment and components. Subsequent tree and inventory changes remain local. Activity main Gear changes are written to Intervals.icu and read back; assembly relationships are not sent.

## Storage and services

- `Gearhouse/state-v2.json`: current state, with compatibility handling for the earlier `state.json` format.
- Media files: local photos and attachments referenced by state.
- Keychain: Intervals.icu API Key, outside state and backups.
- Recovery versions: complete state and media packages validated before restoring.
- iCloud Drive: user-authorized folder access via a security-scoped bookmark, rather than an app-specific CloudKit container.
- Notifications: local date schedules and usage checks after sync or state changes.

The background refresh identifier derives from the configured Bundle ID. Customizing signing does not require editing Swift code. Existing backup document type identifiers remain stable for file compatibility.

## Generated resources

`SharedRules` is the editable source. `scripts/bundle-rules.py` generates the JavaScript resource and checksums for all bundled modules. `scripts/generate-project.py` generates the Xcode project and shared scheme from the source tree. Generated files are committed so contributors can open the project immediately; CI checks that they match the source.
