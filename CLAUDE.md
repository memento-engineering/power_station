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
