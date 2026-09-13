---
status: accepted
date: 2026-09-13
decision-makers:
  - "Nico"
consulted: []
informed: []
register:
  spec: 1
  slug: release-is-a-gated-pipeline-without-committee
  surfaces:
    - "packages/grid_assets/lib/src/code/release.dart"
    - "packages/grid_assets/lib/src/code/code_capabilities.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-lwtw
  legacy-id: null
---

# Release is a GATED PIPELINE, without a committee

## Context and Problem Statement

Every major path this station drives is a circuit.
`packages/grid_assets/lib/src/code/code_capabilities.dart` registers discovery,
spec review, code, code review, design review, docs review and landing (plus the
frozen spec-review shapes the migration guard roots), and each one is a graph the
engine walks: a step's verdict gates the next, and no agent may skip a step by
not reading about it.

Release was not among them. It was driven by
`packages/grid_assets/extension/station_overlay/claude/skills/release/SKILL.md`,
which is prose. Docs review — reversible and internal — was a circuit.
Publishing to pub.dev — externally visible and effectively permanent — was a
document.

The cost came due with `grid_cli` 0.5.0-rc.22. It published from a hand-cut
release pull request (the_grid#407, merged 2026-09-11T17:56:46Z, published
17:59:13Z) whose Gate section recorded analyze, format, test and a dry-run, and
NO declared-floors leg. It was retracted. The gate existed and it worked;
nothing REQUIRED it, because in this machine the thing that makes a step
non-optional is a circuit, and release had none.

Two remembered rules existed only because release was prose — the publish
cascade order with its committed-lock trap and cache staleness, and the fact
that a cancelled publish run may still have uploaded, so each dependent tag
must be gated on pub.dev's versions list rather than on an exit code. Both were
triaged out of the agent memory index on 2026-09-12 under the rung-3 rule that a
procedure executed by remembering to belongs in the circuit that runs it. A
memory binds only the agent that reads it. A circuit step binds every run.

`docs/decisions/2026-07-15-adr-0003-private-git-tag-releases-and-prerelease-gate.md`
anticipated exactly this move. Its D4 made the gate governor-run "for now" and
recorded that "evolving the gate to a CI job or a station-driven validation
circuit is a deliberate later step, not a prerequisite". That reservation is
still in force and is not amended here; this is the later step it named. The
question D4 left open is the one that had to be answered before any of it could
be built: what SHAPE does the station-driven gate take?

## Considered Options

* **A full circuit with a committee round**, matching the code path: the
  deterministic legs, then adversarial critics grading the release against
  rubrics, then a route. It is consistent with every other circuit in the
  station, and consistency is not a small thing — one shape means one thing to
  learn, one place to look, one set of receipts.
* **A gated pipeline with no committee**: the deterministic legs, one
  human-promotion route, and nothing else.

The two genuinely conflict. Consistency argues for the first; cost and latency
argue for the second, and the argument turns on whether a committee would add
signal a deterministic gate has not already produced.

## Decision Outcome

The **gated pipeline** ships, and it ships without a committee. Nico's ruling of
2026-09-12, through the refiner seat, closed the fork.

The reason is that **every release verdict is already machine-decidable**. The
content scrub, the declared-floors analysis, the semver classification against
the published baseline, the packaging dry-run and the pub.dev propagation poll
each return a decided verdict, computed by the vended command that owns it. A
committee round would re-judge what a deterministic gate has already settled —
adding model spend and latency to an already slow, serialized, network-bound
path, and adding no signal. This is the case a critic lane is worst at and a
gate is best at.

`packages/grid_assets/lib/src/code/release.dart` binds these terms.

1. **It COMPOSES; it does not reimplement.** `discover`, `ladder`, `plan`,
   `scrub`, `classify`, `order`, `dry-run`, `publish` and `poll` are already
   vended as subcommands of the release command group in
   `packages/dart_grid_assets/lib/src/dart/release_command.dart`. The circuit
   invokes that argv surface and reads the JSON verdict. It recomputes no
   version math, scans no content, diffs no API and talks to no registry. A leg
   that cannot reach its vended verdict REFUSES rather than deciding for
   itself, so a missing analyzer stays the loud refusal
   `release-classification-shells-out-to-dart-apitool` already made it.
2. **The order is the deliverable.** One linear graph —
   `discover → ladder → promotion → plan → scrub → classify → order → dry-run →
   preflight → publish → poll` — with each node depending on its predecessor,
   and each leg additionally refusing when the receipt of the step it reads is
   absent. Reading a predecessor's receipt is what makes the sequence
   non-optional from inside the leg as well as from the graph.
3. **No committee, no critic, no rubric, no inference leg.** The graph carries
   exactly two capability ids: the deterministic gate and the promotion route.
   Nothing in this path spends a model.
4. **The irreversible leg is spent once.** The `publish` leg declares one
   initial attempt and parks at a gate on exhaustion, for a work failure, a
   no-result turn and an invalid result alike. A tag push IS the publish, so
   re-running an interrupted wave is not a retry of the same work — it is a
   second release attempt against a registry that may have moved. A human reads
   that gate.
5. **An exit code is not publication.** The pipeline ends by ASKING pub.dev, per
   published package, and a zero-exit poll reporting `isPublished: false` fails
   the circuit. That is the second remembered rule, now enforced.
6. **The human promotion boundary is preserved and is the only decision point.**
   Publishing a prerelease is agent work. A rung CHANGE into `rc` or into a
   stable version escalates without a declared human promotion intent, so the
   circuit HALTS at a rung change rather than driving through it. Publishing
   again at a rung a package already occupies is ordinary agent work, and the
   intent that put it there rides through to the vended operations that require
   the flag.

### What this does not do

It does not retire the release skill. Judgement — when to publish, how to frame
a breaking CHANGELOG entry, reconciling tag drift — is the skill's half of the
coupled pair, and it is not machine-decidable. What moves into the circuit is
the SEQUENCE the skill used to describe and an agent used to follow.

It does not close the bypass from outside the station. A human can still push a
tag by hand; refusing that is CI's job. A circuit cannot stop a hand-pushed tag,
and CI cannot sequence a wave across packages, so the two are complements.

It does not forbid a committee later. If a release failure mode turns up that no
deterministic verdict catches — a judgement call about whether a change SHOULD
ship, rather than whether it CAN — that is a new decision with new evidence, and
the graph has room for it.

### Consequences

* Good, because the gate that was skipped is now a step that cannot be skipped:
  the declared-floors leg the retracted candidate omitted runs on every wave, in
  a fixed place, with a receipt.
* Good, because two rules that only ever lived in agent memory are now
  mechanism — the dependency-first order and the pub.dev visibility barrier bind
  every run rather than only the run whose agent recalled them.
* Good, because it is cheap: no model spend and no committee latency on a path
  that is already serialized behind network propagation.
* Bad, because release is now the one circuit shaped unlike the others, so a
  reader who learned the code path's committee shape has a second shape to
  learn.
* Bad, because a release failure that is a judgement call rather than a
  deterministic one has nothing in this graph to catch it; it will surface as a
  bad release and a follow-up decision, not as a held round.
