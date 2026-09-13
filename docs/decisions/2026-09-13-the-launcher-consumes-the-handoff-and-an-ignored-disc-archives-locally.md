---
status: accepted
date: 2026-09-13
decision-makers: ["Nico Spencer"]
consulted: []
informed: []
register:
  spec: 1
  slug: the-launcher-consumes-the-handoff-and-an-ignored-disc-archives-locally
  surfaces:
    - "packages/grid_assets/lib/src/seat/**"
    - "packages/grid_assets/extension/station_overlay/**"
  obsoletes: []
  updates:
    - handoff-succession-commits-before-consume
  obsoleted-by: null
  updated-by: []
  bead: pow-d5ol
  legacy-id: null
---

# The launcher consumes the handoff, and an ignored disc archives locally

## Context and Problem Statement

`handoff-succession-commits-before-consume` made the archive a precondition of
the destruction and gave the successor a verb to run. Both halves leaked.

The verb was instructions, and instructions were skipped: `pow-jhmu` counted
FOUR sessions that read a handoff and never consumed it, so the next successor
found a note describing a board two shifts old. The fourth instance failed for
a different reason, and it is the one that cannot be fixed by asking harder —
measured 2026-09-13 on the live station:

```
succession: governor — REFUSED: could not stage the disc — git add -A --
.grid/seats/governor failed: The following paths are ignored by one of your
.gitignore files: .grid/seats
```

lunar_station had gitignored its seats tree at 7b225e8, deliberately, for the
PII an Agent Disc accretes. The premise the whole ritual rests on — "the disc
is tracked, so git history is the archive" — is not merely unheld on such a
station, it is UNHOLDABLE: the only route from an ignored path into history is
`git add -f`, which commits exactly the material the ignore exists to keep out.
Every succession on that station refused, and every handoff stayed on the disc.

## Decision Outcome

**The LAUNCHER consumes.** `seat`'s relaunch loop performs the succession
itself before it primes a child: archive, prove the archive, delete the note
and its one `MEMORY.md` pointer line, then hand the successor the body it just
consumed. A successor therefore cannot start unprimed and cannot skip the
consumption, because neither is a step it performs. A succession that REFUSES
stops the launch — no child is started over an unresolved disc, where it would
write a second note beside the first. The `succession` verb stays as the
by-hand RECOVERY path: a disc no launcher touched, or one carrying two live
handoffs, which still refuses and names both.

**The archive has TWO sinks, chosen by the disc's own tracked state**, resolved
by `git check-ignore -q -- .grid/seats/<seat>` before any mutation:

* **tracked** (exit 1) — the scoped commit of
  `handoff-succession-commits-before-consume`, unchanged, proved at `HEAD`;
* **ignored** (exit 0) — a LOCAL archive at
  `.grid/seats/<seat>/.archive/<utc-stamp>/`, holding the handoff and
  `MEMORY.md` byte-identical, proved by reading the copies back, and covered by
  the same ignore that selected it. The verb reports `ARCHIVED-LOCAL <path>`.

Anything else — a non-launch, a grid home that is no repository — is "couldn't
tell", and a run that cannot name the archive it would delete into deletes
nothing.

`git add -f` is used on no path, in neither sink. That is the whole point of
the fork: an ignored disc is ignored for a reason, and forcing it into history
would trade a lost handoff for leaked PII.

**`/clear` is retired as a handoff path.** A seat hands off by ENDING: write
the note, say one line, exit. The launcher relaunches. The vended `handoff`
skill carries exactly one signal line and no in-place option, and its Resume
section tells the successor the consumption already happened.

This UPDATES `handoff-succession-commits-before-consume` at one clause. The
archive precondition stands: nothing is destroyed until it is proved archived.
What changes is WHO establishes it — the launcher, not the successor — and
WHERE it lands when the disc is ignored.

### Consequences

* Good, because the consumption is no longer an instruction a tired context can
  skip: a successor that exists at all has already been primed by a consume.
* Good, because a station may ignore its seats tree for PII and still hand off,
  which it could not do at all between 7b225e8 and this landing.
* Good, because the two sinks are decided by a probe rather than by a flag, so
  no seat has to know which kind of disc it sits on.
* Bad, because a local archive accumulates under the disc where git history
  would have folded it away, and nothing prunes it yet.
* Bad, because a refusing succession now blocks the launch rather than only the
  resume — a disc with two live handoffs stops the seat until a human rules.

### Confirmation

`packages/grid_assets/test/seat/seat_command_test.dart` pins the launcher's
consumption on both sinks, the single relaunch, and that `git add -f` is
invoked on no path; `test/seat/succession_command_test.dart` pins the local
archive's byte-identical copies and the three `check-ignore` answers;
`test/assets/handoff_skill_test.dart` pins the one signal line, the absence of
`/clear`, and the Resume section's statement that the launcher consumed.
