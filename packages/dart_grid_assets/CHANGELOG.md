# Changelog

## 0.2.1-dev.1

- fix(release): honor declared git package paths in release overrides (#308)
- feat(release): report each package's ladder rung and staleness (#299)
- test(release): pin first-release rung consistency (#300)
- feat(release): auto-demote stale release candidates to beta (#297)
- feat(dart): add asymmetric verification commands (#293)

## 0.2.0

- PROMOTED from 0.2.0-dev.1. This is the stable release of the 0.2.0 line; the code is the
  candidate's, unchanged. Every family dependency constraint is rewritten from its prerelease
  form to the stable one, because pub refuses a stable package that depends on a prerelease.
- Consumers on a `^0.2.0-rc.N` constraint resolve this automatically: a caret range admits the
  release above its own prereleases, so no downstream pubspec edit is required to pick it up.

## 0.2.0-dev.1

- Changed (BREAKING): `ReleaseChange` carries the SEMVER MOVE alone — `docs`, `additive`, `fix`, `breaking`. Its `rc` value and its `isPreRelease` getter are gone, and `isBreaking` is now true for `breaking` alone. The prerelease rung was never a semver move: binding `rc` to `breaking` made a 0.x package doing breaking work reach for the candidate rung by construction, every single time (the measured drift: `grid_sdk` 22 prereleases and still stable at 0.2.0, `grid_assets` 25 and still 0.4.0, against `genesis_tree`'s ten releases and zero prereleases).
- Added: `ReleaseRung` — the PRERELEASE RUNG axis, carried per PACKAGE: `stable`, `dev`, `beta`, `rc`, with `parse` (fail-closed, null for null/unknown), `defaultPrerelease` (`dev`), `identifier`, `isPrerelease`, `requiresPromotionIntent` and a `compareTo`/`order` fixed as `dev < beta < rc < stable`. `dev` is where any prerelease starts; `beta` means the API is frozen for this target version; `rc` means a human has DECLARED intent to promote, and is the only rung a human must set.
- Changed (BREAKING): `ReleaseService.planVersion` takes a required `rung` plus `promotionIntent`, and `ReleaseVersionPlan` carries both (also in `toJson`). A prerelease off a stable version applies the move and appends `<rung>.1` (`0.1.4` + breaking + beta -> `0.2.0-beta.1`); off a prerelease the target core is fixed, so the counter increments only when the identifier is unchanged and restarts at 1 on every rung change in either direction (`0.2.0-dev.3` + beta -> `0.2.0-beta.1`; a demoted `0.2.0-rc.9` + beta -> `0.2.0-beta.1`). An `rc` plan with no declared `promotionIntent` is a loud refusal, as is a prerelease current on no supported rung.
- Changed (BREAKING): `ReleaseService.publishWorkspace` takes an optional `rung` and a `promotionIntent`; `ReleaseWavePackage` carries a required `rung` and `ReleaseWavePlan` a `promotionIntent` (both serialized). Omitting `rung` INFERS each changed member's rung from its authored version, so a mixed `dev`/`beta` wave is ordinary; supplying one requires every changed member to already sit there. A breaking member authored as a STABLE version is refused at the plan stage and directed to `--change breaking --rung dev`; breaking `dev` and `beta` members publish with no human in the loop; an `rc` member is refused before any tag, push or poll without declared intent. The direct consumer gate now follows the PLANNED wave (does it carry a stable member?) instead of the declared change class, and its failure remedy names `--change breaking --rung dev`.
- Changed: `dart release plan` and `dart release publish` grow `--rung <stable|dev|beta|rc>` and `--promotion-intent`. `plan` defaults to `stable`; `publish` infers per package when `--rung` is omitted, and its `--consumers` requirement moved into the service's stable-member gate (an inferred all-prerelease or mixed-rung wave is no longer rejected from `--change` alone). `--change rc` survives as the COMPATIBILITY SPELLING of `--change breaking --rung rc` — it emits `change: breaking` with `rung: rc`, agrees with an explicit `--rung rc`, refuses a conflicting explicit rung as usage, and still requires `--promotion-intent`.
- Changed: breaking classification names the DEV-FIRST target. `ReleaseService.classifyRelease`'s understated verdict now reads `declared 0.3.2 is a patch, a breaking change requires 0.4.0-dev.1`; the required version still comes from the existing `planVersion` and the `dart-apitool` process seam is untouched.
- Added: `ReleaseService.discoverWorkspace` and `dart release discover --workspace <dir> --diff <ref>` — the read-only workspace preflight, answered by melos instead of by hand. It runs `melos list --no-published` and `melos list --diff=<ref>` through the existing `ProcessRunner` seam and returns `{workspaceRoot, diff, candidates, changed}`, retiring the per-package pub.dev curl and the per-package `git log <ref>..HEAD -- packages/<pkg>` sweep. It is a preflight, not a gate: `publishWorkspace` still resolves every published predecessor against pub.dev immediately before it tags.
- Added: `ReleaseDiscovery` — the structured discovery result (`workspaceRoot`, `diff`, sorted `candidates`, sorted `changed`).
- Added: `ReleaseService.publishOrderFromMelosWorkspace` and `dart release order --workspace <dir>` — publish order read off melos's own adjacency graph (`melos list --json --graph`), so the graph that decides publish order is no longer transcribed into a hand-written manifest. Melos emits `dev_dependencies` and `dependency_overrides` edges too, and publish order is a statement about the published RUNTIME contract only, so every emitted edge is filtered against the source package's top-level `dependencies` before ordering: lenny's `leonard_agent`/`leonard_flutter`/`leonard_flutter_test` dev cycle is not a publish cycle, and the raw graph would refuse a releasable workspace. A runtime cycle still hits `publishOrder`'s existing loud refusal.
- Changed: `dart release order` now requires EXACTLY ONE of `--workspace` and `--manifest` (neither is mandatory alone), refusing both-or-neither with exit 64 before any file or process work. `--manifest` keeps its decoder and its output byte-for-byte.
- Added: `ReleaseService.classifyRelease` — the SEMVER verdict nothing in the chain carried. It diffs the package's public API at HEAD against the API of its LAST PUBLISHED version (the greatest version pub.dev lists, prereleases included — never a checked-in golden, which moves with the diff) and pairs that delta with the version bump the pubspec declares, so a breaking change mis-declared as a patch stops passing every gate. The API extraction is not owned here: the delta comes from the external `dart-apitool` CLI, shelled out through the same `ProcessRunner` seam `dart pub publish` rides, so `dart_apitool` is not a dependency of this package. When the tool cannot be launched the op REFUSES with the activation command in its message — it never returns a passing verdict it did not analyze.
- Added: `ReleaseClassification`, `ReleaseRequiredChange`, `ReleaseDeclaredChange` and `ReleaseClassificationVerdict` — the structured verdict (`package`, `baseline`, `head`, `removed`, `changed`, `added`, `requiredChange`, `declaredChange`, `verdict`, `message`). The message names the SYMBOL and the CONSEQUENCE, e.g. `exported captureScreenshot lost parameter binding, so existing calls that supply binding no longer compile; declared 0.3.2 is a patch, a breaking change requires 0.4.0-dev.1`; the required version is computed by the existing `planVersion`, so classification never invents version math.
- Added: `dart release classify` — the thin Command over the classification (`--dir`, `--package`, `--json`), exiting 0 for `ok`, 1 for `understated`, and 1 with no verdict on stdout when the baseline or the analyzer is unavailable.
- Added: `ReleaseService.publishWorkspace` — the one-command workspace release wave. It computes the changed-package set against pub.dev (reusing `poll`, and resolving each package's published predecessor through the existing `planVersion`), runs the existing scrub, publish-order and dry-run gates, validates every consumer against the origin-reachable release commit for a wave carrying a stable package, then cuts and pushes one `<package>-v<version>` tag per package in dependency order, polling pub.dev between them. The tag push is the publish, so the wave never runs `dart pub publish` for real; a breaking STABLE member is refused before any work, and promotion stays the separate `validate-consumers` then `promote` path.
- Added: `ReleaseWavePlan`, `ReleaseWavePackage`, `ReleaseWaveStage` and `ReleaseWaveFailure` — the structured plan and the "which stage, which package" stop the release skill parses; plus the `ReleaseWait` seam, so a wave's propagation waits are injectable.
- Added: `dart release publish` — the thin Command over the wave (`--workspace`, `--change`, `--rung`, `--promotion-intent`, `--consumers`, `--dry-run`, `--json`), and `bin/dart_grid_assets.dart`, so a workspace root can reach the vended `dart` Command as `dart run dart_grid_assets:dart_grid_assets`.
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
