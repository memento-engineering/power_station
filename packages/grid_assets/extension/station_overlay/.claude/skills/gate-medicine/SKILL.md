---
name: gate-medicine
description: >
  Diagnose and clear gated the_grid sessions: read the worktree critique
  artifacts, separate systemic failures from genuinely bad work, and re-arm
  with a rework round — never a bare gate-close. Use when a session parks at
  review/route, when gate beads open in the state store, when several sessions
  gate at once, or when sessions and gates look stuck, orphaned, or duplicated.
compatibility: Requires dart + the `{{runner}}` runner, bd (beads CLI), git.
metadata:
  author: memento-engineering
---

# Gate medicine

A gate bead (`issue_type: gate` in the STATE store) parks one session node —
`blocks: <session>`, `node: <bead>/review/route`, `reason` from the route. The
evidence lives in the work bead's WORKTREE.

## Read the artifacts first

```
<work repo>/.grid/worktrees/<substation>/<bead>/.grid/critique/
  code-validation.rc     # the gating lane's exit code (the ONLY hard block)
  <rubric>.json          # per-critic verdicts: grade + rationale
<same>/.grid/telemetry/  # per-lane harness usage
```

Read the rationales, not just grades — critics write specific, checkable
claims (files, commits, test names). Verify the load-bearing ones.

## Triage

- **`rc` non-zero + the bead has NO `validation_plan` metadata** → the
  plan-less default (`false`) — an intake miss, not bad work. Stamp the plan
  (see `intake-grooming`), verify it, rework.
- **`rc` non-zero + a real plan** → run the plan yourself in the worktree.
  Environment failures (unresolved deps → bridge `pubspec_overrides.yaml`
  into the worktree; it is gitignored, safe) are yours to fix; genuine red is
  the agent's — rework with the failure as the note.
- **Bad grades with substantive rationales** → judge them. A C/F whose
  rationale names a concrete gap becomes the rework note verbatim.
- **Several sessions gating simultaneously with the same reason** → systemic
  (infrastructure, not four bad agents). Find the common cause before touching
  any single session.
- **A-range grades on a bead whose branch has ZERO commits past origin/main**
  → the critics graded pre-existing mainline work (`git log origin/main..HEAD`
  in the worktree is the truth). That is a stale bead — close it with
  receipts, not a rework.

## THE doctrine: gate-close re-arm is a trap

Closing a gate bead re-arms ONLY the parked route node. Its critic lanes stay
`complete` with their old artifacts on disk, so the route re-joins the SAME
stale data and re-gates immediately — the critique dir's unchanged mtimes are
the tell. The only fresh-round path is the rework re-key:

```
./{{runner}} rework <bead-id> \
  --grid-root {{gridHome}} --prefix <state-store prefix> \
  --note "<honest operator finding>" --note-root <work repo root>
```

This retires the session (`work_bead → <bead>#rN`), and the fresh round's new
node paths make the freshness stamps reject every stale verdict. Rules:

1. **Verify the validation plan runs GREEN in the worktree yourself BEFORE
   firing rework** — otherwise the fresh round burns an agent to rediscover
   your environment problem.
2. **Write honest notes.** If the work stands, say so ("round 1 gated on
   mechanics, not your work; committee graded B/A/A; verify and finish") — the
   fresh agent reads it and no-ops instead of rewriting good code. If a critic
   found a real gap, quote it.
3. Rework caps at ~3 rounds and refuses a LIVE (open, non-gated) session —
   both refusals are loud and correct.

## Hygiene sweeps (after any rework wave)

- **Moot gates:** a gate whose `blocks` session is closed/retired stays open —
  close it with a reason, or the watch alarms forever.
- **Straggler gates:** the stale route can fire once more in the window
  between a gate-close and the re-key, minting a fresh gate on the retired
  session. Same treatment.
- **Duplicate gates:** two open gates for one (session, node) is a known
  mint-dedup race — close both, note it.
- **Orphaned sessions:** a work bead closed while its session sat gated leaves
  the session open forever (the unmount races the scope's terminal close).
  Close it manually with a reason.

## Gotchas

- The gate reason ("code-validation failed: hard block") is generic — the `.rc`
  and the bead's metadata tell you WHICH failure it was.
- Stamping `validation_plan` on the work bead does not reach an
  already-running round; it applies from the next fresh round.
- Session/gate writes belong to the state store only; the work bead takes at
  most a notes append (the rework `--note`).
