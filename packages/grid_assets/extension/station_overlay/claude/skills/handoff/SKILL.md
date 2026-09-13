---
name: handoff
description: >
  Write the seat's own handoff onto its Agent Disc, bank the durable learnings,
  and tell the OUTER harness what to do next — never end a session blind.
  One ritual, two requesters: the HUMAN types /handoff [slug], or the AGENT
  self-initiates at a boundary (a long context, a natural task end, before a
  bounce or a harness upgrade, or when told "take a beat, then hand off"). Use
  at a session boundary — and use its Resume section as the SUCCESSOR, whom
  the launcher has already primed with the note it consumed.
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

A handoff is WORKING MEMORY — written once, picked up, and deleted within
minutes. That is its whole lifetime: a hypertemporal artifact that lives exactly
one succession. It is NEVER amended. If the board moves again, you have not
handed off yet — the next note is authored at the next boundary, not bolted onto
this one, because a note rewritten across a shift has no single author moment
and its own timestamp stops being true. The write verb REFUSES a second live
handoff, so this is a constraint and not only advice.

It is a disc note of `kind: handoff`, and its file shape, its home, its index
line and the delete-on-consume rule are all fixed by
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

## 2. WRITE the handoff onto the disc — ONCE

Compose all ten sections below IN FULL first, in your own context. Resolve
nothing and write nothing until the last one is final: the write is one
operation, and there is no second one to fix it with.

Then resolve the stamp exactly once:

```
date -u +%Y%m%dt%H%M%Sz
```

`<utc-stamp>` is that ONE value — kebab-safe, and it sorts. Substitute it into
the front-matter `name`, into the file name, and later into the index pointer
line; reading the clock again would leave the three disagreeing.
`<slug>` is the human's argument, or three kebab words naming the thread.

One file, on your own seat's disc:

```
<grid home>/.grid/seats/<seat>/handoff-<utc-stamp>-<slug>.md
```

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
   encoded: bead id WITH its title, dep edge, register entry (slug and title),
   disc note. A ruling recorded
   nowhere else dies with this file.
3. **Board state** — a table of ids by store with state, ONE line each, and
   the bead TITLE next to every id (`lenny-96sa — leonard_grid_assets: convert
   the sample suite …`), never the id or slug alone: the successor and the
   human read this on a phone and cannot open a store to decode an id. Gates
   name the bead they block by id and title; decisions name the entry title
   next to the slug. Read it, never remember it:
   `{{runner}} status --state-workspace <grid home>`, then
   `bd -C <store root> list --status=in_progress`.

   Before writing `empty by design`, repeat the Sweep enumeration for every
   stamped-but-unmounted bead across both blocker sources and inspect each
   open blocker's type and notes. The board is empty by design only when that
   OPEN-blocker enumeration is empty; otherwise record every blocker, putting
   each release node or explicit agent-executes blocker in a **GOVERNOR WORK**
   row with its id, title, owning store, and next executable action, and only
   genuine human blockers in human-gate rows.
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

### Then write it, through the verb

Send the COMPLETE note — front matter and all ten sections — on stdin, in ONE
operation:

```
{{runner}} succession <seat> --grid-home "<grid home>" --write-handoff "handoff-<utc-stamp>-<slug>.md"
```

`HANDOFF WRITTEN <path>` is the only success, and it earns the index line in
step 4. The verb writes the note and nothing else.

`REFUSED` means the disc already carries a live handoff. Change NOTHING — not
that file, not the index, not this note under a second name. Read the live
note, recover the disc through the succession verb below, and author yours at
the next clean boundary. Never edit an existing handoff file, never append to one,
and never write a second one beside it.

## 3. BANK the durable learnings

A fact that outlives one succession is not a handoff section — it is its own
disc note (`kind: lesson`, `kind: receipt`, or `kind: observation`), one fact
per file, in the same front matter. Those, plus `kind: handoff`, are the WHOLE
set: there is no fifth kind and no mid-shift channel, because a checkpoint IS
a handoff, cycled fast. Write the durable notes FIRST, then name them in
**Ready**.
Never bank by pasting the handoff: the handoff is deleted on consume, so a
fact that lives only inside it dies with it.

Long-term memory stays THIN. Beads, decisions and trajectories already hold
durable knowledge about this system, its stations and its substations, and each
one is queryable on demand at no standing cost — so a disc note that duplicates
what one of them already holds is deleted, not kept. Bank what the on-demand
surface cannot answer.

## 4. INDEX it

ONLY after `HANDOFF WRITTEN`, append ONE pointer line to
`<grid home>/.grid/seats/<seat>/MEMORY.md`:

```
- [Handoff <stamp> — <slug>](handoff-<utc-stamp>-<slug>.md) — <hook>
```

Append it; never rewrite the index around it. The harness loads that index at
session start, so a successor finds the handoff even where no hook is
installed. After a `REFUSED` write there is no line to add: the index describes
the disc, and nothing was written.

## 5. SIGNAL the outer harness — one line, then end the turn

You cannot restart yourself in any harness we run, so the signal goes UP — and
there is exactly ONE of it. End the turn with this line, and say nothing after
it:

- `Handoff written: <path>; exit, the launcher relaunches this seat.`

Then EXIT — `/exit`, or the turn simply ending under the launcher. Exiting IS
the handoff: the launcher consumes the note, primes the successor with it, and
brings the seat back. There is no in-place path. A compacted or cleared context
is the SAME occupant carrying on, not a successor, so neither one hands off.

The launcher itself is the prime/launcher bead's deliverable, not this skill's.
This skill composes the note, routes it through the write verb, and says the
line.

There is no `PreCompact` guard. The only archive a handoff gets is the one the
launcher writes before it deletes: git history when the disc is tracked, and
`.grid/seats/<seat>/.archive/<utc-stamp>/` when git IGNORES the disc.

## Resume — the successor's side of the same ritual

You are the successor, and the launcher has ALREADY CONSUMED the note that
primed you. Before this session existed it archived the disc, PROVED the
archive, and deleted the handoff and its one `MEMORY.md` pointer line — the
body you were primed with IS that note. There is nothing on the disc to consume
and no verb to run.

1. Act on its **Resume here**, starting at step 1 VERBATIM.
2. Take over what it NAMED: the worktrees, branches, locks, resident process
   and open PRs under **In flight** are yours now.
3. Write your OWN note at your own boundary. Never amend the one you were
   primed with — it no longer exists.

Where the launcher put the archive follows the disc's tracked state: a scoped
`chore(seat): archive <seat> disc` commit when the disc is tracked, or
`.grid/seats/<seat>/.archive/<utc-stamp>/` when git ignores it — the seats tree
is ignored wherever a disc carries PII, and `git add -f` is never used to force
it back into history.

`{{runner}} succession <seat> --grid-home "<grid home>"` stays as the
HAND-RECOVERY path only: a disc no launcher touched, or one carrying two live
handoffs. Two ALWAYS refuse, in either form, and the verb names both — two on
one disc mean a succession was skipped, only the newest describes the board,
and which one that is stays a human's call. `--no-destructive` does everything
except the deletion and names what it WOULD have deleted. Either form first
reports the AGE of every unconsumed handoff on the disc — `Agent Seat "<seat>"
has unconsumed handoff <path> on its Agent Disc — age 9h 0m.` Nothing expires
on account of it: a note that has sat for hours is a succession that did not
happen.
