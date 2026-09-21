---
name: intake-refinement
description: >
  Shape work beads so a resident the_grid station can drive them: prior-art
  search before a filing is accepted, the required validation_plan metadata,
  driveable issue types, dependency wiring, flagged EITHER/OR forks, the
  deterministic filing exit check,
  grid.approved_* stamp approval via the approve verb, and reconciling a
  backlog against what already shipped in mainline. Use when filing, approving,
  re-homing, or auditing beads in any store the station arms — including "why
  won't this bead mount" and "is this backlog actually current" questions.
compatibility: Requires bd (beads CLI) and git.
metadata:
  author: memento-engineering
---

# Intake refinement

A resident station's drive set IS the ready frontier: **ready = in**. Refinement
is the only gate between a bead and a live agent, so every rule here exists
because its violation put a real agent on wrong work.

## The bead contract

Every bead intended for the station needs:

1. **A driveable type** — only `task`, `bug`, `feature`, `chore` mount.
   `epic`/`decision`/`spike`/`story`/`milestone` are organizational and are
   correctly ignored by the mount boundary (they still show in `ready`).
2. **`validation_plan` metadata** — a real `sh` command, run from the bead's
   worktree root by the review committee's gating lane:

   ```
   bd -C <work repo> update <bead> --set-metadata \
     'validation_plan=cd packages/<pkg> && dart pub get && dart analyze && dart test' \
     --actor operator
   ```

   A plan-less bead grades **F by design** (the gating lane runs `false`) and
   hard-blocks at review. `dart pub get` first — worktrees start unresolved.
   Scope it by **Scope the validation_plan to every consumer** below.
3. **Acceptance criteria** — at least one `- [ ]` checkbox a named command can
   falsify: `bd -C <work repo> update <bead> --acceptance '- [ ] <outcome>'
   --actor operator`.
4. **Deps wired the right way round** — every blocker NAMED in the description
   and WIRED. See **Wire every dependency at intake**.
5. **A description an agent can act on alone** — the agent receives the bead
   text and a worktree, nothing else. Name packages and acceptance shape.

Rows 1–4 are the PRESENCE half of the eleven rows the `filing` verb checks;
the verb also checks six VIABILITY rows over the same text — can the plan
parse, is it portable, are the paths repository-relative, do the cited ids and
decisions exist, is acceptance free of pinned releases — and one CONTENT row,
which refuses a NUL byte or a backtick anywhere in the bead's body text. Row 5
is the judgement this skill's reader owns. Never re-derive a row by reading the bead — run the
verb (**The exit check**).

## Search prior art BEFORE accepting a filing

Before accepting any new filing, search the org backlog for the work already
being tracked, from the grid home:

```bash
{{runner}} search --json "<token>"
```

Query **single tokens** (`filing`, `refiner`, `overlay`), one call per token.
The lexical leg ANDs a multi-word query, so a two-word query is the reliable
way to MISS the duplicate. Read `hitCount` and each store's `outcome`; a real
duplicate is closed against the survivor with receipts, and a near-miss is
wired as a dependency instead of re-filed.

**Why:** filing a second bead for work an open sibling already owns spends a
full agent round producing a colliding branch, and the coherence lane grades
the second bead F for duplicating its sibling.

## Scope the validation_plan to every consumer

The plan runs every package the CHANGE reaches, not just the packages the diff
edits. A changed public API in `packages/<a>` that `packages/<b>` imports means
BOTH packages are in the plan:

```
validation_plan=cd packages/<a> && dart pub get && dart analyze && dart test && cd ../<b> && dart pub get && dart analyze && dart test
```

**Why:** a plan scoped to the diff's own package goes green while the consumer
no longer compiles; the break surfaces at the NEXT bead's `pub get`, after the
PR merged.

## Wire every dependency at intake

A blocker is a DECLARATION bd holds. Writing `Blocked by: <id>` in the
description declares NOTHING — it is a sentence, and nothing reads it. Wire the
row, or the bead is not blocked.

