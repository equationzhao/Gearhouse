# Contributing

Bug reports, focused fixes, translations, and improvements to equipment workflows are welcome. For a larger change, describe the use case in an issue before starting.

## Before submitting

1. Follow [development setup](docs/development.md).
2. Keep domain rules in `SharedRules` and core calculations in `Sources/GearhouseCore`; keep platform UI and services in `GearhouseApp`.
3. Regenerate affected resources and the Xcode project. Run `python3 scripts/check-repository.py` and `swift test`.
4. For interaction changes, verify the relevant screen with synthetic data and include a screenshot or concise reproduction steps. Use existing tests for the feature when adding regression coverage.

Explain the problem, the resulting behavior, and how you validated it in your pull request. Keep unrelated formatting and feature changes separate. Preserve historical activity snapshots unless the user explicitly chooses to recalculate them.

Use clear function names that describe actions. UI text should help the person complete their task: keep labels, necessary status, actionable errors, and destructive-operation confirmations; avoid explanatory clutter.

Do not submit personal backups, real activities, keys, signing settings, or device logs. Use the included demo fixture or create synthetic records.

By submitting a contribution, you agree to license it under the project's [MIT License](LICENSE). Include the original notices and compatible license for any third-party code or assets you add.
