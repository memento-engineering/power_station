---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: the-refiner-exit-oracle-is-the-filing-verb
  surfaces:
    - "packages/grid_assets/extension/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-glza
  legacy-id: null
---
## The refiner's exit oracle IS the filing verb (2026-09-02) — bead `pow-glza`

**Decision (AI; MECHANISM only).** The `intake-refinement` skill's exit
criterion is a CALL to the already-shipped `filing` Command
(`packages/grid_assets/lib/src/filing/filing_command.dart`, over
`FilingContract` in `filing_contract.dart`), not a predicate of its own. The
corpus runs `<runner> filing --json "<bead>"`, applies each failing row's
`detail` as the correction, reruns until `passed` is true, and only then stages
for the `approve` verb. No `refinerExitFindings` helper is minted, and
`packages/grid_assets/lib/src/code/mount_eligibility.dart` is not touched.

**Two contracts, two owners — this is the load-bearing half.** FILING
COMPLETENESS is the OPERATOR-side, PRE-APPROVAL contract: `FilingContract`'s
four rows (`driveable_type`, `validation_plan`, `acceptance_criteria`,
`dependencies`), owned by `lib/src/filing/`, consumed by the refiner and by the
`approve` verb's preflight. MOUNT ELIGIBILITY is the ENGINE-side, PRE-SESSION
contract: `mountEligibilityFindings` (driveable type, `validation_plan`, and
the STAMPED `grid.approved` label), owned by `lib/src/code/`, consumed by the
grid_engine mount predicate. They differ in owner, in stage, and in content —
approval is in one and absent from the other by design. Neither subsumes the
other, and a third completeness predicate is a duplication, not a gap.
(`intakeFindings` in `lib/src/code/readiness.dart` is the third, distinct,
already-recorded contract: the cheap pre-specify intake gate.)

**Why:** an earlier draft of this bead proposed a `refinerExitFindings` helper
and an edit to `mount_eligibility.dart`; it was graded a coherence F on
2026-09-02 because the oracle already ships and `space_station` main already
composes both verbs. Recording the boundary is what stops the next refiner bead
from re-deriving it. It also discharges ADR-0001's coupling clause for this
asset — "The skill CALLS the command rather than re-deriving the operation by
inference" — with the same shape `discover`/`search` already proved.

**Affects:**
`packages/grid_assets/extension/station_overlay/claude/skills/intake-refinement/SKILL.md`
(the exit check plus seven refiner rules), and its fences in
`packages/grid_assets/test/assets/skill_assets_test.dart` and
`packages/grid_assets/test/assets/overlay_install_test.dart`. No Dart library
file changes and no public symbol changes.

**Status:** Pending — Nico promotes or rejects.
