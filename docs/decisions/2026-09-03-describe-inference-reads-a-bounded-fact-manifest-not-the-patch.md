---
status: accepted
date: 2026-09-03
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: describe-inference-reads-a-bounded-fact-manifest-not-the-patch
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: ["a18-bead-pow-8dx-the-landing-pr-title-body-is-inferred-from"]
  obsoleted-by: null
  updated-by: []
  bead: pow-c7lb
  legacy-id: null
---
## 2026-09-03 — bead `pow-c7lb`: the describe pass reads a BOUNDED FACT MANIFEST, not the patch

**Decision:** A18(1) ratified INFERENCE over `origin/<base>...HEAD` on the
ground that "a title templated off the bead can only ever restate the bead; a
title read off the DIFF says what actually changed". This narrows WHAT the model
reads of that range, and nothing else:

(1) **The model receives a rendered `DescribeManifest`, never a patch hunk.**
The facts a PR description needs from a diff — which files changed, by how much,
which of them are tests, what the commits say, whether validation and the
committee passed — are all derivable DETERMINISTICALLY from `git diff
--name-status -z`, `--numstat -z`, `--shortstat`, the commit log, and the
session's own receipts. Asking a model to re-derive them from up to 60 KB of
hunks paid frontier-adjacent context for an answer git already had, and made the
file/test claims in the digest a GUESS rather than a fact.

(2) **A18(1)'s ground is preserved, not overturned.** The range is unchanged
(the three-dot merge-base range A9(2) pins the critics to), the title still
describes the CODE and never the tracker, and the pass is still INFERENCE — the
model still chooses the type, the scope, the wording and the digest. What it no
longer does is REDISCOVER facts. The bead's intent rides as intent, explicitly
labelled "never a claim about the code".

(3) **Bounded by construction, and honest when it truncates.** Each record is
clamped before assembly, assembly stops at a record boundary under 16 KiB of
UTF-8, and the section counts, the diffstat aggregate, the change shape and the
receipt provenance are REQUIRED lines reserved before any record is admitted —
so a manifest that drops records SAYS how many, and the prompt forbids
describing an omitted record as if it had been read.

(4) **The call is METERED.** A18(2) put the describe pass inside the delivering
step behind an injected runner, where no `result()` hook was capturing FT-2
usage — so the one inference the landing phase spends was invisible in
`grid.result.*`. `spawnFor` now receives `usageOut: usageReportPath(nodePath)`
and the terminal `Advance` carries the parsed fields, extending A20(5)'s
`modelUsage` capture to the last unmetered seat. The route's own keys are
written after the usage spread, so telemetry cannot rewrite a verdict.

(5) **No builder-authored summary field.** The alternative source for the
manifest was a summary the coding agent writes into its result. Rejected: the
conventional commit subjects/bodies ARE the builder's canonical account, a
second account can drift from them, and it would spend frontier-tier output in
the most expensive seat to restate what the commits already say. If commit prose
is poor, the commit-policy lint (A18(7)) is the correction seam.

**Why:** the truth about a change still lives in the diff. It does not follow
that a model must READ the diff to report it — the parts of that truth a PR
description needs are mechanical, and the part that is not (the wording) is the
only part worth paying inference for. Separating them makes the digest's file
and test references TRUE by derivation rather than by luck, and makes the cost
of the landing prose a bounded, measured line item.

**Affects:** `packages/grid_assets/lib/src/code/describe_manifest.dart` (NEW —
`kMaxManifestBytes`, `ChangedFile`, `changedFilesFrom`, `DescribeManifest`,
`DescribeReceipt`, `buildDescribeManifest`), `pr_composition.dart`
(`buildDescribePrompt` re-signed to `{beadId, manifest, trailerToken}`;
`kMaxDiffChars` + `kMaxContextChars` DELETED), `pr_describe.dart`
(`describeBranch` gains `nodePath` + `receipts`, reads name-status/numstat/
shortstat instead of the patch, arms FT-2 capture, reads its answer from the
envelope; `DescribeOutcome.usage` NEW), `delivery.dart` (the route threads
`args.nodePath` + the two receipts and merges the usage into its `Advance`),
`grid_assets.dart` (one export); tests: NEW `describe_manifest_test.dart`, plus
migrations in `pr_describe_test.dart`, `pr_composition_test.dart`,
`track_e_reference_inflation_test.dart`, `delivery_test.dart` and
`support/asset_fakes.dart`. `AgentCapability`, `AgentBrief` and the builder
result schema are UNTOUCHED.

**Status:** pending — recorded by an autonomous agent run; only Nico promotes.
