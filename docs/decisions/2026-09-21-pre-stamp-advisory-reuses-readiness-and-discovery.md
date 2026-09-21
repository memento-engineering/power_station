---
status: accepted
date: 2026-09-21
decision-makers:
  - "Nico Spencer"
  - "governor (power_station)"
consulted: []
informed: []
register:
  spec: 1
  slug: pre-stamp-advisory-reuses-readiness-and-discovery
  surfaces:
    - "packages/grid_assets/lib/src/filing/**"
    - "packages/grid_assets/lib/src/code/readiness.dart"
    - "packages/grid_assets/lib/src/code/discovery.dart"
    - "packages/grid_assets/lib/src/code/committee.dart"
  obsoletes: []
  updates:
    - "approval-is-the-stamp-the-grid-approved-label-retires"
    - "the-refiner-exit-oracle-is-the-filing-verb"
    - "readiness-route-joins-on-a-published-verdict-never-on-absence"
    - "discovery-evidence-is-gathered-once-and-projected"
    - "the-dependencies-row-is-a-projection-of-bd-dependency-rows"
  obsoleted-by: null
  updated-by: []
  bead: pow-v4xh
  legacy-id: null
---

# The pre-stamp advisory is a new CALL SITE for the readiness and discovery predicates, and it publishes nothing

## Context and Problem Statement

Measured 2026-09-15 over lunar epoch 85 (grid_assets `0.7.0-dev.2`): of 36
mounts, roughly 17 hit a spec-readiness hold or a discovery hold at
`spec_review` before any specify agent ran. Stale line citations, phantom
decision tokens in prose, undecided forks, unacknowledged departures, one
clipped over-bound decision entry.

Every one of those cost the same sequence: a mint, a discovery gather, a lens
run, a gate, an operator cure round of 5–15 minutes at full context, a rework
and a re-mint. The lenses were RIGHT every time. They simply ran at the most
expensive point in the circuit, and the thing they refused — the bead's own
text — was already open in front of the refiner a whole circuit earlier.

The question this entry answers is not whether to move the judgement earlier.
Nico stamped that on 2026-09-16. It is what shape the earlier call may take
without minting a second judgement, without touching the route's join, and
without reordering the stamp.

## Decision Outcome

### (a) A new CALL SITE for existing predicates, never a fourth predicate

The pre-stamp advisory invokes the ALREADY-SHIPPED intake readiness lens
(`intakeFindings` + the `bead-readiness` lens prompt, decided by
`decideReadiness`) and the ALREADY-SHIPPED discovery evidence gather
(`gatherDiscoveryAnchors` + the three lenses, decided by `decideDiscovery`),
from the filing verbs' existing `FilingContract` preflight point.

`power_station#the-refiner-exit-oracle-is-the-filing-verb` permits exactly
this: the refiner's exit criterion is a CALL to the already-shipped `filing`
Command, and what it forbids is a predicate of its own. A fourth predicate
variant is out of scope and is not minted here.

The prompts, the verdict schema versions, the evidence bounds and the
roster-mode lookup are literally the same functions — `readinessLensPrompt`,
`gatherDiscoveryAnchors`, `assembleDiscoveryLensPrompt`,
`projectDiscoveryEvidence` — reached through one shared builder each, with
`LensResultTransport` as the ONLY parameter that differs between the two call
sites. `power_station#a-mechanical-lookup-is-a-vended-command-with-a-bounded-output`
requires that shared mechanism not be re-derived per command, and a lens that
graded a bead differently depending on which verb asked would be exactly that
re-derivation.

### (b) No on-disk artifact and no node path

The advisory's verdict is returned in-process and rendered to the operator on
the verb's stdout or in its JSON. It is NEVER written under a session's node
path or round: every lens rides the in-process transport arm, which names no
write path, forbids a file write in its closing instruction, and passes no
usage-capture redirect.

`power_station#readiness-route-joins-on-a-published-verdict-never-on-absence`
is therefore untouched. The spec-review route still joins only on its own
published verdict, and a pre-stamp run can neither satisfy nor collide with
it, because it publishes nothing for that join to read.

The three-state discipline that entry fixed rides along to the new call site
unchanged: a PRESENT failing grade holds with `renderRefinementAsk` verbatim, a
lens that did not complete — or completed and published nothing readable —
refuses LOUDLY under its own named rule rather than becoming either a bead hold
or a free pass, and absence never advances anything.

`power_station#discovery-evidence-is-gathered-once-and-projected` keeps its
mechanism: `AnchorsCapability` remains the single deterministic gather for the
circuit, and it retains the generation-aware sweep, the cancellation checks and
the artifact write. What moved out of it is only the deterministic body both
call sites must not answer differently. The advisory holds its gather in
memory and persists none of it.

### (c) The order is fixed, and the advisory is LAST before the stamp

`memento-engineering#approval-is-stamped-last-and-an-agent-stamps-its-own-bugs`
fixes the sequence: file unapproved → dedupe → wire deps → every
`FilingContract` row → THIS advisory → stamp.

