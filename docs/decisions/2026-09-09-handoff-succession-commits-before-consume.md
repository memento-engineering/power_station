---
status: accepted
date: 2026-09-09
decision-makers: ["Nico Spencer"]
consulted: []
informed: []
register:
  spec: 1
  slug: handoff-succession-commits-before-consume
  surfaces:
    - "packages/grid_assets/lib/src/seat/**"
    - "packages/grid_assets/extension/station_overlay/**"
  obsoletes: []
  updates:
    - the_grid#agent-disc-file-shape-and-home
  obsoleted-by: null
  updated-by: []
  bead: pow-g2mi
  legacy-id: null
---

# Handoff succession commits the disc before it consumes the note

## Context and Problem Statement

`the_grid#agent-disc-file-shape-and-home` rules that a handoff is working
memory and that "the successor DELETES it in the turn that reads it", and it
licenses that destruction with one premise: "The disc is tracked, so git
history is the archive." The vended `/handoff` skill carried the rule into a
ritual — read the newest note, act on its **Resume here**, delete the file and
its `MEMORY.md` pointer line — and nothing anywhere enforced the premise.

Observed 2026-09-09 on a live grid home: the refiner seat's disc was twelve
UNTRACKED files, the live handoff about to be consumed among them, while the
governor disc beside it carried forty-six tracked ones. The `.gitignore`
negation that re-opens the seats tree was present and correct; nothing had
ever run `git add`. A successor following the ritual literally would have
destroyed the only copy of the note it had just read — and because the ritual
is performed in the SAME turn that read it, there was no natural moment to
notice.

The premise was therefore load-bearing and unheld. Nico, on being shown it:
"commit the disc and delete... this should be a part of the workflow and
should be baked into the cli commands. we can have a --no-destructive flag or
something."

## Decision Outcome

A `succession` verb owns the consume half, beside `prime` and `seat` in the
SEAT command set, and the vended skill CALLS it instead of performing the
delete by hand. The mechanics bind in this order, and a failure at any rung is
a loud refusal that destroys nothing:

1. **Resolve exactly one live handoff** off the disc, reusing `SeatDisc`'s own
   ordering. Zero is a named no-op that invokes no git at all. More than one
   REFUSES and names every candidate: two live handoffs mean a succession was
   skipped, only the newest describes the board, and which is which is a
   condition a human must see, not one the verb papers over.
2. **Resolve exactly one `MEMORY.md` pointer line** whose Markdown link target
   equals the candidate's basename. Zero would orphan an index line; two would
   make the verb guess.
3. **Commit only the seat-disc path**, and only when the tree is dirty, with
   `git add -A -- .grid/seats/<seat>` then `git commit --only -- <same>`. A
   grid home is a live checkout: an unscoped `git add -A` would sweep the
   operator's unrelated work into an archive commit, so unrelated staged paths
   stay staged and outside it.
4. **Prove the archive** before anything is destroyed: both consumed files must
   be present at `HEAD` and byte-identical to the working copy. Presence alone
   is not enough — a commit rejected by a hook or a signature can leave an
   OLDER copy of the note at `HEAD`, and deleting into that loses the bytes
   that were read.
5. **Re-resolve the disc** and refuse a sibling written during the commit
   window, naming both. A race is the same skipped succession as an initial
   two.
6. **Consume**: remove the one pointer line, preserving every other byte, then
   delete the note. Under `--no-destructive` the run stops after rung 5, exits
   0, changes no file, and names the path it WOULD have deleted — the safe
   first run on an unfamiliar disc, and the escape hatch for a seat that wants
   the archive without the destruction.

The work-tree-ROOT guard and the fail-closed dirty gate are NOT re-derived
here: they are `GitOps`'s, already used three times in this package, and the
verb composes that layer. Only the pathspec-scoped mutations and the two
archive proofs — which `GitOps` exposes no public method for — ride the
injected `GitRunner` directly, and they run only after that gate has cleared
the root guard on the same working directory.

This UPDATES `the_grid#agent-disc-file-shape-and-home` at exactly one clause.
The delete-on-consume rule stands unchanged, and so does "there is no archive
directory" — a consumed handoff is still destroyed, and still archived only by
git history. What changes is that the archive is now a PRECONDITION the verb
establishes rather than an assumption the ritual inherits. The disc's file
shape, its home, its front matter and its index line are untouched.

The verb owns the MECHANICS only. What a handoff says, when one is written,
and the one line handed to the outer harness stay with the `/handoff` skill;
this moves no judgement into code.

### Consequences

* Good, because the destruction can no longer outrun the archive: on an
  untracked disc the verb commits first, and on a disc it cannot prove at
  `HEAD` it refuses and deletes nothing.
* Good, because `--no-destructive` makes the whole ritual previewable, and a
  successor priming into an unfamiliar seat can see the refusals before it can
  lose anything.
* Bad, because a successful destructive consume leaves its own deletion
  uncommitted — the archive commit precedes it, so the removed note and
  pointer line ride the disc's NEXT commit rather than this one.
* Bad, because two live handoffs now stop the resume until a human rules on
  them, where the old ritual silently deleted the older note unread.
