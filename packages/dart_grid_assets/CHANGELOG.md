# Changelog

## 0.1.2

- Added: `DartFormatService` — the deterministic `dart format --output=none --set-exit-if-changed` probe the code-review circuit's `format-clean` gate composes; names the unformatted files (pow-jicn, #209).

## 0.1.1

- `release poll` detects published prerelease versions (#95).
- `release scrub` scopes internal-ref detection to working documents and
  narrows one scrub term that produced false positives (#86, #78).
- The overlay publisher reads assets from visible source directories (#82).
- Repo-wide `dart format` sweep (#73).
## 0.1.0

- Initial release: the Dart domain grid assets — the typed grid.dart envelope, pub dev-time linkage, and the exported DartCommand.
