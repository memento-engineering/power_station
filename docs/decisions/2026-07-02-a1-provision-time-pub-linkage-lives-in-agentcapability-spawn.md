---
status: accepted
date: 2026-07-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a1-provision-time-pub-linkage-lives-in-agentcapability-spawn
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A1"
---
## A1 (2026-07-02) — Provision-time pub linkage lives in `AgentCapability.spawn`, applied SYNCHRONOUSLY via a new `DartLinkService.applySync`, not inside `GitSourceControl.provisionWorkspace`

**Decision:** the grid.dart envelope decode+apply the bead `tg-ucz` design ("wire at the code circuit's setup capability after provisionWorktree") calls for happens inside `AgentCapability.spawn` (`packages/grid_assets/lib/src/code/code_capabilities.dart`), immediately after the ambient `Bead`/`Workspace` are read and guarded on `Directory(workspace.workspaceDir).existsSync()` — not literally inside `GitSourceControl.provisionWorkspace` (the method name the design doc's prose points at), and not as a new circuit step. `AgentCapability` gained `devRoot`/`linkService` constructor params; `buildCodeRegistry` and `CodeRunCommand.run` thread `live.workRoot.path` through as `devRoot`. A new `DartLinkService.applySync` (sync `dart:io`, sharing its decode/derive logic with the existing async `apply` via a private `_plan` helper) makes this possible from a method that cannot `await`.
**Why:** `SourceControl.provisionWorkspace(beadId, workspaceDir)` is an engine-owned interface (`grid_engine` — a different repo, out of this bead's scope, and the task explicitly says "the engine stays opinion-free — this lives in the asset, not grid_engine") that carries no `TreeContext`/`Bead` access — so the concrete `GitSourceControl` impl in this repo has no sanctioned way to read the bead's metadata from inside that method. The sanctioned read is the ambient `InheritedSeed<Bead>` `WorkBead` mounts (the same one `AgentCapability.spawn` already reads for the brief) — reading it anywhere requires `TreeContext`, which only capability-level hooks (`spawn`/`run`) receive. Of those, a `ServiceCapability.run` step placed BEFORE `agent` in `kCodeCircuit` was considered and rejected: only `ProcessAllocation` (which drives `ProcessCapability`, i.e. `agent`) calls `sc.provisionWorkspace` before invoking the capability — `ServiceAllocation` (which drives `ServiceCapability` steps like `land`/`critic`/`route`) never calls it, so a `ServiceCapability` "setup" step ahead of `agent` would run against a worktree that does not exist yet. `AgentCapability.spawn` is therefore the only point that is (a) called AFTER `GitSourceControl.provisionWorkspace` in the same `startOrAdopt` flow, and (b) already reads the ambient `Bead`+`Workspace` legitimately. `spawn()` returns `RuntimeConfig` directly (not a `Future`), forcing the sync `applySync` path; a `LinkRefused` outcome throws `StateError`, reusing the EXISTING fail-closed idiom `AgentCapability.spawn` already has (a throw from `capability.spawn` is caught by `ProcessAllocation` and reported as a per-work `AllocationFailed` — ADR-0008 Decision 10) rather than inventing a new failure channel. A directory-existence guard mirrors `GitSourceControl.provisionWorkspace`'s own offline/dry-run no-op posture (`DryRunProvider`/`_DryStationGitService` never materialize a real worktree, yet `capability.spawn` still runs to build the "would-spawn" config) — without it, dry-run would throw trying to write into a synthetic, nonexistent path. No `bd` calls anywhere on this path (A37 holds by construction: the metadata is the SAME already-fetched `Bead.metadata` every other capability reads).
**Affects (if promoted):** the_grid `docs/SCRATCH-pub-capability-and-repo-split.md` / a future the_grid ADR should record that "the_grid only READS it at provision time" resolves through the ambient `Bead` seed at the `agent` capability's spawn edge, not through `SourceControl.provisionWorkspace`'s own signature. Code (already built this bead): `packages/dart_grid_assets/lib/src/dart/dart_link_service.dart` (`applySync` + shared `_plan`), `packages/grid_assets/lib/src/code/code_capabilities.dart` (`AgentCapability._linkWorkspace`, `buildCodeRegistry(devRoot:)`), `packages/grid_assets/lib/src/code/code_run_command.dart` (`buildCodeRegistry(devRoot: live.workRoot.path)`).
**Status:** pending.

