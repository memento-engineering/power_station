---
status: accepted
date: 2026-09-01
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a34-bead-pow-uok-a15-5-alt-a-s-round-stamp-gets-a-capability
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A34"
---
## A34 (2026-09-01) — bead `pow-uok`: A15(5) alt-A's round stamp gets a CAPABILITY writer — an mtime INCARNATION MARKER outside the swept critique dir is the freshness proof, the model's copy is preserved as `model_round`, and both probe outcomes flare

**Decision (AI; mechanism only — the policy is Nico's 2026-09-01 ruling "keep the clause, change the writer").** A15(5) alt-A's equality check (`stampedRound == expectedRound` in `_verdictFromFile`) is untouched, and so is A4's `nodePath` fence. What changes is WHO authors the stamp the check reads. The autonomous calls: (1) the freshness PROOF is a per-lane INCARNATION MARKER file whose mtime is stamped at the spawn edge (`criticIncarnationPath`), and a verdict is re-stamped only when its `nodePath` matches AND its mtime is at or after that marker — `ClearCritiqueCapability`'s sweep stays a belt, exactly as the ruling directs. (2) The marker lives OUTSIDE `.grid/critique/`, under `.grid/critique-incarnation/`, because `sweepStaleCritique` empties the critique dir of everything except the current round's `<rubric>.json`; a marker inside it would be deleted by a mid-wave sweep (the tg-60t race) and the fix would silently degrade. (3) The marker write is BEST-EFFORT, following `ClearCritiqueCapability`'s in-file precedent and rationale: a failed write costs only the re-stamp, and the ratified fence still judges fail-closed. It is not silent — the probe flares `no incarnation marker`. (4) The model's copy is PRESERVED as `model_round` rather than discarded, so the artifact keeps the evidence of contamination. (5) Two flares are added on `ServiceBundle.transport`: `critic.verdictRoundRestamped` (rubric, nodePath, round, model_round) and `critic.verdictProbeUnresolved` (rubric, nodePath, round, fileRound, restamp, strayTried, envelopeTried) — so a session held on the engine's "declared completion artifact is not durable" contract can be attributed to this probe instead of misread as a lane verdict. (6) `restampVerdictRound` NEVER throws: an unparseable or unstamped file is SKIPPED, leaving `pow-q5n`'s strict-decode contract as the one and only place a malformed verdict fails the lane.

**Why.** Three live sessions (pow-p18 r4, tg-j9ac r4, and an earlier respec-cap arc) closed HELD with a passing grade on disk. The mechanism was verified in tg-j9ac's worktree: `acceptance-testability.json`, `adr-alignment.json` and `coherence.json` carried round 4 while the engine's `grid.round` was 1, and `plan-completeness.json` — which carried 1 — completed. The critics had copied the `--- grid rework ROUND 4 ---` header out of the bead's own notes. A fence whose stamp is authored by the thing it fences is not a fence; the writer had to move to the capability, which already holds the engine-injected round at both the probe and the result edge.

**Affects (if promoted):** `packages/grid_assets/lib/src/code/committee.dart` (`kVerdictModelRoundKey`, `kCriticIncarnationDir`, `criticIncarnationPath`, `RoundRestamp` + its three variants, `restampVerdictRound`, `CriticCapability.recordCriticIncarnation`, `CriticCapability.spawn`, `CriticCapability.probeCompletionArtifact`), `specify.dart` (`SpecCriticCapability.spawn`), `readiness.dart` (`ReadinessCriticCapability.spawn`); tests: `track_c_critic_test.dart`, `spec_committee_test.dart`, `readiness_test.dart`. Composes with A4 and A15(5) alt-A; resolves A27(7)(a)'s carve-out for `committee.dart`'s round stamp (whose source `pow-96s` had already moved off the dead `rewindCount` to the engine-injected `grid.round`). Open follow-up `pow-dzc` (narrower restart budget for invalid verdicts) is unchanged.

**Status:** Pending — Nico promotes or rejects.

