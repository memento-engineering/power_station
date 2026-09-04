---
status: accepted
date: 2026-09-03
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: discovery-lens-reports-carry-the-round-and-the-wipe-sweeps
  surfaces:
    - "packages/grid_assets/lib/src/code/discovery.dart"
    - "packages/grid_assets/lib/src/code/committee.dart"
  obsoletes: []
  updates:
    - "a21-bead-pow-96y-the-discovery-circuit-a-nested-read-only-ga"
  obsoleted-by: null
  updated-by: []
  bead: pow-3yo
  legacy-id: null
---
## Discovery lens reports carry the ROUND, and the anchors wipe becomes a round-aware SWEEP (2026-09-03) — bead `pow-3yo`

**Decision (AI; MECHANISM only — the policy is A15(5) alt-A's, already
ratified).** The discovery circuit adopts the committee's two freshness
mechanisms verbatim rather than growing its own. (1) A lens report carries BOTH
stamps and one fence reads them: `_freshLensReport` refuses a foreign
`nodePath` (A4) or a non-current `round` (A15(5) alt-A), and it rules the
canonical file, the envelope fallback and the sweep's keep test alike. (2) The
round parser is committee.dart's, promoted from `_stampedRound` to the public
`stampedRound`; the round SOURCE is `verdictRound(args)`, the engine-injected
`grid.round`, unchanged. (3) `AnchorsCapability`'s blanket wipe becomes
`sweepStaleDiscovery`, which deletes exactly what the read fence would refuse
and KEEPS this round's reports — A21(4)'s guarantee is preserved and made
order-independent. (4) The route's join classifies an artifact-less lane
instead of dropping it: a lane that recorded THIS round's result is LOUD
immediately, a lane that recorded nothing is LATE and is waited for
(`lanePoll`/`laneWaitBudget`, the `SpecRouteCapability` shape). A21(3) is
untouched — absence still never HOLDS the bead; it re-gathers once and then
advances with the miss named.

**Departure recorded: A34's capability-authored stamp is NOT ported.** A34
moved the CRITIC's round stamp off the model ("A fence whose stamp is authored
by the thing it fences is not a fence") onto an mtime incarnation marker,
because a contaminated stamp let a stale VERDICT LETTER decide a gate. A lens
emits no letter: under A21(3) a mis-stamped report is MISSING, so the worst
outcome is one wasted re-gather round, never a false grade and never a false
hold. The marker mechanism, its `model_round` preservation and its two flares
stay scoped to the critic families; discovery takes the stamp + fence half
only. If a contaminated lens stamp is ever observed, porting
`restampVerdictRound` to `.grid/discovery/` is the fix, and it composes with
this entry rather than replacing it.

**Why.** Discovery declares `validates: anchors` and therefore carries the same
engine-derived mixed-generation exposure PR #68 fixed for the committee: the
wave re-keys the gather closure node by node, so a re-keyed lens can write this
round's report before the re-keyed `anchors` runs. Before this bead the join
had NO round fence at all and the wipe was blanket, so the two failure modes
the committee already survived were both live here — observed at the discovery
join in the bridge #2 autopsy (`pow-t2z` r2). The engine-side
generation-atomicity fix removes the trigger; this is the defence in depth that
makes discovery fail LOUD rather than decide on a partial join if any
interleave recurs.

**Affects.** `packages/grid_assets/lib/src/code/discovery.dart`
(`kLensStampInstruction`, `_freshLensReport`, `readLensReport`,
`LensReportReader`, `sweepStaleDiscovery`, `AnchorsCapability.run`,
`DiscoveryLensCapability.buildLensPrompt`/`spawn`/`result`,
`DiscoveryRouteCapability.lanePoll`/`laneWaitBudget`/`route`);
`packages/grid_assets/lib/src/code/committee.dart` (`stampedRound` promoted);
tests: `test/discovery_lens_race_test.dart` (CREATED), `test/discovery_test.dart`,
`test/spec_rubric_pack_test.dart`, `test/acceptance/discovery_acceptance_test.dart`.
