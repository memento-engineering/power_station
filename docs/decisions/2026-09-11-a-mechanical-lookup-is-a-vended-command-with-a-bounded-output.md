---
status: accepted
date: 2026-09-11
decision-makers: ["nico", "refiner"]
consulted: []
informed: [governor]
register:
  spec: 1
  slug: a-mechanical-lookup-is-a-vended-command-with-a-bounded-output
  surfaces:
    - "packages/**"
  obsoletes: []
  updates:
    - adr-0001-packaged-ai-asset-skill-command-coupling
  obsoleted-by: null
  updated-by: []
  bead: pow-kq2e
  legacy-id: null
---

# A mechanical lookup is a vended command, and a vended command bounds its output

## Context and Problem Statement

ADR-0001 ruled on 2026-07-10: *lookup → command; judgement → the agentic half*, and in Nico's own
words, *"do not leave a mechanical lookup to inference."* That rule has been in force for two
months. It was applied only to lookups an agent already knew to ask for **by name** — `search`,
`discover`, and the ADR-grep and sibling cross-check `specify` leans on.

The largest mechanical lookup in the system was never vended: **reading and searching source.**

Measured over the whole 2026-09 codex pool — 880 sessions, 544.6M characters of session growth:

* Tool output is **53.8%** of all growth. Inside it, reading source is the largest single class:
  `sed` at 2,583 calls and **44.2M characters**, averaging **17,110 characters per call**, plus
  `nl -ba` at 245 calls and 4.8M characters, averaging 19,421. On the Claude lanes the same class is
  the `Read` tool: 9,291 calls, 91.9M characters, 9,893 per call — 4.7x the per-call cost of `Bash`.
* The loop is **guess, over-read, re-guess.** The agent does not know where a symbol is, so it pays
  twice: `rg` to discover (1,881 calls, 24.7M characters), then `sed` with a **guessed line range**
  to read. `sed -n '1,260p'` means "the first 260 lines, and hope."
* **32% of file-read calls re-read a file already read in the same session** — 29% of all file-read
  output, 14.2M characters, for content already in context.
* **Nothing is capped anywhere.** A multi-file `sed` chain reaches 34,461 characters in one call,
  and the agent discovers a file's size by paying for it.
* Across 6,683 distinct command shapes the **top 20 families are 26.9% of all shell output**, and
  nearly every one is the same shape: a `sed` line-range read, chained one to six times. The agents
  are hand-rolling **one** missing tool, thousands of times.

This is not a gap in ADR-0001. It is a two-month-old violation of it, and it is the single largest
avoidable cost in the system.

A second problem the same data exposes: **no vended command declares an output contract.** A
deterministic command with unbounded output burns the window exactly as the inference it replaced
did. Coupling alone does not deliver the saving the rule was ratified for.

## Considered Options

* Leave reading to inference and attack the cost with prompt guidance ("read less").
* Vend a read command, and let each command decide its own output discipline.
* Vend a read command, and bind every vended command to an output contract implemented once in the
  CLI SDK.

## Decision Outcome

Chosen option: **the third.** Two clauses.

### 1. Reading and searching source are lookups, and they are vended

They sit on the lookup side of the ADR-0001 line, so the existing rule already requires a command.
This entry states it because the absence has been read as a gap rather than as a violation.

A read command **addresses by symbol, not by line range.** The guessed range is the defect: it is
what makes the agent pay `rg` to find the file and then pay again to read the wrong part of it.
Symbol to file-and-span is deterministic in every language we ship, and resolving it collapses the
discovery call and the read call into one. Returning line anchors with the content also retires the
separate `nl -ba` pass whose only purpose is to number lines for a patch.

### 2. Every vended command carries a bounded output contract

A command that returns whatever the filesystem happens to hold has not replaced the inference; it
has only renamed it. Three properties, and they are **implemented once in the CLI SDK** — output
configuration and formatters vend from the SDK, never re-derived per command. A per-command
implementation is the same failure this entry exists to stop, one layer down.

* **A hard output cap.**
* **An explicit truncation marker** naming what was withheld and how to ask for it
  (`+412 more lines — refine with --span`). Silent truncation is worse than no cap: it produces
  confident, partial answers, which is the `bd query` capped-read failure this org has already
  shipped once.
* **Structured results**, per ADR-0001 — the skill parses a schema and never scrapes prose.

### Suppression is keyed on the answer, never on the question

A command may decline to re-emit what it already returned in the same session **only** when it can
prove the answer unchanged. The key is the **identity of the answer** — path, span and blob hash —
**never the text of the command.** In a build lane the file is changing underneath the agent, so
keying on the command string would serve a stale read while reporting success.

That splits vended commands into three classes, and only the first may suppress:

| class | examples | cap output | suppress repeats |
|---|---|---|---|
| pure / content-addressed | `read`, `search`, a bead read pinned to a revision | yes | yes, keyed on content identity |
| time-varying read | `git status`, `bd ready`, station `status` | yes | **never** |
| mutating | `bd create`, `apply_patch`, `approve` | incidental output only, never the receipt | **never** |

**A command that cannot prove its answer unchanged returns fresh output.** That is the default, and
a command which cannot compute an identity key does not get to opt into suppression.

### Deliberately not ruled here

**Result caching for slow commands** — returning a previous `dart test` or `dart analyze` result
because the tree looks unchanged. It is a different problem with real correctness risk: flaky lanes,
environment-dependent tests, and ordering effects mean a cached green can mask a live red, which
costs far more than the tokens it saves. It is also small — `dart` is 1.73% of measured growth
against roughly 9% for reads. Ruling on it under time pressure would be the wrong trade; it needs
its own entry.

### Consequences

* Good, because it converts the largest measured cost class from inference to a deterministic
  surface, which is what ADR-0001 was ratified to do.
* Good, because a symbol-addressed read removes the `rg`-then-`sed` round trip rather than
  compressing it — the saving is structural, not a smaller dump.
* Good, because the contract lands in the SDK once, so every command vended afterwards inherits the
  discipline instead of re-deciding it.
* Good, because the identity key makes suppression safe in a lane where files change mid-session,
  which a naive command-string cache would not be.
* Bad, because a capped read can truncate the one region that mattered, and the agent then pays a
  second call to widen it. The truncation marker is what keeps that recoverable; a silent cap would
  not be.
* Bad, because bounded reads may raise the call count even as they lower total bytes. Per-call
  overhead is real, and the net saving is asserted from output measurement rather than proven by a
  controlled run.
* Bad, because vending a command is a maintenance obligation, as ADR-0001 already noted. This adds
  the output contract to that obligation.

### Confirmation

This decision is in force when a station's own read command serves the lanes and the measurement is
repeated. The pass condition is a fall in the file-read share of session growth, with the
re-read share — 29% of file-read output today — as the leading indicator, since it is the one
component that should go to near zero rather than merely shrink.