- **Local (same store)** —

  ```bash
  bd -C <store root> dep add <blocked bead> <blocker bead> --actor operator
  ```

  The BLOCKED bead is the first argument. The `filing` verb's `dependencies`
  row is a PROJECTION of the rows bd holds for the bead — it reports them and
  reads no prose.
- **Cross-store** — never a raw foreign id in a local dependency row: a
  cross-store blocker is bd's OWN `external:<project>:<capability>` dependency
  row on the BLOCKED bead, and the station's link verb is the sugar that writes
  it:

  ```bash
  {{runner}} link <blocked bead> --blocked-by <blocker bead>
  ```

  It labels the target `export:<target>` and runs
  `bd dep add <blocked> external:<project>:<target>`, where `<project>` is the
  target substation's ROSTER NAME. It mints no bead and never touches the
  station's state store. The edge LIFTS when the target ships —
  `bd ship <target>` on a CLOSED target — so there is nothing to unwire by
  hand. `{{runner}} link ls` lists the external rows the roster's stores carry.

  **Know this before you wire one.** `filing` and `approve` resolve
  `<project>` against the armed roster the STATION composing them passes in,
  and no station threads that roster yet. Until one does, every `external:`
  row refuses both verbs with `no station roster was supplied` — a COMPOSITION
  gap, not a bead defect. Wire the row anyway: an unwired cross-store blocker
  is the failure this whole section exists to stop, and the refusal is loud,
  named and correctable. Never delete the row to make the check pass, and
  never hand-stamp `grid.approved_*` around it.

**Why:** an unwired blocker leaves the blocked bead in `ready`, so the station
mounts it and its agent builds against an API the blocker has not shipped. A
raw foreign id in a local row is worse: `bd doctor --fix` can classify it as
orphaned and sever it silently, and the frontier resolves nothing against it.
And a blocker named only in prose is invisible to every reader that matters:
the hyphenated spelling `Blocked-by:` once read as absence, which cost a
duplicate link bead, a false P1 and a withdrawn approval in one day.

## FLAG an EITHER/OR fork — never decide it

When refinement finds two viable designs, write BOTH into the bead as a named
fork and stop:

```
FORK (author decides): (A) extend the existing service with a second mode, or
(B) mint a sibling service. NOT decided at intake.
```

Do not pick, and do not approve the bead until a human picks.

**Why:** a fork settled at intake by inference reaches the build stage looking
decided; the round is spent before the human ever sees that there was a choice.

## Stamp architecture constraints into the CHILD bead

An agent reads ONE bead: its own. A constraint recorded only in a parent epic —
the seam to extend, the package that owns the surface, the doctrine that binds
— does not exist for the child's agent. Copy every constraint that governs the
child INTO the child's own description.

**Why:** the epic said "extend the existing loader", the child said "add a
loader", the agent built a second loader, and the coherence lane graded it F.

## Repo-relative paths in every declared test list

Every path a bead names is written relative to the REPO ROOT —
`packages/grid_assets/test/assets/skill_assets_test.dart`, never a bare
`test/assets/skill_assets_test.dart` and never an absolute machine path.

**Why:** the agent's cwd is a fresh worktree root, so a bare path resolves
under whichever package it happened to enter; the declared test is "not found"
and the criterion goes unchecked.

## Point at the primitive that already exists

When the work extends something the tree already owns, write the pointer into
the bead body as `path:line` plus the relationship:

```
COMPOSE: packages/grid_assets/lib/src/filing/filing_contract.dart:880 owns the
eleven-row completeness contract — CALL it; do not add a second predicate.
```

**Why:** without the pointer the build stage re-expresses the primitive beside
the one that exists. That is the duplication the coherence lane F-grades, and
it is why this skill CALLS the `filing` verb instead of carrying a completeness
checker of its own.

## Two checks the verb deliberately does NOT make

Both stay YOURS, and both are real. They are not `filing` requirements because
neither is decidable from the bead's text:

- **The validation_plan must finish inside the critic lane's ~600 second cap.**
  A plan that overruns latches failed, mints no gate, and strands the session
  invisibly. Duration needs EXECUTION or an estimate — a lint that guessed it
  would refuse legitimate work — so keep plans bounded (name the suites, never
  a whole-repo sweep) and time a long one before filing.
