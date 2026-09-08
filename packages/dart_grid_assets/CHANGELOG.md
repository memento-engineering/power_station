# Changelog

## Unreleased

- Added: `ReleaseService.publishWorkspace` — the one-command workspace release wave. It computes the changed-package set against pub.dev (reusing `poll`, and resolving each package's published predecessor through the existing `planVersion`), runs the existing scrub, publish-order and dry-run gates, validates every consumer against the origin-reachable release commit for a docs/additive/fix wave, then cuts and pushes one `<package>-v<version>` tag per package in dependency order, polling pub.dev between them. The tag push is the publish, so the wave never runs `dart pub publish` for real; a `breaking` wave is refused before any work, and promotion stays the separate `validate-consumers` then `promote` path.
- Added: `ReleaseWavePlan`, `ReleaseWavePackage`, `ReleaseWaveStage` and `ReleaseWaveFailure` — the structured plan and the "which stage, which package" stop the release skill parses; plus the `ReleaseWait` seam, so a wave's propagation waits are injectable.
- Added: `dart release publish` — the thin Command over the wave (`--workspace`, `--change`, `--consumers`, `--dry-run`, `--json`), and `bin/dart_grid_assets.dart`, so a workspace root can reach the vended `dart` Command as `dart run dart_grid_assets:dart_grid_assets`.
- Changed: `PollResult` now carries the pub.dev `statusCode` and the complete `versions` list (both additive in `toJson`), so a caller can tell "not published yet" from "the API did not answer" without a second parser.

## 0.1.3

- Added: `ReleaseService.validateDeclaredFloors` — the release scrub gate now also resolves the candidate in a throwaway copy with every workspace sibling pinned to the EXACT floor the candidate declares (`pubspecOverridesForExactVersions`) and runs `dart analyze` there, so a member used above its declared floor cannot ship green the way `grid_engine 0.3.0-rc.15` did (the_grid tg-klfj); `release scrub --json` gains `declaredFloors` (pow-dqet, #219).
- Changed: `release scrub` now exits 1 when the content scan finds hits (it exited 0 and only printed before); the JSON `clean` field is unchanged. The declared-floors leg resolves against pub.dev, so the scrub gate is online by design; the pub.dev integration test is tagged `integration` and excluded from `dart test -x integration`.

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
