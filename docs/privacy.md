# Privacy and data

Gearhouse stores equipment, installation history, activities, notes, maintenance, reminder rules, photos, and attachments in the app's local storage. It has no account service of its own and includes no third-party analytics SDK.

When you connect Intervals.icu, requests go directly from the device to its API. The API Key is stored in Keychain. Activity main Gear edits are sent to Intervals.icu; the local equipment tree and maintenance records are not uploaded there.

Automatic iCloud Drive backup is optional. It writes complete data and media packages into the folder you select. Device access and iCloud file availability depend on your Apple account and system settings. This is versioned backup, not multi-device conflict resolution.

Exported JSON and backup packages are not encrypted by Gearhouse. They may contain activity times, account identifiers, equipment history, notes, and personal media. Share them only with people you intend to give that information to. The API Key is excluded from Gearhouse exports and backups.

Imported photos are re-encoded as JPEGs. Attachments such as invoices and PDFs are retained as files and can contain their own metadata or personal information.

Reminders use Apple's local notifications. Permission is requested when needed, and can be changed in iOS Settings.

When reporting a bug, use synthetic examples or remove private information from logs and screenshots. Never include an API Key, an unredacted backup, or a device signing credential in a public issue.
