---
name: release
description: >
  Cut a disciplined pub.dev release of a Dart package (or a workspace of them) —
  the consolidated genesis+lenny publishing playbook. Owns the JUDGEMENT: when a
  version is worth publishing, whether a change is a patch or a breaking minor,
  how to frame a breaking CHANGELOG + migration line, and how to reconcile a
  workspace whose tags have drifted (lenny's repo-level `v0.1.1`) onto the
  per-package `<pub-name>-v<version>` convention. The deterministic work —
  version math, tag strings, the scrub gate, the dry-run, the pub.dev poll,
  dependency order — rides the vended `{{runner}} dart release` Command, whose
  JSON this skill PARSES. Use when the human says "release <package>", "publish
  <package> to pub.dev", "cut a release", "bump and publish", "ship the new
  version", or "reconcile the release tags".
compatibility: Requires dart + the `{{runner}}` runner, git, and pub.dev publish rights (the memento.engineering verified publisher).
metadata:
  author: memento-engineering
---

# Release

Publishing is a JUDGEMENT wrapped around a deterministic core. You make the calls
a human would — is this worth a release, is it breaking, is the drift real — and
you delegate every mechanical step to the `{{runner}} dart release` Command,
which returns structured JSON you PARSE. Never eyeball a version, hand-grep for
internal refs, or read pub.dev's HTML — the Command is the substrate.

## The deterministic substrate — CALL the command, PARSE its JSON

Each op emits ONE JSON object under `--json`. Read the fields; never scrape.

- **Version + tag** — `{{runner}} dart release plan --package <name> --current <ver> --change <docs|additive|fix|breaking|rc> --json`
  -> `{current, next, change, requiresBreakingChangelog, package, tag}`.
- **Private release tag** — `{{runner}} dart release tag --repo-dir <repo-dir> --tag <tag> --json`
  -> `{tag, created, exitCode}`.
- **Consumer validation** — `{{runner}} dart release validate-consumers --rc-tag <rc-tag> --manifest <consumers.json> --json`
  -> `{rcTag, allPassed, results:[...]}`.
- **Stable promotion** — `{{runner}} dart release promote --repo-dir <repo-dir> --stable-tag <stable-tag> --validation <validation.json> --json`
  -> `{tag, created, exitCode}`.
- **Scrub gate** — `{{runner}} dart release scrub --dir <package-dir> --json`
  -> `{root, clean, filesScanned, hits:[{file, line, text, match}], declaredFloors:{candidate, pins:[{package, declaredConstraint, floor}], pubGetExitCode, analyzeExitCode, passed, message, stdout, stderr}}`.
  Read both `clean` and `declaredFloors.passed`. A false value stops the release;
  `declaredFloors.message` names the analyzed symbol diagnostics and every
  workspace sibling exact floor. This leg resolves pub.dev and belongs only to
  this release verb, never the offline workspace test command.
- **Workspace discovery** — `{{runner}} dart release discover --workspace <workspace-dir> --diff <ref> --json`
  -> `{workspaceRoot, diff, candidates, changed}`. `candidates` is every
  publishable member whose AUTHORED version is not on pub.dev; `changed` is
  every member touched since `<ref>`. It is the operator PREFLIGHT — read-only,
  and it neither replaces nor weakens the gates below.
- **Publish order** — `{{runner}} dart release order --workspace <workspace-dir> --json`
  -> `{order:[...]}` (dependency-first sequence out). The workspace adapter
  reads melos's own dependency graph and FILTERS it to each package's top-level
  `dependencies:` before ordering — see the runtime-only limit below.
  `--manifest <deps.json>` (a `{package:[in-set deps]}` object) remains as the
  compatibility input; pass EXACTLY ONE of `--workspace` and `--manifest`, or
  the op exits 64. A cycle exits non-zero with a loud message.
- **Dry-run gate** — `{{runner}} dart release dry-run --dir <package-dir> --package <name> --json`
  -> `{package, exitCode, warningCount, clean, warnings:[...]}`.
- **pub.dev poll** — `{{runner}} dart release poll --package <name> --version <ver> --json`
  -> `{package, wanted, latest, isPublished}`. ONE probe — you loop it.

## Answering the release questions with melos, not by hand

Every workspace here already declares melos as a dev_dependency and configures
only its `scripts:` key. That is not the limit of what melos knows: `melos
list` already answers, for the WHOLE workspace, the questions this flow used to
answer one package at a time. Use it instead of the hand method.

- **Which local versions are unpublished** — `dart run melos list
  --no-published --json`. NOT a pub.dev curl per package.
- **What changed since a ref** — `dart run melos list --diff=<ref> --json`.
  NOT a `git log <ref>..HEAD -- packages/<pkg>` per package.
- **Which siblings a breaking package drags along** (the rc closure) —
  `dart run melos list --depends-on=<package> --json`. It returns the closure
  INCLUDING dev-dependency edges, which is exactly what you want when asking
  "what stops resolving", and is exactly what you must NOT feed to publish
  order.
- **The dependency graph** — `dart run melos list --json --graph`, an adjacency
  object of ALL in-workspace edges.

`{{runner}} dart release discover` wraps the first two and
`{{runner}} dart release order --workspace` wraps the last, so prefer the
vended ops: they hand you one JSON object to PARSE and they apply the runtime
filter. Reach for raw `melos list` for the `--depends-on` closure, which has no
vended op of its own.

Do NOT add a melos command configuration to make any of this work — every flag
above is a `melos list` FILTER, not configuration. Each workspace's existing
scripts-only `melos:` block stands.

## When to publish (the judgement)

- A **consumer needs the version resolvable** — a sibling wants to drop a path
  override, or a member's constraint points at an unpublished version. An
  unpublished API reachable only via path links is a bug in the release state.
- A **docs-only refresh** — pub.dev renders the README/CHANGELOG frozen into the
  archive at publish time, never GitHub, so a docs fix ships as a real version.
  Cheap and encouraged; say "Docs only, no API changes" and use `--change docs`.

If neither holds, do not cut a release — say so and stop.

## Patch vs. breaking (the call `plan` encodes)

Decide the `--change` class, then let `plan` do the math:

- **Additive API, fixes, docs -> `--change` docs/additive/fix** — a PATCH
  (`0.1.x`).
- **Breaking -> `--change rc`** — plan a MINOR pre-1.0 candidate (`0.1.x`
  -> `0.2.0-rc.1`), or a MAJOR candidate from 1.0. A BREAKING change MUST go
  rc-first; do not use `--change breaking` to cut a stable version directly.
  `plan` returns `requiresBreakingChangelog: true`: the CHANGELOG MUST lead with
  `Breaking:` and carry a one-line migration. pub reads `^0.1.0` as
  `>=0.1.0 <0.2.0`, so a breaking change hidden in a patch silently reaches
  every resolver — that is why breaking moves to the next breaking base as an
  rc before stable promotion.
- **Adding a member to an exported abstract interface is breaking** for external
  implementers, even when every in-repo handle just delegates — call it breaking.
- **Cross-package coherence:** when a sibling consumes API introduced in version
  X, tighten the sibling's constraint to `^X` in the SAME change and release in
  dependency order, so a resolved pair is always coherent.

## Pre-release (rc) publishing

Cut an rc instead of a stable release when a breaking change must be adopted by
siblings before stable is safe, when the candidate needs consumer validation in
CI, or whenever “we should not have to do a public stable release to get
development to work” describes the bind. A BREAKING change MUST go rc-first.

1. Plan the candidate with `{{runner}} dart release plan --package <name>
   --current <ver> --change rc --json`; use the returned `next` and `tag`.
2. Apply the planned version and CHANGELOG entry, pass the ordered gates below,
   commit them, then cut the candidate tag with `{{runner}} dart release tag
   --repo-dir <repo-dir> --tag <rc-tag> --json`.
3. In each consumer, opt in by changing its hosted constraint to
   `^X.Y.Z-rc.N`. Pub excludes prereleases from ordinary stable caret ranges:
   a consumer on `^0.1.x` does NOT resolve `0.2.0-rc.1`, while a consumer
   pinned to `^0.2.0-rc.1` accepts later `0.2.0` rcs and stable `0.2.0`.
   That exclusion is what lets the pub.dev candidate publish without disturbing
   stable consumers.
4. **Sibling-coherence rule:** an rc on a package forces an rc on EVERY in-repo
   sibling that depends on it. Move each dependent's constraint to the rc and
   version every package in the same release wave, even when a dependent has no
   API change of its own; otherwise the package set will not resolve. Moreover,
   `dart pub publish` REFUSES a stable package that depends on a prerelease, so
   every dependent in that closure must remain rc until the wave is promoted.
   Read the closure with `dart run melos list --depends-on=<package> --json`
   — it is the query that surfaces the dev-dependency edges which break a
   workspace resolve — then compute publish order with `release order` and
   process the complete closure.
5. Publish each candidate in dependency order by PUSHING ITS TAG (one tag per
   push — see Publishing below; the publish workflow uploads via trusted
   publishing). After each tag, loop `{{runner}} dart release poll --package
   <name> --version <rc-version> --json` until `isPublished: true` before
   pushing a dependent's tag. `release poll` reads pub.dev's complete versions
   list and is the authority for prereleases (`melos publish` compares against
   latest stable and is retired for uploads).
6. Validate the candidate with `{{runner}} dart release validate-consumers
   --rc-tag <rc-tag> --manifest <consumers.json> --json`, save that ONE JSON
   object as `<validation.json>`, and require `allPassed: true`.
7. Only after every consumer passes, promote with `{{runner}} dart release
   promote --repo-dir <repo-dir> --stable-tag <stable-tag> --validation
   <validation.json> --json`. A failed validation report MUST stop promotion;
   only the promoted wave may remove the prerelease suffix and publish stable.

## The gates — all mandatory, IN ORDER

Run them in sequence; a failure STOPS the release.

1. **Workspace green** — `melos run analyze`, `melos run test`, `melos run
   format` (or the repo's equivalent). A plain shell gate, not a `dart release`
   op.
2. **Scrub** — `{{runner}} dart release scrub --dir <package-dir> --json`. Read
   `clean`, which folds in BOTH legs. If false, each `hits[]` entry names the
   `file`, `line`, and `match` to strip, and `declaredFloors.passed: false`
   means the candidate does not compile against the minimums its own
   `pubspec.yaml` promises — a member used above a declared floor. A pub
   workspace resolves siblings by path, so that stays invisible until a fresh
   resolve holds the older published sibling; RAISE the named sibling's
   constraint to the version that introduced the symbol rather than loosening
   the gate. Fix, re-run, expect `clean: true`.
3. **No internal working docs inside the package dir** — handoffs, scratch, and
   design notes ship in the archive if they live under the package. Move them out.
4. **CHANGELOG entry + version bump, committed** — author them with `dart run
   melos version --no-git-commit-version`, which writes every member's
   `pubspec.yaml` version AND its CHANGELOG entry AND the dependent constraint
   and dependent version updates in one pass (melos's `--changelog`,
   `--dependent-constraints` and `--dependent-versions` defaults all stay ON —
   that is the point). `--no-git-commit-version` disables melos's default
   commit and, by implication, its default tagging: the release commit must
   land through the repo's reviewed PR path, and trusted publishing must still
   start from one per-package tag push YOU control (see Publishing). Reconcile
   what melos wrote against `plan.next`, add the `Breaking:` + migration line
   when `requiresBreakingChangelog`, then commit.
5. **Classification** — `{{runner}} dart release classify --dir <package-dir>
   --package <name> --json` for EVERY candidate; require `verdict: "ok"`. This
   is mandatory, and it does NOT become optional because melos authored the
   version — see the commit-message limit below.
6. **Dry-run** — `{{runner}} dart release dry-run --dir <package-dir> --package
   <name> --json`. Read `clean`; treat ANY warning as a stop. In particular,
   “N checked-in files are modified in git” means gate 4 is incomplete: COMMIT
   the version bump and CHANGELOG first, then rerun dry-run. Staging is not
   enough; this gate validates checked-in state, so gate order matters.

## Two limits melos does NOT lift

Both were hit live on the 2026-09-08 lenny release. Neither is a reason to keep
doing discovery or versioning by hand; both are reasons the vended ops stay in
the flow.

1. **`melos version` reads COMMIT MESSAGES, so it inherits their honesty.** It
   derives each bump from Conventional Commits. lenny#96 was a breaking change
   that carried no `!` and no `BREAKING CHANGE:` footer, so `melos version`
   would have cut a PATCH — exactly what the hand method cut. Adopting melos is
   NOT a substitute for classification. After melos authors the versions, run
   `{{runner}} dart release classify --dir <package-dir> --package <name>
   --json` on every candidate and require `verdict: "ok"`: `classify` diffs the
   public API against the last PUBLISHED release, so it sees the break the
   commit message hid.
2. **Publish order is computed on RUNTIME dependencies only.** `leonard_agent`,
   `leonard_flutter` and `leonard_flutter_test` form a DEV-dependency cycle,
   and `release order` correctly REFUSES a manifest containing it. A melos
   graph carries dev-dependency and dependency-override edges, so the
   `--workspace` adapter filters every edge against the package's top-level
   `dependencies:` before ordering. A dev cycle is not a publish cycle. Never
   hand a raw `melos list --graph` to `--manifest`.

## Publishing — push the tag; CI publishes (trusted publishing)

**Local `dart pub publish` is RETIRED.** Each repo's
`.github/workflows/publish.yml` publishes on a per-package tag push via
pub.dev's GitHub-Actions trusted publishing (OIDC — no long-lived credential).
Every historical publish-run failure on the_grid/power_station was `Version X
already exists`: a hand-publish had beaten the tag. The tag IS the publish.
CI checkouts also carry no `pubspec_overrides.yaml`, so the move-the-overrides
dance disappears with the hand-publish.

1. Land the release commit through the repo's normal PR path (queue where one
   exists). Tags point at the MERGED main commit.
2. Resolve dependency order (`{{runner}} dart release order --workspace
   <workspace-dir> --json` for a multi-package wave; `--manifest <file>` still
   works for a hand-written graph).
3. For each package in that order:
   - `git tag <plan.tag> <release-commit> && git push origin <plan.tag>` —
     **ONE TAG PER PUSH.** GitHub fires NO workflows for a push containing more
     than three tags (observed live 2026-08-23: four tags in one push, zero
     runs), and per-tag pushes are what give you ordering anyway.
   - Watch the run (`gh run list --workflow=publish.yml`) and loop `{{runner}}
     dart release poll --package <name> --version <ver> --json` until
     `isPublished: true`. Only then push the DEPENDENT's tag.
4. **First release of a package:** automated publishing must be enabled ONCE on
   the package's pub.dev admin page (Automated publishing → GitHub Actions →
   repository `memento-engineering/<repo>`, tag pattern: `<package>-v`
   immediately followed by pub.dev's version placeholder — the word `version`
   in double curly braces, as the admin form suggests). Only an uploader can
   click it — a publish run
   failing with an authorization/OIDC message means exactly this toggle; hand
   the human the admin URL, nothing else.
   (`melos publish` remains retired for uploads; melos still owns the
   workspace-green gates, release discovery, and version authoring.)