- **The validation_plan must cover every affected consumer.** See **Scope the
  validation_plan to every consumer**. Identifying every consumer is a
  judgement about the BLAST RADIUS of a change, not a mechanical lookup, so it
  is the refiner's and not a lint's.

## The exit check — `filing` is the oracle, and it is a COMMAND

Refinement EXITS on the verb, never on a reading. From the grid home (the verb
resolves the owning store by the id's prefix):

```bash
{{runner}} filing --json "<bead>"
```

The verb takes no `--state-root`: the `dependencies` row is a projection of the
dependency rows the WORK store's own bd holds, and it reaches no second store.
`park` and `show` still take the option, because they reach the grid home's
session-lifecycle beads.

The report is one JSON object: `{id, passed, requirements, error?}`.
`requirements` carries exactly eleven rows, in order — `driveable_type`,
`validation_plan`, `acceptance_criteria`, `dependencies`,
`validation_plan_syntax`, `validation_plan_portability`, `repo_relative_paths`,
`bead_references`, `release_versions`, `decision_references`,
`no_corrupting_text` — each `{requirement, passed, detail}`. `passed` is true
only for a found bead whose eleven rows ALL pass.

The first four are PRESENCE (is the field there); the six after them are
VIABILITY (can what the field holds actually work); the last is CONTENT (does
the text itself survive being written and read back). Each viability row and
the content row retires a rule that used to be remembered and cost a round when
it was not.

For every row reporting `"passed": false`, apply its `detail` as the
correction:

- `<type> is not driveable` — re-type the bead to `task`/`bug`/`feature`/
  `chore`, or re-home the work under a driveable child.
- `validation_plan is blank` — author one, scoped by **Scope the
  validation_plan to every consumer**.
- `acceptance_criteria is blank` — author `- [ ]` checkboxes a named command
  can falsify.
- `bd dependency rows: <rows>` / `bd holds no blocking dependency rows` — the
  row PASSED. It is a PROJECTION, not a comparison: it reports what bd holds
  and asserts nothing about what the prose says. A bead that names a blocker in
  a sentence and wires no row reports NO ROWS and passes — which is why **Wire
  every dependency at intake** is a step and not a suggestion.
- `unresolvable external dependency rows: <row> names "<project>", which this
  station does not arm (armed: …)` — an `external:` row points at a project the
  roster does not carry. Arm that substation, or re-point the row at one the
  roster does. Never delete the row to make the check pass.
- `unresolvable external dependency rows: <row> is unresolved: no station
  roster was supplied` — nothing can resolve `<project>`, so the row refuses
  fail-closed. This is a COMPOSITION gap and not a bead defect: the fix is in
  the station that builds the verb, never in the bead. Say so on the bead,
  leave the row wired, and do not work around it by deleting the row or
  stamping the approval by hand.
- `validation_plan does not parse under sh: <diagnostic>; offending text
  "<slice>"` — **rewrite as one parseable POSIX-shell command**. The gating
  lane runs the plan as `sh -c '( <plan> )'` a whole build later; a plan that
  dies at PARSE burns the round with no log and no return code. The row names
  the exact offending text: a `#` inside a quoted `$(…)` opens a comment that
  swallows the closing paren, and an apostrophe carried out of design prose
  into a single-quoted program closes the quote early.
- `validation_plan parses under sh but not under dash: <diagnostic>; offending
  text "<slice>"` — **replace the Bash-only construct with POSIX sh syntax**.
  `sh` is bash on a developer's mac and dash on CI, and a Bash-only construct
  such as `<(…)` dies at parse under dash — which surfaces as a harness
  throttle rather than as a bad plan.
- `absolute file path in bead text: "<path>" (<field>:<offset>)` — **use a
  repository-relative path**. The anchor extractor resolves an absolute path
  against the worktree, misses, and records a FAILED surface, which holds the
  round without ever saying why.
- `no attached store holds "<id>" (<field>:<offset>)` — **mint it before citing
  it or cite an existing attached-store id**. Guessed ids have shipped three
  times. Create the bead first and copy the id off the `Created` line.
- `exact release version pinned in acceptance_criteria: "<version>"` — **use
  release-relative language or a version range**. Specify copies the acceptance
  list into a gating plan leg, so a pinned version fails on the next release
  wave rather than on the work.
- `no register holds "<citation>"` — **a round may not cite a decision it
  creates; cite an existing entry or describe the proposed entry without a
  citation**. Discovery holds every round on a citation that cannot exist until
  the work lands. Decision requests are read from the **description and design
  only**: notes are the operator's RECEIPT channel, so a governor quoting a
  hold reason into them cites nothing and this row never sees it. A citation
  genuinely meant is restated in the description or the design.
- `no register holds "ADR-<nnnn>" (<field>:<offset>) — REPORTED, never
  refused` — the row PASSED, and it is still telling you something. A legacy
  `ADR-<nnnn>` id no completed lookup can answer is reported rather than
  refused: the register's own log file is spelled `ADR-0000`, and no register
  holds an entry for the log its amendments live in, so refusing there is a
  hold nothing can clear. Read the named slice anyway — a genuinely misspelled
  legacy id looks exactly like this.
- `corrupting bead text: backtick "\u0060" (<field>:<offset>)` or `NUL
  "\u0000" (<field>:<offset>)` — **remove NUL bytes and backticks before
  filing**. A NUL TRUNCATES the write and a backtick is COMMAND-SUBSTITUTED by
  the shell that carries the field, and `bd` reports success either way — so
  the bead files clean and dies a build later without ever naming its own
  cause. The row quotes each offending code unit by its printable escape and
  names the exact field and offset to edit; it names the first twelve sites and
  counts the rest, so fix the named ones and rerun. Write a quoted path or
  symbol as plain words or an indented block, never as a code span.
- `… evidence is unavailable for <token>: <source> — restore complete evidence
  and rerun` — nobody could ANSWER, which is not the same as an answer of "no".
  This is a COMPOSITION gap, not a bead defect: the store or the decision index
  the verb was composed with did not reply. Fix the composition and rerun;
  never edit the bead to route around it.

Then RERUN the verb. Repeat until the report reads `"passed": true`; only then
stage the bead for approval. Nothing else stages a bead — a reading of the
fields is not the check, and this skill deliberately owns no completeness
predicate of its own.

A report carrying `error` (`bead not found`) is a REFUSAL, not a pass: the id
is wrong or the cwd is the wrong store. Correct the id or the store root and
rerun. Never approve past an `error`.

## "Why won't this bead mount?" — `mount` is the oracle, and it is a COMMAND

`filing` answers whether a bead is APPROVABLE. It does not answer whether the
station will MOUNT it, and that second question used to be answered from memory
— a hand-closed session leaves a bare `work_bead` key and the bead never
re-mounts; a mount-attempt cap has no reset verb at all. It is a command now.
Run it FIRST, before any inference, from the grid home:

```bash
{{runner}} mount --json --state-root "<grid home>" "<bead>"
```

The report is one JSON object: `{id, verdict, preconditions, filing, withheld?,
withheld_retrieved_by?, error?}`. `preconditions` carries exactly ten rows, in
order — `driveable_type`, `validation_plan`, `acceptance_criteria`,
`dependencies`, `approval_stamp`, `session_occupancy`, `defer_state`,
`verdict_cap`, `mount_attempt_cap`, `live_admission` — each
`{precondition, outcome, detail, remedy?, evidence?}`. `outcome` is `PASS`,
`BLOCKED` or `UNCHECKED`; the exit code is 0, 1 and 2 in that order.

- **`BLOCKED`** — the row's own `remedy` says what to do. Apply it when it is a
  bead edit this seat owns. Hand it over when it is `park`, `rework`, `resume`,
  `unpark` or `bead rearm`: those are destructive, they belong to the governor,
  and the verb itself performs none of them.
- **`UNCHECKED` means NOT ASKED, and is never a pass.** `session_occupancy`,
  `verdict_cap` and `mount_attempt_cap` go unchecked when no `--state-root`
  names a grid home or that home's state store refuses the read;
  `dependencies` goes unchecked when a local target could not be read back.
  Supply the root and rerun, or write on the bead that the condition is
  UNKNOWN — never record it as clear.
- **`live_admission` is ALWAYS `UNCHECKED`**: capacity, slot reservations,
  admission latches, process liveness and the engine-only mint and
  successor-retry counters live in a running station's memory, not in any
  store. It is the only residue worth escalating — read the resident's
  `{{runner}} status`, and only then reach for relay inference, which is the
  cheap pass OVER this mechanical answer and never a replacement for it.

`filing` stays the approvability exit oracle: `mount` stages nothing and
approves nothing. Its embedded `filing` member IS that same report, so one
invocation answers both questions and neither is re-derived by reading fields.

## Staging: approve with the approve verb, only after refinement

Drafts are created open and UNSTAMPED; the human's approval is the approve
verb, which re-runs the same eleven-row filing preflight and then writes the
`grid.approved_*` stamp in one `bd update`. Against a LIVE station, the
mounted predicate refuses any unstamped bead with
`approval: not approved - run the approve verb` — the retired `grid.approved`
label is not read — so the mount race is closed without a timer:

- Create UNSTAMPED, wire deps, finish the description and design,
  and drive `{{runner}} filing --json "<bead>"` to
  `"passed": true`. Only after human approval, from the grid home, run:

  ```
  {{runner}} approve --actor operator --json "<bead>"
  ```

  The verb stamps `grid.approved_by` (the `--actor`), `grid.approved_at` (the
  UTC ISO-8601 instant) and `grid.approved_rev` (the digest of the FILING
  BASIS the preflight just evaluated — the bead's work fields, its validation
  plan and the dependency ROWS bd holds); that one stamped write is the final
  transition into the mounted frontier. Approval is granted to that basis, not
  to the bead id: EDITING an approved bead's description, acceptance, design,
  validation plan or blockers refuses it at the gate with
  `approval: stale - rerun the approve verb`, so rerun the verb after any
  approved-bead edit. A refusal writes nothing — it reports `"approved": false`
  with a `reason` plus the failing filing rows; fix them and rerun the verb.
- Removing the `grid.approved_*` stamp from a bead that is ALREADY mounted does
  not evict it
  — mounted work is never evicted for budget or readiness reasons; only a
  positive terminal (bead closed / session terminal) unmounts.

## Staleness reconciliation — run BEFORE arming any store

Backlogs rot: features get built in other sessions and the beads stay open. A
stale bead costs a full agent round on already-shipped work, and (until the
committee's diff-pinning fix is everywhere) can even come back A-graded because
critics reviewed the mainline code as if it were the bead's diff.

For each ready bead: check whether the named artifact already exists in the
work repo's mainline (`git log`/`grep` for the package, class, or file the bead
names). If shipped, CLOSE IT AS STALE WITH RECEIPTS — the reason carries the
file paths and commit ids that prove it:

```bash
bd -C <work repo> close <bead> --reason "<receipts: file paths, commit ids>" \
  --actor operator
```

Closing a bead with a live agent on it is safe — that is the designed positive-
terminal unmount.

## Re-homing beads across stores

Re-creating a bead in another store carries the text, NOT the metadata:
re-stamp `validation_plan` (and any `grid.*` envelope keys) on the destination
or round 1 gates F. Re-run the exit check in the DESTINATION store before
staging.

## bd footguns

- `bd update` with an EMPTY id resolves the LAST-TOUCHED bead — never
  interpolate a possibly-empty variable into an id slot.
- Writes route by CWD: always `bd -C <store-root>` (a leading `cd` in a
  compound also re-routes the command through permission classifiers).
- `bd create --deps 'blocks:X'` makes the NEW bead block X (inverted from the
  common intent) — wire with `bd dep add` after creating.
- Grouped mutations: `bd batch` (one transaction). Bulk reads: `bd export`.
  Never `bd show` from a polling path; never spawn bd per issue in a loop.
- `--actor operator` on every mutation; reasons carry receipts.
