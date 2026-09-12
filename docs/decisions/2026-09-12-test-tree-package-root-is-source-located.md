---
status: accepted
date: 2026-09-12
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: test-tree-package-root-is-source-located
  surfaces:
    - "packages/grid_assets/lib/src/search/search_recall.dart"
    - "packages/grid_assets/test/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-15jv
  legacy-id: null
---

# The test tree's one package-root anchor is the helper's own source location

## Context and Problem Statement

`Directory.current` is process-global and `dart test` runs test files in
concurrent isolates of ONE process. Three suites in this pack assigned it while
twelve read package-local source through a path relative to it, so a read that
landed inside another file's working-directory window threw
`PathNotFoundException` or resolved a different tree. The outcome depended on
isolate scheduling rather than on anything in the diff, so it never reproduced
in isolation and rarely on a quiet machine — it surfaced as two separate critic
rounds on one clean branch, once as a test exiting 1 with an empty error sink
and once as a `PathNotFoundException` reading `lib/src/code/respec.dart` while a
sibling suite held the working directory at a temp dir.

`power_station#a24-bead-pow-a74-the-operator-install-leg-discovers-its-over`
already recorded the mechanism — "`Directory.current` is process-global and
`dart test` runs suites concurrently, so the sibling suite that chdirs to a
foreign dir to PROVE cwd-independent resolution (`track_d_assets_test`) raced
any walk done from inside another suite's test body" — and fixed it for the
asset suites by routing them through `PackagedAssetLoader.root`. That left the
three writers in place, so the hazard returned as soon as new relative readers
landed.

## Decision

`packages/grid_assets/test/support/package_root.dart` exports one
`packageRoot()`; every package-local path in the suite is
`p.join(packageRoot(), …)`, and no test file reads or assigns the process
working directory. The calls made autonomously around that:

**(1) The anchor is this helper's own source location**, read off the top frame
of a stack trace captured inside it, then walked up to the `pubspec.yaml` naming
`grid_assets`. NOT `Platform.script`: under `dart test` that resolves to a
throwaway kernel dill in the system temp dir
(`file:///tmp/dart_test.kernel.*/test.dart_1.dill`, measured in this tree), not
to a file in this package, so a walk from it can never reach the package root.
It IS `Platform.script` inside the sibling probe executable, which is why the
helper's refusal names it. And NOT `PackagedAssetLoader.root`, because
`track_d_assets_test.dart` verifies that production resolution — a locator built
on the code under test could not tell a broken loader from a broken locator. The
walk shares no mechanism with the loader's (that resolves a `package:` URI
through the package config; this reads a source location), which is what makes
the loader probe's assertion a cross-check of two independent derivations rather
than a tautology.

**(2) The two cwd-independence proofs are preserved as child processes, not
deleted.** `track_d`'s foreign-cwd group is the only live fence on A24's named
invariant, so it spawns `test/fixtures/asset_loader_cwd_probe.dart` with
`workingDirectory` set to a temp dir and asserts the root a no-explicit-root
`PackagedAssetLoader()` resolved there EQUALS `p.join(packageRoot(), 'extension')`
— a stronger claim than the old "some rubric loaded", and it moves no global.
`test/support/package_root_test.dart` pins the anchor the same way. A child
process is the only way to exercise a foreign working directory without
reintroducing the hazard; `dart test -j 1` and tag isolation were refused
because they hide the race rather than remove it.

