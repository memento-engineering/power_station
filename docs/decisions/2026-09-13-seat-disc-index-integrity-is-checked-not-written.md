---
status: accepted
date: 2026-09-13
decision-makers: ["Nico Spencer"]
consulted: []
informed: []
register:
  spec: 1
  slug: seat-disc-index-integrity-is-checked-not-written
  surfaces:
    - "packages/grid_assets/lib/src/seat/**"
  obsoletes: []
  updates:
    - the_grid#agent-disc-file-shape-and-home
  obsoleted-by: null
  updated-by: []
  bead: pow-jd9g
  legacy-id: null
---

# Seat disc index integrity is CHECKED, never written

## Context and Problem Statement

`the_grid#agent-disc-file-shape-and-home` makes `MEMORY.md` the disc's index —
"one pointer line per file ... it is the only thing that is loaded wholesale;
the files themselves load on relevance" — and then rules the machinery out:
"Lint is front-matter presence only: no JSON schema, no index code, no
generator," repeated in its non-goals as "no disc lint beyond front-matter
presence; no index code."

That left the index with no owner on the write path. Every seat hand-edits it.

The cost came due on 2026-09-12 at 06:24 CDT. The governor seat banked ONE
lesson and its index went from 77 pointer lines to 1. Commit 72d4d92 in the
lunar_station grid home records it exactly — `.grid/seats/governor/MEMORY.md`,
1 insertion and 78 deletions, hunk header `@@ -1,79 +1,2 @@`. The disc title
line went with them. Nothing external did this: the seat rewrote its OWN index
wholesale while appending one entry, the same replace-where-append-was-meant
failure the house already knows from `bd --notes` versus `--append-notes`, on a
different surface.

The note FILES survived. That disc held 81 markdown files and the index named
2. Seventy-nine banked lessons were on disk and unreachable, because the index
is the only thing that makes a disc note findable. The loss was silent —
nothing failed, nothing warned, and it was found by accident four hours later.

`power_station#handoff-succession-commits-before-consume` does not cover this.
It commits and proves the disc before a destructive CONSUME; here the entries
were gone long before any succession ran. The gap is the BANK path.

## Considered Options

* **An integrity check.** Assert the index covers the notes: every persistent
  note has exactly one pointer line, and every pointer line resolves to a file.
  Cheap, and it catches every cause — a wholesale rewrite, a hand edit, a bad
  merge — because it reads the result rather than intercepting the write. It
  does not prevent the write.
* **A vended append-only bank verb.** A seat calls a verb that writes the note
  and its pointer line atomically and append-only, so no seat hand-edits the
  index. Removes the class, but only for the seats that call it; a hand edit
  still bypasses it.

They are complementary rather than exclusive, so the question was only which
ships first.

## Decision Outcome

The **integrity check** ships, and it ships alone. Nico's ruling of 2026-09-12,
in substance: the check catches every cause including the hand edit and the bad
merge, and it is the only one of the two that would have caught the 06:24 loss;
the verb removes the class only for seats that call it. The fork is closed.

`SeatDisc.verifyIndexIntegrity` is that check, and it binds these terms.

1. **The invariant is COVERAGE, both ways.** Every persistent note on the disc
   is named by exactly one pointer line, and every pointer line names a file
   that is on the disc. Zero pointer lines is the 06:24 loss; two is an index
   that has drifted and a note the succession verb can no longer consume; a
   target that resolves to nothing is a line a reader cannot follow.
2. **It REPORTS, it never repairs.** The check runs after the write, which is
   exactly why it sees a wholesale rewrite, a hand edit and a bad merge alike.
   It creates, appends to, renames and deletes nothing — including the index it
   just faulted. A drifted index is a condition a human rules on, and a check
   that quietly re-derived the index would destroy the evidence of what wrote
   it.
3. **It is LOUD and it names every offender.** One `SeatDiscIntegrityException`
   thrown after the whole scan, carrying the uncovered notes, the unresolvable
   targets and the doubly-named notes in three sorted fields. Naming only the
   first offender is precisely how seventy-six of seventy-seven lost pointer
   lines stay invisible.
4. **`kind: handoff` is EXEMPT from the coverage count.** A handoff is working
   memory, indexed for exactly one succession and deleted in the turn that
   reads it. The one-pointer-line rule for a handoff already belongs to
   `power_station#handoff-succession-commits-before-consume`, which holds it at
   the moment it consumes it. An absent index is EMPTY rather than an error, so
   a disc holding only a handoff, or nothing at all, verifies.
5. **No bank verb is built.** The append-only writer is successor work, and only
   if hand-editing proves recurrent — that is, if the check starts reporting
   drift that the discipline alone does not stop. Until then the seats keep
   writing their own index, and this check is what makes a mistake audible.

### What this narrows in the updated entry, and what it does not

This UPDATES `the_grid#agent-disc-file-shape-and-home` at two clauses and no
others. "No index code" and "no disc lint beyond front-matter presence" now
read: no code WRITES the index, and the only check beyond front-matter presence
is this read-only coverage assertion. The premise the disc doctrine already
carries — that the index is the sole path to a note — is what forces it.

Everything else in that entry stands untouched. One non-binding fact per file
with its front matter; the index's name is still `MEMORY.md` and its grammar is
still `- [Title](file.md) — hook`, one disc-local pointer per line; the harness
still loads that index at session start and the notes on relevance, with no
projection; harness-written front matter is still tolerated and never linted;
a handoff is still destroyed on consume with git history as the only archive.
Nothing here injects the disc or disc-recording instructions per session, adds
a hook, or touches the graduation path.

Restoring the governor's own index is NOT part of this: the 77-line version is
recoverable from 13f7f93 in that grid home and the notes were never deleted,
but that disc belongs to the governor seat and the station is live, so recovery
is the operator's call.

### Consequences

* Good, because the loss stops being silent: the one condition that makes a
  banked lesson unreachable is now a named, loud refusal instead of a diff
  nobody read.
* Good, because it catches causes a bank verb cannot — a hand edit, a bad merge,
  a `git checkout` that resurrects an old index — since it asserts the result
  rather than owning the write.
* Bad, because it does not PREVENT the write. A seat can still drop 76 pointer
  lines; the check only guarantees the next verification says so, and how soon
  that runs is a scheduling question this entry does not answer.
* Bad, because the index grammar is now load-bearing in code: an index line
  whose target leaves the disc — a URL, a path with a directory part — is
  reported, so a seat that wanted a non-pointer link in `MEMORY.md` has to put
  it somewhere else.