The advisory runs only after every mechanical row passes. A failing row already
refuses on its own, and the advisory never runs to mask it — the ten rows are
free and already refuse a phantom canonical citation, an unparseable plan and
an absolute path, so spending inference to re-discover any of those is the
waste this advisory exists to remove. An advisory refusal composes as one more
named refusal in the same preflight report, carrying the owning lens's own fix
text byte-for-byte.

The opt-out is `--readiness=skip`, and its use is recorded on the stamp.

## The completeness lane is unchanged, and so is `armedSubstations`

`power_station#the-dependencies-row-is-a-projection-of-bd-dependency-rows` is
the currently-binding ruling on the exact signatures this work edits. It
records the `armedSubstations` parameter on `FilingContract.evaluate`,
`FilingService.inspect`/`check`, `ApproveService.approve`, `UnparkService.unpark`
and the three commands, and it reaffirms the completeness-lane boundary it
inherited: *"The report still carries exactly four requirements with unchanged
wire names and order… No fifth requirement and no second predicate is
minted."*

Both hold here, and neither is a departure:

- `armedSubstations` is UNTOUCHED. It stays required, stays threaded through
  every one of those signatures, and the dependency projection it resolves is
  unchanged. The new `FilingAdvisoryMode` parameter is added BESIDE it on the
  same call chain; it does not displace, wrap or re-derive it.
- No requirement is minted. `FilingRequirement` still carries exactly its ten
  values, with unchanged wire names and order, and `FilingReport.requirements`
  still holds exactly those rows. The advisory rides its OWN member
  (`FilingReport.advisory`), because a judgement an LLM makes is not a
  mechanical row and must never read as one. A reader of `requirements` sees
  exactly what it always saw.

`power_station#notes-are-receipts-and-a-phantom-legacy-token-is-reported-not-failed`
is likewise preserved whole: citation extraction still reads description and
design only, an unresolved legacy id is still reported rather than failed, and
a canonical missing `repo#slug` still fails the mechanical `decision_references`
row BEFORE any inference runs.

## The stamp gains provenance; the receipt tuple does not

`power_station#approval-is-the-stamp-the-grid-approved-label-retires` ruled
that the `approve` verb writes only the three stamp keys. Nico's 2026-09-16
ruling on `pow-v4xh` extends that: the same atomic update may also carry what
the advisory judged.

- A pass adds exactly `grid.readiness_grade=<A|B|C>`.
- A waiver adds exactly `grid.readiness_skipped=true` and
  `grid.approved_advisory=skipped`, and no grade.
- An advisory that was never asked adds neither.

All of it rides the SAME single `bd update` as the receipt, because a receipt
and the account of what was judged to earn it must land together or not at all.

None of it is read by `ApprovalStamp.tryParse`. `grid.approved_by`,
`grid.approved_at` and `grid.approved_rev` remain the sole required validity
tuple and the sole mount marker. A receipt carrying no advisory provenance is
exactly as valid as one carrying all of it — which is what keeps every receipt
minted before this existed readable, and what keeps a waiver writable at all.

## Consequences

`filing`, `approve` and `unpark` now make inference calls by default, and each
can refuse a bead the ten mechanical rows pass. That is the intended trade: one
mid-tier lens plus three cheap ones at the stamp, against a mint, a gather, a
gate, an operator cure round and a re-mint at `spec_review`.

Composition is fail-closed. A verb asked to RUN an advisory that was never
composed refuses naming what is missing, exactly as an unasked decision index
refuses a citation rather than clearing it. A consumer that is not a stamp
moment — the mount explainer, the reconciler's eligibility read — keeps
`FilingAdvisoryMode.off` as its default and spends nothing.

Production surfaces: `lib/src/filing/pre_stamp_advisory.dart` (new),
`lib/src/filing/filing_contract.dart`, `lib/src/filing/filing_command.dart`,
`lib/src/filing/approval_stamp.dart`, `lib/src/filing/approve_command.dart`,
`lib/src/filing/park_command.dart`, `lib/src/code/committee.dart`,
`lib/src/code/readiness.dart`, `lib/src/code/discovery.dart`.

Public symbols added: `FilingAdvisoryMode`, `FilingAdvisory`,
`FilingAdvisoryVerdict`, `FilingAdvisoryPassed`, `FilingAdvisoryRefused`,
`FilingAdvisorySkipped`, `PreStampAdvisory`, `FilingReport.advisory`,
`FilingReport.refusalReason`, `LensResultTransport`, `LensArtifactTransport`,
`LensInProcessTransport`, `kInProcessResultInstruction`,
`verdictFromResultText`, `readinessLensPromptBody`, `readinessLensPrompt`,
`readinessRubricText`, `readinessLensRuntimeConfig`, `gatherDiscoveryAnchors`,
`assembleDiscoveryLensPrompt`, `discoveryLensPrompt`,
`discoveryLensRuntimeConfig`, `discoveryLensOutcomeFromResultText`,
`kReadinessGradeKey`, `kReadinessSkippedKey`, `kApprovedAdvisoryKey`,
`kApprovedAdvisorySkipped`, `addReadinessOption`, `readinessModeOf`,
`kReadinessOption`, `kReadinessRun`, `kReadinessSkip`, and the
`ApprovalStamp.readinessGrade` / `ApprovalStamp.advisorySkipped` fields.