**(3) The site-binding construction-time read keeps its proof in two halves.**
Passing an explicit `HarnessProvider.siteBinding` proves only what the existing
test already proves, so the conventional document is loaded by EXPLICIT path
under a temp root, the provider is constructed from it, the document is DELETED,
and the mount is then asserted to carry the same instance; and the DEFAULT
read's POSITION is a structural fence over the provider's own class body (the
`loadJsonFile(kSiteBindingFile)` call sits above `buildWithChild`, and is the
pack's only caller). Scoped to that class body deliberately: the file declares
several providers, so a whole-file index would compare against a sibling's build
method.

**(4) `runRecall` gains exactly one optional `workingDirectory`**, defaulted to
`'.'` so `tool/search_recall.dart` and every other caller are unchanged. It is
the only production surface this bead touches.

**(5) Record mode is seeded from a fixture no tool writes.** The recall suite
seeded record mode from the DURABLE corpus and asserted that corpus's baseline
was empty. `--record-baseline` rewrites that same corpus's own baseline after a
green live run, so the assertion made a legitimate recording indistinguishable
from a regression — and a stale populated copy left on disk read as a failure.
The seed is now `semantic_recall_empty_baseline_set.json`, pinned empty, and the
contract test holds both corpora to the same cases and exact-id guard so the
seed cannot drift from what is actually searched. The durable corpus's baseline
is deliberately left unasserted rather than populated: it is documented as a
recorded LIVE baseline, and filling it from the pack's report fixtures would
record a measurement that never happened.

## Consequences

The suite has one anchor that is not the code under test, and the class of
defect is removed rather than hidden — no serialization flag and no tag-based
isolation was introduced. The two foreign-working-directory proofs got stronger
(an equality against an independently derived root, versus "something loaded").
The cost is one child process per proof and one optional production parameter.

## Alignment

`power_station#one-asset-resolution-defines-tree-and-writers` (bead `pow-4peu`,
which `updates` A24): "One pure `resolveGridAssets` evaluation over the
station-generated `GridAssetRegistry`, an immutable `SubstationFactsSnapshot`,
render values, and an optional roster override is authoritative." Three touched
suites exercise exactly that machinery — `test/assets/overlay_materializer_test.dart`
and `test/assets/overlay_install_test.dart` call `resolveGridAssets` over
`GeneratedGridAssetRegistrant.registry` with a hand-built
`SubstationFactsSnapshot`, and `test/assets/station_asset_registry_test.dart`
pins that registry's generation shape. The change at all three is confined to
where the vending ROOT is read from: the one resolution call, the snapshot it is
handed, the registry it evaluates, the roster override and every resolved
artifact path are byte-unchanged, and no writer's behaviour is touched. A24's
separate "Also (mechanical, no decision)" paragraph — the clause this bead
extends — is not the clause `pow-4peu` updates, so the two compose rather than
conflict.

`power_station#a28-bead-pow-d26-the-acceptance-suite-flake-is-the-molecule` is
honoured: "the fix is homed HERE" — the harness and one package-local injection
seam change, the_grid and A28's `settle` primitive do not, and the process-cwd
race is a distinct defect from A28's real-filesystem wait race.

`power_station#a8-bead-tg-kx1-the-d-h-doctrine-rides-the-coding-agent-worki`
("guards LOUD or GONE") is applied: the helper and both probes REFUSE loudly —
`packageRoot()` throws `StateError` naming both its source anchor and
`Platform.script` when the frame carries no file URI or the walk reaches the
filesystem root — rather than returning a guessed directory.

`power_station#the-spec-structural-contract-becomes-a-typed-record-grammar` is
preserved: `recordArtifact` remains the pack's single owner of the
temp-file-plus-rename discipline, and neither the recall path seam nor the empty
seed alters that writer or record-mode semantics.

## Confirmation

`grep -rn "Directory.current *=" packages/grid_assets/test` and
`grep -rln "File('lib/\|File('test/\|Directory.current" packages/grid_assets/test`
both print nothing and exit 1. `dart analyze`, `dart format --set-exit-if-changed`
and three consecutive full-suite runs are green, and the diff introduces no
`dart test -j`/`--concurrency` flag and no `@Tags`/`tags:` isolation.

## Affects

`packages/grid_assets/lib/src/search/search_recall.dart` (`runRecall`'s
`workingDirectory`), `packages/grid_assets/CHANGELOG.md`, new
`packages/grid_assets/test/support/{package_root.dart,package_root_probe.dart,package_root_test.dart}`,
new `packages/grid_assets/test/fixtures/asset_loader_cwd_probe.dart`, new
`packages/grid_assets/test/search/fixtures/semantic_recall_empty_baseline_set.json`,
and the test files whose locators now join on `packageRoot()` (including the
retained corpus's locator example in
`test/fixtures/spec_corpus/pow-kzx.design.md`, whose parsed contract and shadow
finding counts are unchanged). Composes with A24 (the cwd-independent invariant
is preserved, not weakened).
