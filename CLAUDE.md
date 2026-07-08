# power_station

First-party **grid asset packs** for [the_grid](https://github.com/memento-engineering/the_grid)
— each pack exports domain components + CLI components (the CLI-SDK model). See
`README.md` for the pack table and the dev-linkage story (machine-local
`pubspec_overrides.yaml` path-deps into the sibling `../the_grid` checkout).
Extracted from `the_grid` at the repo split (ADR-0011 placement).

## Read first, in order

- `README.md` — the pack table + `dart pub get` / `melos run test|analyze`.
- `docs/adr/ADR-0000-ai-decision-register.md` — the living AI-decision register
  (A1…; every autonomous agent run lands its decisions here as a pending
  amendment, per the org rule — never Accepted, only Nico promotes).

## Conventions

- **Memento house set** (genesis ADR-0001 D7): Dart `^3.11`, pub workspace +
  melos; **freezed** sealed unions + `json_serializable`, consumed with
  exhaustive `switch`; **Fakes, not mocks**; pure logic tested before IO;
  shared lints (`strict-casts`/`-inference`/`-raw-types`, `prefer_single_quotes`,
  `unawaited_futures`, `avoid_print`). **"extension," never "plugin."**
- **The D-H genesis_tree doctrine (ADR-0008; companion to the_grid's `GridDelegate`
  D-H fix).** Assets/capabilities here are genesis_tree consumers, so:
  - **Always watch deps** — read ambient tree values in `build` via `dependOn*`;
    never snapshot-and-`??=`-cache reactive state. (The **effect** verb, at a
    capability's `spawn`/`run` edge, is the non-binding `getInheritedSeedOfExactType`;
    the **build** verb is the subscribing `dependOnInheritedSeedOfExactType` — ADR-0008 D3.)
  - **No public synchronous accessor over `StateNotifier` state** — `.state`/
    `current` never escapes; re-project it into the tree as an `InheritedSeed`
    and observe it in `build`.
  - **Config = VALUES in the tree; impls = DI** — author configuration as mounted
    values, inject implementations (no services in a branch except injected).
  - **Guards LOUD or GONE** — a guard exists only if it protects a NAMED
    invariant and is loud (throws/refuses) when violated; delete a silent guard.

## bd / beads rules

- `BD_JSON_ENVELOPE=1`; mutations via the **bd CLI only**, `--actor <name>`.
  **Never SQL writes, never touch `.beads/hooks/`.** **Never call `bd show` from a
  re-query/controller path** (it writes `.beads/last-touched` and self-triggers
  the watcher). Coexistence-safe: any experiment against live gc convergence
  traffic is strictly read-only.


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->
