---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a37-bead-pow-hxme-a-spec-critic-s-actionable-verdict-names-i
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A37"
---
## A37 (2026-09-02) — bead `pow-hxme`: a spec critic's actionable verdict NAMES its OWNER (`architect`|`author`), and an AUTHOR-owed finding parks for a human at round 0 — REFINING ratified A14(3)'s grade-as-boundary

**Decision (AI; autonomous run — recorded per ADR-0004 D3, "an ADR departure is recorded, not blocking").** A14(3)'s ratified boundary — *"grade-as-boundary (`D`/`E`→respec, `F`→human)"* — is REFINED, not removed: a `D`/`E` auto-respecs only when the finding is ARCHITECT-owned; an AUTHOR-owed one joins `F` on the human side. The autonomous calls inside that shape: **(1)** the critic verdict schema gains an `owner` column (`kVerdictOwnerKey`, closed vocabulary `kVerdictOwners` = {`architect`, `author`}), REQUIRED whenever the grade is `D` or `E`. **(2)** The ONE shared decoder (`_verdictFromFile`) enforces it behind a DEFAULTED `requireOwner` flag whose value is a per-family switch (`CriticCapability.requiresVerdictOwner`, `false` in the base class and `true` only in `SpecCriticCapability`) — the verdict TRANSPORT stays shared exactly as A13(3) ratified, and the code + readiness families are never refused for omitting a key their prompts never state (A19). **(3)** `decideSpecRoute` gains ONE arm, between the `no-rationale` arm and the `respec` arm: a fixable join containing ANY author-owed lane returns `SpecEscalate(rule: 'author-owed')` IMMEDIATELY, spending NO round of A15(4)'s bound, and quotes each author-owed lane's rationale verbatim so a governor cures the bead BODY once. **(4)** A blank or unrecognised owner reads as ARCHITECT-owed in the matrix — today's behaviour, so nothing regresses on a critic that has not yet learned the column; the LOUD guard against a missing owner is the DECODER, never a silent matrix default. **(5)** A15(4)'s bound (2) is UNTOUCHED: this narrows WHEN the auto-loop applies, never how far it runs. **(6)** The column is a PAYLOAD field, not a freshness stamp: it is validated after the grade and before A4's `nodePath` and A15(5) alt-A's `round` fences, it does not participate in freshness (`restampVerdictRound` rewrites with `{...decoded}`, so it survives a re-stamp unchanged), and the round-aware janitor `sweepStaleCritique` reads at the permissive default so it can never DELETE a current-round verdict for a payload defect the read path is the LOUD owner of.

**Why.** The auto-respec loop is the right instrument for a defect the architect can fix from the bead as written plus the tree, and the wrong one for a FORK the bead text never decided. The receipt: on 2026-09-02 `pow-n6n.1` drew a coherence `D` twice after auto-respec because the `D` asked the architect to choose between its own symbol names and `pow-n6n.2`'s. Both rounds were unwinnable by construction — `specify` re-ran against the same bead text and re-drew the same grade — and they cost about fifteen dollars (one opus specify plus four sonnet lanes per round, from the `.usage.json` telemetry) before the respec cap gated to the governor, who decided it in one body edit. The same shape produced that day's readiness holds: every one was a fork in the body, none an architect defect. A14(3)'s PURPOSE ("a human is the ESCALATION, not the default") is preserved for every finding an architect can actually fix, and restored for the class where a respec round cannot converge. Prior art: bead `pow-bhm` (deferred; Nico-ratified 2026-07-18 — "bead-graph findings route to refinement, never round-fail") is the broader committee re-tune this mechanism serves; it is a BEAD, not an amendment in this register, so this amendment declares the departure on its own terms rather than leaning on it for authority.

**Affects (if promoted):** `packages/grid_assets/lib/src/code/committee.dart` (`kVerdictOwnerKey`, `kOwnerArchitect`, `kOwnerAuthor`, `kVerdictOwners`, `kVerdictOwnerInstruction`, `CriticCapability.requiresVerdictOwner`; new optional params on `verdictJsonTemplate`, `currentVerdictFromFile`, `currentVerdictOnDisk`), `specify.dart` (`SpecCriticCapability.requiresVerdictOwner` + the prompt column), `respec.dart` (`SpecLane`'s required `owner` field, `decideSpecRoute`'s `author-owed` arm), the four judgement rubrics under `extension/rubrics/`, and `extension/prompts/spec-critic.md`; tests: `respec_test.dart`, `spec_committee_test.dart`, `verdict_transport_test.dart`, `spec_rubric_pack_test.dart`. REFINES ratified A14(3); HONOURS ratified A13(3) (one transport, one decoder) and A14(2) (the decision fork), A14(6) (rationale-less still escalates first), A15(4) (the bound), A29 (every escalate arm spends the guidance ledger), A19 (only the family taught the contract is held to it), A34(6) (`pow-q5n`'s strict decode stays the ONE place a malformed verdict fails the lane), and A4/A15(5) alt-A (the freshness stamps). Does NOT revive A31, which the register records as rejected. the_grid: none. Out of scope: `pow-bhm`'s single-D-advances arm and its code-committee half; `pow-0gg`.

**Status:** Pending — Nico promotes or rejects.

