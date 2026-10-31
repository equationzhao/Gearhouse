# Architecture

Gearhouse is a single-device SwiftUI app. It stores equipment, activities, installation history, maintenance, and reminder rules locally. Its only activity backend is Intervals.icu.

## Modules

| Location | Responsibility |
| --- | --- |
| `GearhouseApp/Application` | App lifecycle, navigation, editor routing, background refresh registration |
| `GearhouseApp/DesignSystem` | Shared color surfaces, metrics, equipment cards, and downsampled image loading |
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

Activities retain equipment snapshots. Changing a tree or category does not silently rewrite earlier activity membership or distance policy. Explicit recalculation previews changes before applying them. Date-only installation records retain their calendar-day semantics. Precise records carry both their Shanghai wall time and a validated UTC instant; activities with a reliable UTC start can be matched at that instant, including a repeated DST hour. If an activity lacks a reliable instant near a precise change, its component membership is left unresolved and recomputation skips it until the time is available.

Initial gear import reads Intervals.icu equipment and components. Subsequent tree and inventory changes remain local. Activity main Gear changes are written to Intervals.icu and read back; assembly relationships are not sent.

Activity edits are field patches: main equipment, cycling shoes, and trainer have independent override intent. Missing patch fields preserve current values, including changes received while a form was open. Explicit null clears a selection. Legacy whole-activity manual assignments retain their main override and frozen assembly until explicitly released; a shoe-only override does not freeze unrelated assembly recalculation. Snapshot changes replace only the affected equipment branches.

Main equipment uploads retain the remote value observed when editing began, separately from the latest remote value. Reads can reveal a conflict without rebasing the pending write. Choosing the local value rereads the activity and requires another choice if it changed again. Confirmed target values close a pending write, including recovery after a lost write response. Local persistence completes before any upload, so network failures do not leave saved fields marked as drafts.

Every sync refreshes the remote equipment catalog; one-time local equipment, assembly, and usage-baseline import remains separate. Refresh failures retain the previous catalog. Linking a previously unknown remote main equipment resolves matching activities while preserving local shoes and trainer choices. Removed catalog entries retain existing local links and remain editable.

Photo imports load and prepare one image at a time, then commit the selected batch in one transaction. Failure or cancellation removes only that batch's new files. Attachment selections save one file at a time. Both retain the restoration generation captured when the selection began, so an old operation cannot append media after a backup replaces the library. Cancelled file workers finish before cleanup; event drafts receive photo IDs only after a successful batch.

Manual and automatic sync share one registered task. Callers that await sync keep its lifetime through completion or cancellation; cancellation preserves previously committed activity batches and does not advance the failure backoff. A remote equipment refresh temporarily prevents starting another sync.

## Storage and services

- `Gearhouse/state-v2.json`: current state, with compatibility handling for the earlier `state.json` format.
- Media files: local photos and attachments referenced by state.
- Keychain: Intervals.icu API Key, outside state and backups.
- Recovery versions: complete state and media packages validated before restoring.
- iCloud Drive: user-authorized folder access via a security-scoped bookmark, rather than an app-specific CloudKit container.
- Notifications: local date schedules and usage checks after sync or state changes.

The library becomes available only after loading, validation, and persistence succeed. A failed read blocks ordinary writes, sync, exports, automatic backup publication, pruning, and notification reconciliation. Recovery can still read backup versions. Before replacing an unreadable library, it preserves and verifies the original file bytes; failure to preserve them aborts replacement. Recovery from this state persists a reconnection requirement, so an existing Keychain credential cannot resume requests until an explicit connection verifies the restored account.

Only the original Swift Codable format can omit installation history. Before migration, storage validates its known top-level and record fields, types, and ISO dates, then preserves its exact source bytes. These original files are separate from restorable version packages, whose format requires installation history. A modern library missing installation history is rejected before normalization can discard its other records.

The background refresh identifier derives from the configured Bundle ID. Customizing signing does not require editing Swift code. Existing backup document type identifiers remain stable for file compatibility.

## Generated resources

`SharedRules` is the editable source. `scripts/bundle-rules.py` generates the JavaScript resource and checksums for all bundled modules. `scripts/generate-project.py` generates the Xcode project and shared scheme from the source tree. Generated files are committed so contributors can open the project immediately; CI checks that they match the source.
