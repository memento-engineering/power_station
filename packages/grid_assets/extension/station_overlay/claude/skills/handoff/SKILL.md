---
name: handoff
description: >
  Write the seat's own handoff onto its Agent Disc, bank the durable learnings,
  and tell the OUTER harness what to do next — never compact or clear blind.
  One ritual, two requesters: the HUMAN types /handoff [slug], or the AGENT
  self-initiates at a boundary (a long context, a natural task end, before a
  bounce or a harness upgrade, or when told "take a beat, then hand off"). Use
  before compaction, clear, or relaunch — and use its Resume section as the
  SUCCESSOR, which consumes the newest handoff and deletes it.
compatibility: >
  Requires a seat whose Agent Disc is `<grid home>/.grid/seats/<seat>/`, the
  `{{runner}}` runner, bd (beads CLI), and git.
metadata:
  author: memento-engineering
---

# Handoff

The auto-summarizer guesses what mattered. You KNOW. However the event was
raised, it ends the same way: a curated note on your seat's disc, durable
learnings banked separately, and ONE line telling the outer harness what to do
next.

A handoff is WORKING MEMORY — a hypertemporal artifact that lives exactly one
succession. It is a disc note of `kind: handoff`, and its file shape, its home,
its index line and the delete-on-consume rule are all fixed by
`the_grid#agent-disc-file-shape-and-home`.
This skill invents no shape. A handoff never graduates, and never goes near a
decisions register.

## 1. SETTLE

Before you write a word:

- Finish or park every in-flight tool call. Nothing half-written — no dangling
  `bd` write, no half-applied edit, no unpushed commit the human does not know
  about.
- NAME every resource this seat owns: worktrees, branches, locks, the resident
  process, open PRs. The successor inherits them and cannot see them.

## 2. WRITE the handoff onto the disc

One file, on your own seat's disc:

```
<grid home>/.grid/seats/<seat>/handoff-<utc-stamp>-<slug>.md
```

`<utc-stamp>` is `date -u +%Y%m%dt%H%M%Sz` — kebab-safe, and it sorts.
`<slug>` is the human's argument, or three kebab words naming the thread.

The front matter is the disc's. No new keys:

```yaml
---
name: handoff-20260903t141200z-acp-thread
description: <one line; this is the recall key>
seat: <seat>
date: <YYYY-MM-DD, UTC>
kind: handoff
---
```

Then these TEN sections, in this order. Each one earned its place in a
successor's wasted hour:

1. **Header** — seat, the stamp in UTC **and** local (the CDT skew has caused
   misreads), harness + model, the trigger (human `/handoff` or
   agent-initiated, with the reason), and one sentence: what the successor is
   being brought back to do.
2. **Rulings** — what the human decided this session, and WHERE each one is
   encoded: bead id, dep edge, register entry, disc note. A ruling recorded
   nowhere else dies with this file.
3. **Board state** — a table of ids by store with state, ONE line each, names
   not just slugs. Read it, never remember it:
   `{{runner}} status --state-workspace <grid home>`, then
   `bd -C <store root> list --status=in_progress`.
4. **In flight** — what is hot and why, plus the resources SETTLE named: the
   resident, locks, worktrees, PRs waiting on a queue.
5. **Tried and failed — do not retry** — each with the reason it failed.
6. **Promises to the human** — and the status of each.
7. **Context the successor must not re-derive** — the expensive facts, with
   their receipts.
8. **Unfiled observations** — what the human said to ignore, recorded here and
   nowhere else.
9. **Resume here** — ordered steps; step 1 is executable VERBATIM.
10. **Ready** — the disc notes banked this session, by name, and an attestation
    that nothing is half-written.

## 3. BANK the durable learnings

A fact that outlives one succession is not a handoff section — it is its own
disc note (`kind: lesson`, `kind: receipt`, or `kind: observation`), one fact
per file, in the same front matter. Write those FIRST, then name them in
**Ready**.
Never bank by pasting the handoff: the handoff is deleted on consume, so a
fact that lives only inside it dies with it.

## 4. INDEX it

Add ONE pointer line to `<grid home>/.grid/seats/<seat>/MEMORY.md`:

```
- [Handoff <stamp> — <slug>](handoff-<utc-stamp>-<slug>.md) — <hook>
```

The harness loads that index at session start, so a successor finds the
handoff even where no hook is installed.

## 5. SIGNAL the outer harness — one line, then end the turn

You cannot compact, clear, or restart yourself in any harness we run. The
signal goes UP. End the turn with exactly ONE of these lines, and say nothing
after it:

- **(a) Continue in place** — `Handoff written: <path>. Run /compact now — the handoff complements the summary, it does not replace it.`
- **(b) Fresh start** — `Handoff written: <path>. Run /clear, or exit and let the seat launcher relaunch this seat.`
- **(c) Headless / launcher-driven** — `Handoff written: <path>. Turn ended for relaunch.`
  The launcher brings the seat back primed with it
  (`claude --append-system-prompt-file <path>`). WHICH run mode it relaunches
  into is the launcher's business, not this skill's.

The launcher itself, and the `SessionStart` compact-matcher hook that
references the newest handoff after an in-place compaction, are the
prime/launcher bead's deliverable — not this skill's. This skill writes the
file and says the line.

There is no `PreCompact` guard and no archive directory.

## Resume — the successor's side of the same ritual

You are the successor. Before you sweep, before you plan:

1. Read the NEWEST `kind: handoff` note on your seat's disc:
   `ls <grid home>/.grid/seats/<seat>/handoff-*.md | sort | tail -1`.
2. Act on its **Resume here**, starting at step 1 verbatim.
3. DELETE the file AND its `MEMORY.md` pointer line in the SAME turn that read
   it. The disc is tracked, so git history is the archive.

A handoff that has a NEWER sibling is deleted UNREAD, with a one-line disc
`observation` naming it: two live handoffs on one disc mean a succession was
skipped, and only the newest one describes the board.
