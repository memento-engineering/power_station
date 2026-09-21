---
status: accepted
date: 2026-09-18
decision-makers:
  - "Nico Spencer"
  - "agent"
consulted:
  - "governor"
informed: []
register:
  spec: 1
  slug: a-clipped-decision-entry-keeps-its-front-matter-and-decision-outcome
  surfaces:
    - "packages/grid_assets/lib/src/code/discovery.dart"
  obsoletes: []
  updates:
    - "discovery-evidence-is-gathered-once-and-projected"
  obsoleted-by: null
  updated-by: []
  bead: pow-ojex
  legacy-id: null
---

# A clipped decision entry keeps its front matter and its Decision Outcome

## Context and Problem Statement

`discovery-evidence-is-gathered-once-and-projected` bounds every foreign
evidence record at `kMaxDiscoverySnippetChars` (4,096 characters) and records
the clip as `truncated`. The clip kept the HEAD of the text. For a MADR
decision entry the head is front matter, title and Context. The part a lens
judges alignment against is `## Decision Outcome`, and it comes last.

Measured on 2026-09-15, the round for pow-07zx held at the discovery evidence
gate. The `explore-decision` lens needed clause 2 of
`power_station#a-mechanical-lookup-is-a-vended-command-with-a-bounded-output`.
That entry is 7,833 bytes, and its `## Decision Outcome` starts at byte 3,011,
so the head clip ended partway through clause 1. The re-gather cannot change a
deterministic clip, so the round held on every attempt. On that date 60 of 100
power_station entries and 54 of 141 the_grid entries were over 4 KiB. Any bead
governed by one of them could hold the same way.

Nico ruled on 2026-09-17 that the clip becomes section-aware for decision
entries. This entry records that ruling and the details settled while building
it.

## Considered Options

* Keep the head clip and let the lens narrate the truncation.
* Clip around the `## Decision Outcome` section, as the heading-bounded MADR
  section.
* Treat everything from `## Decision Outcome` to the end of the file as one
  load-bearing region.

## Decision Outcome

Chosen option: **clip around the `## Decision Outcome` section.** It applies
only to a `decision-entry` record over the bound. Every other evidence kind
keeps the head clip.

* **The kept regions.** The YAML front matter, from the opening `---` line to
  the closing one, is kept whole. It is the entry's identity: slug, status,
  surfaces and edges. The `## Decision Outcome` section is also kept whole,
  from its line-start heading to the next level-two heading or the end of the
  file. That includes an in-section `### Consequences`.
* **The spare budget.** It is filled from the top of the text between the two
  regions (title, Context, Considered Options). Anything left then fills from
  the top of any sections after the Outcome. Some entries in this register
  split their ruling across level-two sections after `## Decision Outcome`.
  They keep as much of that text as fits, and the budget is not left unused.
* **When the Outcome does not fit.** If front matter plus the whole Outcome
  exceeds the bound, the middle is dropped. The Outcome keeps its heading and
  prefix, and only its tail is clipped. The head of the file is never what
  gets cut.
* **The marker.** One marker sits directly above `## Decision Outcome`. It
  names what was kept and what was withheld. It also says how to get the rest,
  as `a-mechanical-lookup-is-a-vended-command-with-a-bounded-output` clause 2
  requires: the canonical evidence id, whose digest is the complete body's,
  and the entry file to read it from. The layout reserves room for the longest
  marker the case could need, so the snippet never exceeds the bound. The
  marker never names a clip that did not happen.
* **Unrecognized shapes.** A long entry without both regions keeps the head
  clip, because this rule does not invent section boundaries. Examples are an
  amendment-style entry with no `## Decision Outcome`, or a body with no front
  matter.

Nothing else in `discovery-evidence-is-gathered-once-and-projected` changes.
There is still one gather. The digest still covers the complete body. The
record stays `truncated`, and that state is still context, not a
deterministic gap.

### Consequences

* Good, because a lens asked to judge a long entry now reads its ruling rather
  than its preamble. A clipped body can no longer hold a round by
  construction.
* Good, because the marker makes each clip recoverable. The reader is told
  what is missing and where the complete entry lives.
* Bad, because the Context of a long entry is now the part that gets cut. A
  lens that needs the reasoning behind a ruling rather than the ruling must
  follow the marker to the file.
* Bad, because the section rule is heading-literal. An entry that titles its
  ruling differently keeps the head clip until it adopts the MADR heading.
