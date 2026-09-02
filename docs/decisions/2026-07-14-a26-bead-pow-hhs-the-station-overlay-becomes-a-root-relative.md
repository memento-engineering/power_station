---
status: accepted
date: 2026-07-14
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a26-bead-pow-hhs-the-station-overlay-becomes-a-root-relative
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A26"
---
## A26 (2026-07-14) — bead `pow-hhs`: the station_overlay becomes a ROOT-RELATIVE, path-preserving overlay with a PROVENANCE stamp — one root-parametric materializer, two callers, two SCOPES; drift is decided by the BODY; A23(7)'s malformed-tree throw is RE-HOMED to the caller whose invariant it protects

**Decision:** Nico settled the four design points this bead turned on (2026-07-14 — the overlay is a path-preserving tree onto a repo ROOT; the trigger is an explicit `assets install` command group, never folded into `up`; provenance is COMMITTED, not gitignored, with a `--check` drift gate; the header's `@<ref>` IS the version stamp). Seven calls the run made that those four did not settle:

(1) **The provenance stamp is FORMAT-AWARE, and an unstampable file type is REFUSED LOUDLY.** A comment ABOVE the content would break both shapes the overlay vends: a SKILL.md's YAML frontmatter must OPEN on line 1 (the harness's skill discovery parses it there), and JSON has no comment syntax at all. So the stamp goes INSIDE each format — a YAML comment on line 2 of a frontmatter-led `.md`, a top-level `"$generated"` field textually inserted after a JSON object's opening brace (the rest preserved byte-for-byte, so an install never reformats the operator's settings). `provenanceSyntaxFor` THROWS on any other shape, because an unstampable file could never be told from a hand-authored one — which would dissolve the very invariant the stamp exists to carry. The JSON leg additionally re-parses what it stamped and throws if the insertion would not leave valid JSON (a minified or empty object): textual insertion is what preserves formatting, and this is the guard that keeps it honest.

(2) **DRIFT is decided by the BODY, never the ref.** `--check` compares `stripProvenance(installed)` to the freshly rendered source, and an install re-stamps only a file whose BODY changed. The alternative — treating a stale `@<ref>` as drift — would mark every installed file dirty on every grid_assets commit and churn the operator's tree for nothing, which would make the committed-with-provenance posture unusable within a week.

(3) **`--check` is an in-memory PLAN (`dryRun`) over the SAME walk, not a re-materialize into a temp dir + diff** (the mechanism the bead's own text suggested). No temp IO, no cleanup, and — the load-bearing half — ONE code path decides both modes, so the check cannot disagree with the install it is gating.

(4) **The worktree leg SCOPES to `.claude/skills`; the operator leg takes the WHOLE tree.** One tree, two consumers, two ROOTS — and two SCOPES. A23(6) already established that `.claude/` is REPO-OWNED territory in the very repos the grid cuts worktrees from (power_station and lenny TRACK `.claude/settings.json`); that clause rejected a shared `.claude/.gitignore` for exactly this reason. Now that the completed overlay CARRIES `.claude/settings.json`, an unscoped worktree leg would either leak a loose file into the bead's PR (it cannot be fenced per-asset-dir) or overwrite a tracked repo file from a provision hook. The scope is what keeps A23(6) true.

(5) **A23(7)'s LOUD malformed-tree throw is RE-HOMED, not deleted.** Under the path-preserving format a loose file is LEGAL (`.claude/settings.json` genuinely lives there), so the throw cannot stay in the walk. It moves to `OverlayMaterializeReport.writtenAssetDirsUnder` — the one caller whose named invariant it actually protects (nothing the wire materializes may ride the bead's PR), and the half A23(7)'s own text pointed at: *"which is also what lets the wire safely derive the asset dirs it must exclude."* A file loose under the SCOPED subtree still throws; a file loose elsewhere in the overlay is simply installed.

(6) **The source ref is probed with a SYNCHRONOUS, READ-ONLY `git rev-parse --short HEAD`** (`resolveOverlaySourceRefSync`), not the house `GitRunner` seam — which is async-only, while the provision wire cannot await (A23(3)/A1: `ProcessCapability.spawn` returns a `RuntimeConfig` directly). It is confined to one function, writes nothing, creates no git artifact, and is overridable (`--source-ref`, `AgentCapability(overlaySourceRef:)`) — the seam a git-tag dep will feed. A24(2)'s "commits nothing, writes no git artifact" fence is PRESERVED and STRENGTHENED: the grep still covers the two install files, and a new test pins that the ONE git invocation the leg can reach is a `rev-parse` and names no mutating verb — so the fence now binds the code the Command actually runs, not merely the two files it greps.

(7) **A BLOCKED or REFUSED skill is NOT reported as installed** — departing from A23/A24, where a target file that already existed was SKIPPED and still counted toward `installedSkillIds` (*"an operator's own copy is still an installed skill"*). A blocked path holds a HAND-AUTHORED file this tooling neither wrote nor vetted, and the brief that consumes these ids tells the agent "the station materialized these VENDED skills" — naming a file we did not install, whose body we do not control, would be a claim the wire cannot make. The safe direction is also the honest one: a skill the brief never names cannot be invoked (print mode selects none on its own — ADR-0001).

(8) **A SYMLINK at the target — at the file OR at any ancestor dir — is BLOCKED, never followed.** Found by driving the real installer against a copy of the live operator seat rather than by reasoning: `space_station/.claude/agents/governor.md` and every `.claude/skills/<id>/` are SYMLINKS into its `extension/` tree. Two distinct failure modes, both real: a DANGLING link makes `File.existsSync()` return false, so the write is taken for a fresh one, follows the link and throws `PathNotFoundException` (an unhandled crash mid-install); and a RESOLVING link — the seat's actual shape, where the *directory* is the link and the file under it is not — would, on any later UPDATE, write straight THROUGH it and mutate a file OUTSIDE the target root, silently breaking this lib's own stated promise ("writes nothing outside `targetRoot`"). A symlink is by definition not something this tooling generated (it only ever writes regular files), so it is BLOCKED with its own remedy named ("remove the link to let the vended file install") — which is precisely the act the space_station companion must perform. This is the guard that makes the never-clobber invariant true against the seat as it ACTUALLY exists, not merely against a tree of regular files.

