---
status: accepted
date: 2026-09-21
decision-makers:
  - "Nico Spencer"
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: the-content-row-refuses-the-nul-byte-and-nothing-else
  surfaces:
    - "packages/grid_assets/lib/src/filing/filing_contract.dart"
    - "packages/grid_assets/extension/station_overlay/agents/skills/intake-refinement/SKILL.md"
    - "packages/grid_assets/extension/station_overlay/claude/skills/intake-refinement/SKILL.md"
    - "packages/github_grid_assets/lib/src/intake/github_intake_store.dart"
  obsoletes: []
  updates:
    - "pre-stamp-advisory-reuses-readiness-and-discovery"
  obsoleted-by: null
  updated-by: []
  bead: pow-2bkw
  legacy-id: null
---

# The filing contract's CONTENT row refuses the NUL byte and nothing else

## Context and Problem Statement

The filing contract grew an eleventh row, `no_corrupting_text`, to stop
remembering one rule and start refusing it: bead body text must survive being
written and read back. The rule as it had been carried in prose named two code
units — the NUL byte and the backtick — and the first implementation refused
both.

The two are not the same fact. A NUL truncates the write that carries the
field, and `bd` reports success anyway, so the bead files clean and dies a
build later without naming its own cause. A backtick does nothing to `bd` or to
the bead. What it can do is get command-substituted by the shell of whoever
WRITES the bead, in an unquoted heredoc — a property of the writing recipe, not
of the text.

Measured against the 22 beads stamped at the time, the backtick half of the row
refused 7 of them, including the bead that introduced it. Bead prose is
markdown; a code span is ordinary authoring.

## Considered Options

* **Refuse both units.** Implemented first. Mechanically simple, and it holds
  correct beads at every filing caller — `filing`, `approve`, `unpark` and the
  mount explainer — for text no reader would call corrupt.
* **Refuse the NUL byte only.** Keeps the refusal exactly as wide as the
  corruption, and leaves the heredoc hazard where it is actually cured.
* **Refuse neither and keep the rule as prose.** Rejected before this round:
  prose had already failed at this rule twice, because the failure is invisible
  at the moment it is made.

Nico ruled on 2026-09-21, after the first implementation was held at landing:
"backticks help me, and i'm sure agents, distinguish symbols versus words." The
row refuses the NUL byte; a backtick is legitimate bead text.

## Decision Outcome

`no_corrupting_text` scans the four body fields — description, design,
acceptance criteria, notes — for the NUL byte, and for nothing else. A backtick
passes, and no surface in `grid_assets` or `github_grid_assets` may refuse one,
strip one, or teach a refiner to avoid one. The store that files its own
workflow-run beads writes its falsifier as a code span again, because a
falsifier is a command.

The unit table stays a MAP rather than collapsing to a single constant: the
class is open, and a unit joins it when it is SHOWN to corrupt the write. Two
sibling rules from the same prose family stay JUDGEMENT and are not mechanized
— that a validation plan fits the critic lane's runtime cap, and that it covers
every consumer the changed API reaches — because neither is decidable from bead
text alone.

### The completeness lane is bounded by KIND, not by a count

`power_station#pre-stamp-advisory-reuses-readiness-and-discovery` records, of
the surface this row joins: *"No requirement is minted. `FilingRequirement`
still carries exactly its ten values, with unchanged wire names and order."*
That entry stays in force, and this is what amends it: the count is now eleven.

The boundary that entry protects is not the number. It is that
`FilingReport.requirements` carries only checks a machine decides the same way
every time, and that a judgement an LLM makes rides its own member
(`FilingReport.advisory`) and never reads as a row. `no_corrupting_text` is on
the mechanical side of that line by construction — it gathers nothing, reads no
`FilingEvidence`, spawns no inference, and answers identically under
`FilingEvidence.unavailable` and under a complete live gather. It joined
`requirements` in wire order, last, and the rows before it kept their wire
names and their order.

So a deterministic row may still be minted beside the ten. A judgement may not.

### Confirmation

`packages/grid_assets/test/filing/filing_contract_test.dart` states the eleven
wire names explicitly rather than deriving them from the enum, so a rename or a
reorder fails; it fails one NUL in each of the four fields identically under
both evidence postures, and it passes a bead carrying a code span in every one
of them. `packages/grid_assets/test/filing/filing_viability_test.dart` runs all
eleven rows over three checked-in live-bead snapshots, two of which write
ordinary code spans, and requires every row to pass.
`packages/grid_assets/test/assets/skill_assets_test.dart` asserts each overlay
leg independently: it requires the emitted NUL refusal and its correction, and
fails a leg that still asks a refiner to remove backticks.

### Consequences

* Good, because the refusal is exactly as wide as the corruption. No correct
  bead is held, and the one failure that is invisible at filing time is refused
  at filing time.
* Good, because bead prose keeps the code span, which is how a reader — human
  or agent — tells a symbol from a word.
* Bad, because the heredoc hazard that motivated half the rule is now covered
  by nothing mechanical. It is a property of how a write is made, so it lives
  in the write recipe on the governor disc and can still bite a writer who does
  not follow it.
* Bad, because the prose family is not finished: two sibling rules remain
  remembered, and a remembered rule binds only the agent who reads it.
