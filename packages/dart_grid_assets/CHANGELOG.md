# Changelog

## Unreleased

- Added: `ReleaseService.discoverWorkspace` and `dart release discover --workspace <dir> --diff <ref>` — the read-only workspace preflight, answered by melos instead of by hand. It runs `melos list --no-published` and `melos list --diff=<ref>` through the existing `ProcessRunner` seam and returns `{workspaceRoot, diff, candidates, changed}`, retiring the per-package pub.dev curl and the per-package `git log <ref>..HEAD -- packages/<pkg>` sweep. It is a preflight, not a gate: `publishWorkspace` still resolves every published predecessor against pub.dev immediately before it tags.
- Added: `ReleaseDiscovery` — the structured discovery result (`workspaceRoot`, `diff`, sorted `candidates`, sorted `changed`).
- Added: `ReleaseService.publishOrderFromMelosWorkspace` and `dart release order --workspace <dir>` — publish order read off melos's own adjacency graph (`melos list --json --graph`), so the graph that decides publish order is no longer transcribed into a hand-written manifest. Melos emits `dev_dependencies` and `dependency_overrides` edges too, and publish order is a statement about the published RUNTIME contract only, so every emitted edge is filtered against the source package's top-level `dependencies` before ordering: lenny's `leonard_agent`/`leonard_flutter`/`leonard_flutter_test` dev cycle is not a publish cycle, and the raw graph would refuse a releasable workspace. A runtime cycle still hits `publishOrder`'s existing loud refusal.
- Changed: `dart release order` now requires EXACTLY ONE of `--workspace` and `--manifest` (neither is mandatory alone), refusing both-or-neither with exit 64 before any file or process work. `--manifest` keeps its decoder and its output byte-for-byte.
- Added: `ReleaseService.classifyRelease` — the SEMVER verdict nothing in the chain carried. It diffs the package's public API at HEAD against the API of its LAST PUBLISHED version (the greatest version pub.dev lists, prereleases included — never a checked-in golden, which moves with the diff) and pairs that delta with the version bump the pubspec declares, so a breaking change mis-declared as a patch stops passing every gate. The API extraction is not owned here: the delta comes from the external `dart-apitool` CLI, shelled out through the same `ProcessRunner` seam `dart pub publish` rides, so `dart_apitool` is not a dependency of this package. When the tool cannot be launched the op REFUSES with the activation command in its message — it never returns a passing verdict it did not analyze.
- Added: `ReleaseClassification`, `ReleaseRequiredChange`, `ReleaseDeclaredChange` and `ReleaseClassificationVerdict` — the structured verdict (`package`, `baseline`, `head`, `removed`, `changed`, `added`, `requiredChange`, `declaredChange`, `verdict`, `message`). The message names the SYMBOL and the CONSEQUENCE, e.g. `exported captureScreenshot lost parameter binding, so existing calls that supply binding no longer compile; declared 0.3.2 is a patch, a breaking change requires 0.4.0-rc.1`; the required version is computed by the existing `planVersion`, so classification never invents version math.
- Added: `dart release classify` — the thin Command over the classification (`--dir`, `--package`, `--json`), exiting 0 for `ok`, 1 for `understated`, and 1 with no verdict on stdout when the baseline or the analyzer is unavailable.
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