## Post-publish

1. Verify: `{{runner}} dart release poll --package <name> --version <ver>
   --json` returns `isPublished: true` for every wave member, and spot-check
   the rendered README.
2. Pull `main` in the primary checkout so the local tree matches the tagged
   release.

## Reconciling drift (the lenny case)

lenny ships ad hoc: REPO-level tags (`v0.1.0` / `v0.1.1`) that have DRIFTED from
the actual per-package versions (`leonard_flutter` is at `0.1.7` behind a
`v0.1.1` repo tag), with no gates and no written playbook. That repo-level tag is
the **anti-pattern** — it cannot tell which package a tag belongs to. To migrate
a workspace onto the convention:

1. For each published package, read its real `pubspec.yaml` version and compose
   the correct tag with `{{runner}} dart release plan --package <name> --current
   <ver> --change docs --json` (read `tag`).
2. Create the missing per-package tags on the commits that shipped those
   versions; leave the old repo-level tags in place (deleting shared tags
   rewrites history others may hold).
3. From here every release tags per-package via `plan.tag`, and the gates above
   apply — the drift stops accreting.

## Publisher & ownership

All members ship under the **memento.engineering** verified publisher; new
versions inherit it. A package published OUTSIDE the publisher needs a one-time
**Admin -> Transfer to Publisher** (irreversible) on its pub.dev page — a manual
step this skill flags but cannot perform.

## What you don't do here

- Invent a version, tag string, publish order, or scrub verdict by inference —
  every one is a `{{runner}} dart release` op whose JSON you PARSE.
- Publish when no consumer needs the version and it is not a docs refresh.
- Hide a breaking change in a patch, or ship a `Breaking:`-less CHANGELOG for a
  `--change breaking` release.
- Publish a dependent before `poll` returns `isPublished: true` for its
  dependency.
- Treat a commit message as a classification. `melos version` is version
  AUTHORING; `release classify` is the verdict, and it runs on every candidate.
- Order a publish wave off a raw melos graph, or let `melos version` commit or
  tag for you.
