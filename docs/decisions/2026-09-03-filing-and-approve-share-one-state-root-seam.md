---
status: accepted
date: 2026-09-03
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: filing-and-approve-share-one-state-root-seam
  surfaces:
    - "packages/grid_assets/lib/src/filing/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-z2pj
  legacy-id: null
---
## Filing and approve share ONE state-root seam, and a blocker is DECLARED, not mentioned (2026-09-03) — bead `pow-z2pj`

**Decision (AI; MECHANISM only).** The `--state-root` option, its help line, its
`noStateRoot` default and its per-run resolution live once, in
`packages/grid_assets/lib/src/filing/state_root_option.dart`. `FilingCommand`
and `ApproveCommand` both register and resolve through it. The two verbs read
one `FilingContract`, so they must read one grid home the same way: before this,
`approve` consulted the state store's link beads and `filing` did not, and a
bead wired by an open link bead was `dependencies=false` under one verb and
approved under the other.

**Decision.** A blocker is DECLARED by a description segment that OPENS with
`Blocked by` / `Blocked on` / `Depends on`. A mid-sentence occurrence of the
phrase is a MENTION and declares nothing — the bug report that named this defect
was itself refused because its receipt quoted `DEPENDS ON: tg-1n4y`. Segments end
at a sentence terminator followed by whitespace, or at a line break, so dotted
child ids stay intact. This matches the authored contract the vended
`intake-refinement` and `discover` skills already teach: name each blocker on its
own `Blocked by:` or `Depends on:` line.

**Decision, and a departure from the bead text.** Within a declaring segment a
`<prefix>-<tail>` token is a bead id when its prefix is KNOWN — the checked
bead's own store, or the store of a blocker already wired by a local `blocks`
edge or an open link bead — OR when its tail carries a digit. The bead offered
"at minimum require a digit in the tail"; that alone is REJECTED, because real bd
ids are frequently digitless and the existing suite proves it (`pow-one`,
`pow-two`, `filing-blocker` are live fixtures). A digit-only rule would silently
stop naming them, and a gate that quietly passes is worse than the false positive
it removes.

**Read-only posture, and a numbering note.** This verb reads and never writes:
`ExactSubstationBeadSource` issues only `query` + `dep list`, and
`CrossLinkBlockerSource` only `list -t link --status open`. That is ratified
A11(3)'s posture verbatim — *"A37 is held BY CONSTRUCTION, not by a runtime
guard: the service is built on a seam ... with no mutation surface ... (fenced by
test: the recorded argv set is exactly `[['export','--all']]`)"* — and the new
command test extends the same argv fence to the command layer. The `A37`
shorthand inside A11(3) is INHERITED numbering drift: this register's own A37
slot now holds the 2026-09-02 spec-critic verdict-owner decision
(`power_station#a37-bead-pow-hxme-a-spec-critic-s-actionable-verdict-names-i`),
which says nothing about reads. The governing clause is A11(3)'s, cited by its
own number here so the next bead at this seam does not re-inherit the drift.

**Known residue.** A foreign, digitless id named in a store that has no wired
blocker of that prefix reads as prose and is not required. Closing it needs the
substation ROSTER's prefixes at this seam (`SubstationScope.prefix`, resolved
through the roster mount A11(1) established), which `FilingCommand` has no
delegate for today; the bead's own preferred fix. Recorded here rather than
shipped, so the next bead at this seam does not re-derive it.

**Affects:** `packages/grid_assets/lib/src/filing/state_root_option.dart` (new),
`filing_command.dart`, `approve_command.dart` (wiring only — no behaviour
change), `filing_contract.dart`, `packages/grid_assets/lib/grid_assets.dart`, and
`packages/grid_assets/test/filing/filing_command_linked_blockers_test.dart`
(new). CONSUMES A30's link-bead mechanism unchanged, HONOURS A11(3)'s read-only
posture, and discharges ADR-0001's coupling clause for the filing verb. The
one-line composition that threads the grid home into both verbs on a station's
`buildRunner` lands with its own bead in the composing repo — the same split
A11's "Affects" already took for `SearchCommand`.

**Status:** Pending — Nico promotes or rejects.