**Why:** Nico's decision (1) makes the overlay's own tree the target layout, which unifies the two delivery legs into one root-parametric materializer — but it also makes a LOOSE file legal for the first time, and that single consequence is what drives (4) and (5): the format guard and the git fence both assumed every vended file sat inside a `<kind>/<name>/` asset dir. (1), (2) and (3) are the mechanism decisions the "committed, not gitignored" posture needs to survive contact with a real repo: a stamp that breaks the file it stamps, a drift check that fires on every commit, or a check that can disagree with its own install would each make the posture worse than the hand-copies it replaces. (6) is a constraint, not a preference — the one seam that could give a commit sha is async and the wire cannot await it. (7) is the only place this run tightened a pending amendment's stated behavior, and it is recorded rather than quietly changed. (8) is the one decision no amount of reasoning produced — it came from driving the installer at the real seat, which is symlinked, and finding that the never-clobber guard did not yet hold against the very tree it was written to protect.

**Flagged for Nico (NOT decided here):** **ADR-0001 (DRAFT)** now has its SECOND Command half, and it is of a new kind: `assets install` is the deterministic leg of the coupled skill+command pattern for the whole asset SET — the installer of the pairs — rather than the partner of one skill. That is a genuine extension of a DRAFT ADR and wants an ADR-0001 amendment; per the org rule it is flagged, not authored autonomously. Separately, **A24(2)'s "the install target defaults to `<gridHome>/.claude`" is SUPERSEDED IN FORM** by Nico's decision (1) — the command's target is now the repo ROOT and the `.claude/` comes from the overlay's own tree — while landing on the IDENTICAL destination; A24(2)'s load-bearing half (commits nothing, writes no git artifact) is preserved as (6) records.

**Affects (if promoted):** `packages/grid_assets/lib/src/assets/overlay_provenance.dart` (new — the stamp, the strip, the sync ref probe), `…/lib/src/assets/overlay_materializer.dart` (root-parametric + path-preserving + `subtrees`/`sourceRef`/`dryRun`; `kOverlayKinds`/`OverlayFileSkipped`/`writtenEntryDirs`/`installedSkillIds` DELETED; `OverlayFileUpdated`/`Unchanged`/`Blocked` added; `kDefaultOverlayRunner` re-homed here from `code_capabilities.dart`), `…/lib/src/assets/overlay_install.dart` (installs onto a ROOT; `check`; `operatorClaudeDir` DELETED), `…/lib/src/assets/assets_command.dart` (was `install_command.dart` — the `assets` GROUP; `--root` replaces `--target`; `--check`/`--source-ref` new), `…/lib/src/code/code_capabilities.dart` (the wire targets the worktree ROOT, scoped to `.claude/skills`), `…/lib/src/assets/asset_loader.dart`, `…/extension/station_overlay/.claude/**` (re-rooted; GAINS `agents/governor.md` + `settings.json` — the complete operator asset set), `…/extension/mcp/config.yaml`, and the migrated suites + `test/assets/overlay_golden_test.dart` (new — the live worktree path's regression gate). space_station: the consumer half (compose the command, install onto its root, retire its hand-copies) is a companion bead in another repo.

**Status:** Ratified (2026-07-14, Nico) — part of the SKILLS-HOME RULE (register foot).

---

## RATIFIED CROSS-AMENDMENT RULE — SKILLS-HOME (2026-07-14, Nico)

Nico's ratification. Promotes **A12, A23, A24, A26** to **Ratified**. A vended skill's on-disk home follows its declared `audience` (`extension/mcp/config.yaml`):

- **agent** (invoked by a build agent; named in its brief) → `packages/grid_assets/extension/skills/<name>/SKILL.md` (A12).
- **operator** (for the human/governor operating a station; NEVER named in a build agent's brief) → `packages/grid_assets/extension/station_overlay/.claude/skills/<name>/SKILL.md` (A23 established the overlay tree → A24 the audience split → A26 the root-relative `.claude/` form).

Audience is declared in the manifest and enforced as a deny-list so a build agent's brief never offers an operator skill (A24(3)). Consequence: the `release` skill (pow-vvr) and the four station-operator skills are OPERATOR-audience; `discover` is AGENT-audience.

---

## RATIFIED — DISCOVERY GATE: pending amendments are ADVISORY, not binding (2026-07-14, Nico)

Nico's ratification, resolving the A21-vs-CLAUDE.md conflict that thrashed the pow-vvr / vendor-content work. At the discovery/violation gate (A21 / pow-96y), a **PENDING** ADR-0000 amendment is **ADVISORY ONLY** — surfaced as context for the spec committee's `adr-alignment` lane, NEVER grounds for a discovery HOLD. Only a **RATIFIED** standard (a ratified ADR, or an amendment whose Status is Ratified) can trigger a hold.

This **supersedes A21(2)'s** clause "the citable standard is a ratified ADR (its pending `A<n>` amendments included — they bind)", and aligns the gate with the org CLAUDE.md (amendments are candidates for ratification, not binding until ratified).

The gate additionally grades a bead's **INTENT** — a bead whose plan/acceptance REMOVES a cited offence PASSES (it is the fix), rather than holding on mere text-presence — per A21's own principle that "only an unwitting contradiction gates."

Implemented by **pow-d7i**.

