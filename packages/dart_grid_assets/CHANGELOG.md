# Changelog

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
