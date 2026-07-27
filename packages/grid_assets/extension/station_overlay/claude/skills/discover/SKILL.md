---
name: discover
description: >
  The grid home's front door — the ONLY human-in-the-loop stage. Dispatches on
  arg shape: a bare invocation or a topic/idea/question researches what the
  grid already knows (the attached substations' backlogs + decision beads +
  code), then continues an existing bead or — on your yes — files a staged one
  and starts the design conversation. A bead-id with no prompt is
  advisory: it loads the bead and its graph and recommends the next lifecycle
  step. A bead-id followed by an instruction is directed: same context load,
  but it carries out the instruction (decompose, retype, close, fill in
  design, kick off specify). Use when the human says "let's build", "I have an
  idea", "plan this", "design this", "what's the state of <bead>", "what
  should I do with <bead>", or "have we already decided this".
---

# Discover

The front door of the grid home. Figure out what the grid already knows, then
either point the human at the next step, carry out their instruction, or start
a design conversation. You are in the governor's seat: you feed the backlog —
the station's agents build.

## The research substrate — CALL the search command

Cross-store coverage is a lookup, not a judgement call. The station vends a
deterministic, read-only Command for it, and you use it for EVERY "what does
the grid know about X?" pass:

```bash
{{runner}} search --json "<keywords>"
```

