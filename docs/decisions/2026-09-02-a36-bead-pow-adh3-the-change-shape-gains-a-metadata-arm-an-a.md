---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a36-bead-pow-adh3-the-change-shape-gains-a-metadata-arm-an-a
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A36"
---
## A36 (2026-09-02) — bead `pow-adh3`: the change shape gains a METADATA arm — an ALLOW-list of non-code surfaces, routed to the EXISTING docs circuit, fenced by ONE shared path predicate

**Decision (AI).** `ChangeShape` gains a third value, `metadata`, for a bead whose `## Touches` cites only non-code surfaces (`CHANGELOG.md` and any `*.md`, `pubspec.yaml` and any `*.yaml`/`*.yml`, `*.json`, `*.toml`, `LICENSE`). The autonomous calls: (1) the admission test is an ALLOW-list (`kMetadataPathExtensions` + `kMetadataPathFilenames`, read by `isMetadataPath`), never a deny-list of source extensions — an unlisted surface (`tool/release.sh`, an extension-less script, a template) must fall to the CODE committee, preserving `changeShapeOf`'s documented fail-to-code posture; a deny-list would route every surface nobody enumerated at a prose committee. (2) `isMetadataPath` is a strict SUPERSET of `isDocsPath`, so ONE predicate serves both the classification and the lanes' foreign-file fence — never a second, drifting path vocabulary. (3) `metadata` routes to the EXISTING `docs_review` circuit rather than a fourth committee: the lane set a release bump needs is exactly the docs one (three deterministic checks plus `spec-adherence`, no `test-coverage`), and a circuit whose lanes would be identical is duplication. (4) The `DocsCheckCapability` fence therefore admits metadata paths for BOTH shapes — a docs-shaped bead whose diff also bumps a `pubspec.yaml` is now admitted rather than hard-blocked. Declared consequence: the narrower alternative (re-deriving the shape inside the lane) would make the lane's refusal depend on the bead's prose twice, and the lane's job is to fence the DIFF. (5) The refusal message is re-worded from `non-docs file(s)` to `source file(s)` — the fence now names what it actually refuses, and guards LOUD keeps its voice.

**Why.** Two live receipts on 2026-09-02: `pow-x6k` (power_station #160, `CHANGELOG.md` + `pubspec.yaml`) graded A/A/F and needed a governor override with receipts; `swift-infer-ecny` (`README.md` + `example-config.json`) graded A/A/F and burned a rework round on a test written only to satisfy the lane. `test-coverage` grades a diff with no code F BY DESIGN — the same defect the docs committee already exists to fix — so the fix widens the SHAPE that selects the committee, and never softens the rubric (explicitly out of scope on the bead).

**Affects (if promoted):** `packages/grid_assets/lib/src/code/docs_committee.dart` — NEW public `kMetadataPathExtensions`, `kMetadataPathFilenames`, `isMetadataPath`; NEW enum value `ChangeShape.metadata` (a breaking addition for any exhaustive `switch` over it, of which this repo has exactly one, in this file); `changeShapeOf`, `ChangeShapeCircuitResolver.circuitFor`, `DocsCheckCapability.run`'s fence and rationale, plus the library header prose. All three new symbols reach the pack API through the existing wholesale `export 'src/code/docs_committee.dart'`. Tests: `packages/grid_assets/test/docs_committee_test.dart`. No `grid_engine` and no the_grid change. Extends the docs committee (bead `pow-ay8`, never recorded in this register) and composes with A9's pinned-diff scope, which the lanes still read unchanged. Does not touch `test-coverage`'s rubric prose, and does not overlap `pow-hxme` (the verdict `owner` field) or `pow-aoa` (`declared-tests-present`).
