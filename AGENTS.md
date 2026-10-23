# Project scope

This repository maintains the native iPhone app. All required source is included here; do not add a dependency on the archived web application.

# Structure and checks

- SwiftUI screens belong in `GearhouseApp/Features`; iOS adapters belong in `GearhouseApp/Services`.
- Shared Swift logic belongs in `Sources/GearhouseCore`; equipment and activity rules belong in `SharedRules`.
- Prefer verb + noun function names.
- Run the rules bundler after rule edits and the project generator after source-file moves. Generated files must pass `--check`.
- Use synthetic data for tests and UI checks. Do not commit backups, API Keys, personal signing, private logs, or device identifiers.
- Add regression coverage to an existing feature test file where practical.

# Reader-facing content

Write from the final reader's perspective. Describe the task, result, or actionable next step, not the implementation process. Use consistent names and remove redundant explanations. Keep necessary labels, operation status, actionable errors, permission requests, and destructive-operation confirmations. Do not add tutorial tooltips or permanent hints to compensate for unclear controls. Review documentation independently of the request before finalizing it.