It resolves the ATTACHED substations from the resident-station context (the
roster is never hardcoded) and queries each seat's work store — backlog AND
decision beads, all statuses (decisions live closed; "have we already decided
this" needs them). One JSON object comes back:

```
{query, stores: [{substation, prefix, root, outcome, ...}], hitCount}
```

Per-store `outcome` is `searched` (with `beadsSearched` + `hits`), `absent`,
or `failed` — a roster seat is never silently dropped, and neither do you:
carry any absent/failed seat into your summary. Each hit is
`{id, store, status, type, title, field, snippet}`. Exit 0 = at least one
store searched; exit 1 = NOTHING was searchable — that is a loud non-answer to
report, never a cue to improvise.

Run 2–4 focused queries with distinct keyword angles — vary the terms, never
the mechanism. **The redline:** never re-derive cross-store search by
inference — no ad-hoc per-store `bd` sweeps, no SQL, no grepping `.beads/`
exports by hand. Reading CODE (Grep/Read over a substation's working tree) is
yours to do with normal tools — the command covers the bead stores, not the
repos.

Store roots in the report are as the station authored them — resolve a
relative `root` against the grid home (the directory you run from).

## Dispatch

Look at the first argument:

- **No arguments** (bare invocation or implicit trigger) → ask "What do you
  want to look into?" then treat the answer as a **topic**.
- **Arg 1 looks like a bead-id** — a `<prefix>-<suffix>` token on one of the
  roster's store prefixes. Confirm it deterministically:
  `{{runner}} search --json "<token>"` — an `id`-field hit confirms the bead
  exists AND names its owning store (id has first match precedence). Then:
  - **nothing after it** → *Advisory* (read-only recommendation).
  - **a prompt after it** → *Directed* (carry out the instruction). Everything
    after the bead-id token is the prompt.
- **Arg 1 is anything else** (a phrase, an idea, a question) → a **topic**.

The research layer runs in every shape — only the anchor differs (a known bead
vs. a topic). Only the directed shape *acts*; advisory and topic research do
not, except topic research may file a bead once the human confirms.

## Topic research

"I have an idea: XYZ" and "search for XYZ" are the same opening move —
research first, file only on confirmation.

1. **Search the stores** with the command above (2–4 keyword angles).
2. **Read the promising hits.** `cd` into the owning store's `root` and
   `bd show <id>` — a one-shot, human-present read; NEVER loop it or wire it
   into anything recurring (it touches the store's watcher), and never use it
   as a query mechanism — queries are the search command's job.
3. **Read the relevant code** in the owning repos — enough to know whether
   this is genuinely new or a re-tread.
4. **Report one of two outcomes:**
   - **Already exists** — name the bead, its status, its store, and what it
     covers. Ask: continue it? (If yes, that's the *Advisory* or *Directed*
     path — switch to it.)
   - **New** — name the adjacent beads and decisions it intersects. Ask: want
     a bead for this?
5. **On the human's yes → file the bead** (see *Filing*), then enter the
   design conversation. Do **not** file before the yes — no junk beads for
   "oh, that already exists".

## Filing — where a new bead goes

- **Target store: the substation whose repo the work would change** (the
  search report's `root` for that seat is your `cd` target). No clear owner →
  **the grid home's own store** (`.grid/.beads` under it).
- **Cross-store ordering:** cross-store dependencies DO exist, but
  never author one as a dependency row or with `bd dep add <id>
  external:<project>:<capability>`: A44 reversed that raw-foreign-id wiring
  because `bd doctor --fix` can classify it as orphaned and sever it. The
  current mechanism is A55's OPEN grid-state `type=link` bead carrying
  `grid.link.from=<blocked bead id>`, `grid.link.to=<blocker bead id>`, and
  `grid.link.type=blocks` in its own metadata. The station's link-authoring
  verb mints that bead only after its `crossLinkTypeRefusal` capability check;
  `StationJoinBridge._applyCrossLinks` projects it and the shared
  `applyBlockGuard` enforces it. A malformed link fails closed.
  Default to homing coupled beads together when one repo owns the work,
  because that gives
  the station a locally resolvable graph; split them across stores when repo
  ownership calls for it — including the three-store split directed by
  Nico on 2026-07-26 — and express their ordering with the link-authoring verb.
- **Staged, never ready:** a live station mounts a ready bead within seconds —
  a half-designed bead must never enter the frontier.

```bash
cd <owning store root>
bd create --title "<title>" --type <feature|bug|task|epic|chore|decision> \
  --defer <date ~1 week out> --actor governor \
  --description "<one paragraph: what problem this solves and why>"
```

Immediately verify that the created bead is discoverable with `{{runner}}
search --json "<new bead id>"` and require an `id`-field hit. Never use `bd show`
for this verification: exact-id lookup resolves a stranded wisp and hides that
it is absent from list/search surfaces.

The bead stays deferred until the human blesses it into the ready frontier.
Record design approval by filling `--description` and `--design` with `bd update
<id> --actor governor`; there is no persistence flag to change. All backlog
writes ride the bd CLI with `--actor governor`; never SQL, never
`.beads/hooks/`.

## Design conversation

Once you're on a typed bead (just filed, or an existing one the human wants to
keep designing):

- **One question at a time.** Multiple choice when possible; open-ended when
  the design space is genuinely wide.
- **Propose 2–3 approaches** with trade-offs; lead with your recommendation
  and say why.
- **Present the design section by section** — architecture, components, data
  flow, error handling, testing — and get a nod after each.
- **Type notes:** `epic` → on approval, decompose into child beads
  (`--parent`); `bug` → reproduce before designing the fix; `decision` → the
  record IS the deliverable: capture the tradeoffs and the ruling.

Every project gets discovery — "too simple to need it" is where unexamined
assumptions cost the most; brief is fine, skipped is not. When the design is
approved, write it into the bead so the specify stage has context in
isolation:

```bash
bd update <id> --description "<what and why, one paragraph>" --actor governor
bd update <id> --design "<approach chosen, constraints, what was ruled out and why>" --actor governor
```

### Hand off to specify

When the human signals "continue" / "specify it" / "keep going" → kick off the
specify stage (the sibling vended asset): invoke `/specify <id>` if this
station vends it. If it doesn't yet, say so and hand back: "Design recorded on
<id>, staged. Bless it when it's driveable."

## Advisory

For a bead-id with no prompt. **Never dispatches lifecycle-mutating commands
or other skills without an explicit go-ahead** — but asking clarifying
questions inline is not dispatching; the human is right here.

1. **Load the bead and its graph.** In the owning store's root: `bd show <id>`
   (status, design field, blockers/blocked-by), then one-shot reads of the
   related beads it names. Same caution as above: one-shot, human-present,
   never looped.
2. **Read the relevant code and decisions** for that bead.
3. **Classify the next step:**
   - **Tool-dispatch next steps** — the bead needs a lifecycle action the
     human must authorize (kick off specify, retype, close, decompose, bless).
     Recommend the command; do not run it.
   - **Conversational next steps** — the bead has open design decisions in its
     body (explicit forks, TBD markers, thin coverage) that can be resolved by
     asking. Fall through to the *Design conversation* inline; end with a tool
     next-step recommendation.

## Directed

For a bead-id followed by an instruction. Same context load as *Advisory*, but
**carry out the instruction** — the human instruction IS the authorization to
act: decompose the epic, retype, close, fill in the design field, kick off
specify, whatever was asked. Directed = advisory + permission. If the
instruction lands you on a typed bead that needs design work, fall through to
the *Design conversation*.

## Exit criteria

Before handing off from a design conversation, verify: the human has
**explicitly approved** the design; no open questions remain; you can state
what we're building in one sentence.

## What you don't do here

- Write acceptance criteria or implementation plans (the specify stage's job).
- Write code, or edit engine/product code to "fix" a bead (the station's build
  agents build; you file, refine, and bless).
- File a bead before the human confirms in topic research.
- Run lifecycle-mutating commands from *Advisory* without explicit go-ahead —
  only *Directed* carries permission. Asking questions is not dispatching.
- Bless a bead into the ready frontier — staging is yours, blessing is the
  human's.
- Re-derive cross-store search by inference — the search command IS the
  research substrate.
