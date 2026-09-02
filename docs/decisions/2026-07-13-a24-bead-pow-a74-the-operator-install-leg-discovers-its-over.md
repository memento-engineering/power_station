---
status: accepted
date: 2026-07-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a24-bead-pow-a74-the-operator-install-leg-discovers-its-over
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A24"
---
## A24 (2026-07-13) — bead `pow-a74`: the operator install leg discovers its overlay roots NON-PRESCRIPTIVELY via `package:extension_discovery` over the GRID HOME's package config; its target defaults to `<gridHome>/.claude`, not `~/.claude`; the vended skills gain an AUDIENCE, held as a DENY-list so the build agent's brief never offers an operator skill

**Decision:** the OPERATOR leg of overlay delivery ships as `packages/grid_assets/lib/src/assets/overlay_install.dart` (the UI-drivable lib) + `install_command.dart` (the thin adapter), consuming A23's `OverlayMaterializer` unchanged. Four autonomous calls:

(1) **Overlay-root discovery is `package:extension_discovery` over the GRID HOME's package config, read explicitly.** Every package in `<gridHome>/.dart_tool/package_config.json` that ships BOTH the Packaged-AI-Asset manifest (`extension/mcp/config.yaml`) and an `extension/station_overlay/` is in scope, sorted by package name; no pack is named in code, so a new asset pack in the station's pubspec is in scope the moment it is. The repo already followed this package's SHAPE as a spec (the manifest IS its `extension/mcp/config.yaml` form) without taking the dep; the operator leg is exactly the case it exists for, so this bead takes it. The config is read EXPLICITLY rather than via the running isolate's, because a composing station ships AOT (it cannot find its own package config) and because the packs to install are the OPERATOR's project's, not the binary's. `useCache: false` — the command leaves no `.dart_tool/extension_discovery/` artifact in the operator's checkout. A grid home with no package config THROWS, naming the probed path: an operator who has not run `dart pub get` is told, never handed a silent empty install.

(2) **The install target defaults to `<gridHome>/.claude`, a declared DEPARTURE from A23's parenthetical** ("its target, `~/.claude`, is not a repo, so it needs none of (6)"). The bead prescribes COMMITTABLE overlays that the operator reviews and commits, and the skills this bead re-homes were hand-committed in the grid home's own checkout — so the grid home, not the home dir, is where they belong; `--target` serves the operator who wants otherwise. Both readings agree on the load-bearing half: this leg writes NO git-exclusion artifact and COMMITS NOTHING — it prints a new-file diff and stops. That is the one place it departs from the provision wire, which self-ignores what it materialized (A23(6)) because `land` commits with `git add -A`; hiding the operator's overlay from git would defeat its purpose. Fenced by a by-construction test: the leg's source names no `GitOps`/`SourceControl`/`Process.*`/`.gitignore`.

(3) **The vended skills gain an AUDIENCE, held as a DENY-list (`kOperatorSkills`), not an allow-list of agent skills.** Re-homing the four operator skills into the ONE overlay tree means a per-bead worktree now receives them too (A23: one tree, two consumers) — but a build agent's brief must never NAME them, because `harvest-review` teaches "push and open a PR with receipts" inside the very brief that says "Do NOT push and do NOT open a pull request", and a skill the brief never names cannot be invoked in print mode (ADR-0001). The guard is a deny-list rather than an allow-list because the wire materializes whatever overlay it is handed: a skill this package does not vend (a third-party asset pack's, an injected fixture's) is a skill whose pack meant it for its agents, and silently dropping it from the brief would make it mysteriously non-invocable. Only a DECLARED operator audience withholds a skill. Mirrored in the manifest as `audience: operator` / `audience: agent`, fenced by test.

(4) **The offline delegate mount is extracted ONCE (`mountedValuesOf<T>`, `mounted_tree.dart`) and both legs ride it.** The install leg must resolve the grid home from the resident-station context by TREE POSITION (the ambient `GridRoot` a `RawAssetGrid` provides) — the same walk `mountedRosterOf` does for `SubstationScope`. A23(2) named the trap outright ("building a second roster-walker here would duplicate A11's"), so the walker is generalized rather than copied; `mountedRosterOf` keeps its signature and becomes a one-liner over it.

**Why:** (1) is what makes "non-prescriptive" real rather than aspirational — a hardcoded pack list would have to be edited every time a station gains an asset pack, which is the cross-store deferral A23(4) was taken to avoid. (2) is a genuine judgement call against a parenthetical in a pending amendment, so it is declared rather than quietly taken. (3) is correctness, not polish: without it the re-home actively hands every build agent a skill that contradicts its working agreement — the re-home is only safe BECAUSE of the audience split. (4) is A23(2)'s own restraint, honored.

**Also (mechanical, no decision):** the asset suites' hand-rolled cwd walk was replaced by the loader's cwd-independent root (`PackagedAssetLoader.root`). `Directory.current` is process-global and `dart test` runs suites concurrently, so the sibling suite that chdirs to a foreign dir to PROVE cwd-independent resolution (`track_d_assets_test`) raced any walk done from inside another suite's test body — a latent flake this bead's two new suites made bite.

**Affects (if promoted):** `packages/grid_assets/lib/src/assets/overlay_install.dart` (new), `…/lib/src/assets/install_command.dart` (new), `…/lib/src/assets/mounted_tree.dart` (new), `…/lib/src/search/station_search.dart` (`mountedRosterOf` rides the extracted walker; the private `_RosterAuthor` deleted), `…/lib/src/assets/asset_loader.dart` (`kVendedSkills` grows to five; new `kOperatorSkills`), `…/lib/src/code/code_capabilities.dart` (`_materializeStationOverlay` withholds operator-audience ids from the brief), `lib/grid_assets.dart`, `pubspec.yaml` (`extension_discovery`), `extension/station_overlay/skills/{station-operations,intake-refinement,harvest-review,gate-medicine}/SKILL.md` (re-homed + templated), `extension/mcp/config.yaml` (four declarations + `audience:`), new `test/assets/overlay_install_test.dart`, new `test/assets/install_command_test.dart`, `test/assets/skill_assets_test.dart`, `test/assets/overlay_materializer_test.dart`, `test/track_h_code_extension_test.dart`. The composing station's own hand-committed `extension/skills/` copies are left in place (a different repo); deleting them and composing `..addCommand(InstallCommand(...))` on its runner is that repo's own follow-up.

**Status:** Ratified (2026-07-14, Nico) — part of the SKILLS-HOME RULE (register foot).

