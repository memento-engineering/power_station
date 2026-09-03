---
status: accepted
date: 2026-09-03
decision-makers: ["Nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: a-harness-may-carry-its-own-instructions
  surfaces:
    - "packages/grid_assets/test/assets/overlay_codex_leg_test.dart"
    - "packages/grid_assets/extension/station_overlay/**"
  obsoletes: []
  updates:
    - the-worktree-overlay-scope-widens-to-every-skill-tree
  obsoleted-by: null
  updated-by: []
  bead: pow-emxf
  legacy-id: null
---

# A harness may carry its own instructions — the per-harness overlay legs are independent instruction sources

## Context and Problem Statement

`power_station#the-worktree-overlay-scope-widens-to-every-skill-tree`
(bead `pow-99g`, PR #176) vended the codex leg of the station overlay and
recorded: "The codex leg is authored as a byte-identical COPY of the claude leg
under `extension/station_overlay/agents/skills/`, pinned by test rather than by
a mechanism". It named the cost in the same breath — "every skill edit must
land twice; the byte-identity test is what makes that loud instead of silent" —
and the cost arrived on the first collision. `pow-vwny` (PR #177) edited two
claude skills (`discover`, `intake-refinement`); the moment #176 landed ahead of
it, the merge-group run for #177 failed the twin test, the queue ejected the PR,
and the governor had to hand-copy the edited skills over their twins to
re-queue. Worse than the tax: under the pin a genuinely harness-specific
instruction — a codex-only note, a claude-only tool hint — is unrepresentable.

## Decision Outcome

Per Nico, 2026-09-03: "That is overbearing. Different harnesses can have
different instructions." Each per-harness leg of `station_overlay`
(`claude/skills`, `agents/skills`) is an INDEPENDENT instruction source.
Identical content between legs is PERMITTED and remains the common case — the
SKILL.md + frontmatter format really is shared — but it is never REQUIRED, and
nothing tests for it. `packages/grid_assets/test/assets/overlay_codex_leg_test.dart`
loses its `'every agents-leg SKILL.md is BYTE-IDENTICAL to its claude twin'`
test.

What the leg still owes is STRUCTURE, and those checks are untouched: both legs
vend exactly the `kVendedSkills` id set (a skill present for one harness and
absent for the other is a vending GAP, which is a defect in the vending rather
than an instruction difference), the agents leg carries SKILL.md files and
nothing else, and no copilot leg is authored.

This entry UPDATES the pow-99g entry on exactly one clause — the byte-identical
copy rule and the test that pinned it. Everything else pow-99g recorded stands
verbatim: the worktree overlay scope is still the SET of per-harness SKILL
trees, the per-asset-dir `.gitignore` fence still derives from that scope, the
materializer still gains no placement branching (A26's path-preserving
invariant is untouched), and no loose root file is vended. The ratified entry is
not edited.

### Consequences

* Good, because a skill edit lands on the leg it belongs to and no longer has
  to be mirrored to keep CI green; the #177 ejection class of failure is gone.
* Good, because a harness-specific instruction is now expressible at all, which
  is what a per-harness leg is for.
* Neutral, because the legs are byte-identical today and stay so until someone
  has a reason to diverge; nothing is copied, moved, or rewritten by this
  decision.
* Bad, because a copy-paste MISTAKE on one leg is no longer caught by a test —
  an unintended divergence now reads the same as an intended one. Accepted:
  under the pin the same mistake was caught only by making every deliberate
  edit expensive, and Nico ruled that trade overbearing. The id-set and
  SKILL.md-only checks still catch the failure mode that is unambiguously a
  defect — a skill missing from a harness.

### Confirmation

`cd packages/grid_assets && dart test test/assets/overlay_codex_leg_test.dart`
— three structural tests pass, and appending a line to one leg's SKILL.md
leaves them passing.
