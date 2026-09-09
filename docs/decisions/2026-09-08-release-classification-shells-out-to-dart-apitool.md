---
status: accepted
date: 2026-09-08
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: release-classification-shells-out-to-dart-apitool
  surfaces:
    - "packages/dart_grid_assets/lib/src/dart/release_service.dart"
    - "packages/dart_grid_assets/lib/src/dart/release_command.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-dd6.1
  legacy-id: null
---
# Release classification shells out to `dart-apitool` through the process seam

## Context and Problem Statement

Nothing in the release chain CLASSIFIES a change. `release plan` takes the
change class as an INPUT and only does the version arithmetic; `release scrub`
checks declared floors; `release dry-run` checks packaging. A breaking change
mis-declared as a patch therefore passes every gate and publishes.

This is not hypothetical. On 2026-09-08 `leonard_flutter` 0.3.2 was planned,
gated and staged as a PATCH. It removed the required `RendererBinding`
parameter from `captureScreenshot`, which the package barrel exports, so every
external `captureScreenshot(binding)` call would have failed to compile on a
caret-compatible upgrade. It was caught only because a human asked "all
patches?" and the public barrel was hand-diffed against the last release tag.

Commit-message-driven tooling cannot catch this class: the change carried no
`!` and no `BREAKING CHANGE` footer, so Conventional Commits — and therefore
`melos version` — would also have cut a patch. The missing fact is not "a
symbol changed" (the git diff already says that) but the PAIRING of two facts
no single diff holds: the API delta since what consumers actually resolve, and
the version bump being declared.

Three ways to get the delta were on the table.

## Decision Outcome

`ReleaseService.classifyRelease` obtains the public-API delta by SHELLING OUT
to the `dart-apitool` CLI — an external tool whose stated purpose is to diff a
package against another version to check semver — through the same
`ProcessRunner` seam `release_service.dart` already owns for
`dart pub publish`.

1. **`dart_apitool` is NOT a dependency of `dart_grid_assets`.** It is an
   external executable the gate calls. It appears in neither `dependencies` nor
   `dev_dependencies`, and a test asserts that. Replacing the tool later is a
   change at one seam.
2. **Rejected: taking `package:dart_apitool` as a library dependency.** That
   puts a thinly-adopted package into the dependency graph of the org's release
   gate.
3. **Rejected: in-house analyzer extraction.** The semver rules are subtle —
   generics, optional parameters, sealed types, re-exports — and owning them
   wrong makes the gate lie in the safe-looking direction.
4. **The baseline is the LAST PUBLISHED release, never a checked-in golden.**
   A golden moves with the diff and can only tell you a symbol changed. The
   baseline is the greatest version pub.dev lists (a prerelease counts — it is
   what an rc consumer resolves), read through the existing `poll` on the one
   `HttpGetter` seam.
5. **A missing analyzer is a LOUD refusal, never a passing verdict.** The tool
   must be activated to run; a launch failure, exit 127, a non-zero exit, a
   missing report and a malformed report all throw, and the launch-shaped ones
   carry `dart pub global activate dart_apitool` in the message. A gate that
   silently passes when its analyzer is missing is worse than no gate.
6. **The failure message names the SYMBOL and the CONSEQUENCE.** "A thing
   changed" is not worth a gate (Nico, 2026-09-08: *"Do you really need a test
   to tell you that you changed a static? Isn't the diff that tells you that
   you changed something"*). The `leonard_flutter` case reads: `exported
   captureScreenshot lost parameter binding, so existing calls that supply
   binding no longer compile; declared 0.3.2 is a patch, a breaking change
   requires 0.4.0-rc.1`.
7. **The required version comes from the existing `planVersion(..., rc)`**, so
   classification never invents version math and the remedy it names stays on
   `power_station#adr-0003-private-git-tag-releases-and-prerelease-gate` D3's
   rc-first lane. The verdict compares CORE versions only: it judges bump SIZE,
   not whether the rc ritual was followed.

### Consequences

- **Benefit.** The `leonard_flutter` 0.3.2 shape is caught by a gate rather
  than by a human asking the right question.
- **Cost — an activation step.** Any environment that runs the gate must have
  `dart-apitool` activated. That cost is deliberate: the alternative is a gate
  that passes when it cannot see.
- **Cost — a wire contract with an external tool.** The JSON report shape
  (`report.breakingChanges` / `report.nonBreakingChanges` trees, the `changeCode`
  vocabulary) is parsed here. An unfamiliar change code lands in `changed`
  rather than being discarded, so a tool that grows a code stays visible; a leaf
  missing `changeCode`, `isBreaking` or `changeDescription` is a refusal.
- **Deferred.** Wiring the verdict into the release SKILL as a mandatory gate,
  and into the two-wave publish flow, is follow-up work once the verdict shape
  is proven. `release classify` is an op, not yet a gate.
