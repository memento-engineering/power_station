# github_grid_assets

GitHub App identity and authenticated REST transport for grid extensions. This
package deliberately stops at identity: it does not poll or reconcile state,
open pull requests, process webhooks, or write beads.

## Credential posture

The non-secret App and installation IDs enter through `GitHubAppConfig`.
`GC_GITHUB_APP_KEY_PATH` must contain an absolute path to an external,
operator-owned PEM file. The operator provisions that file outside the source
tree with mode `0600`. The PEM is never passed on argv and never stored inline
in an environment variable.

When `GC_GITHUB_APP_KEY_PATH` is absent or empty, credential resolution returns
`null`, allowing unconfigured composition to remain inert. Once configured, a
missing, non-file, unreadable, or incorrectly permissioned binding refuses
loudly. Derived installation tokens remain memory-only and are never written to disk;
they refresh before expiry.

## Boundaries

- `pow-1rn.2` owns pull-request opening.
- `pow-1rn.3` owns reconciliation and polling.
- `pow-1rn.4` and `pow-1rn.5` own bead projections.
- `pow-1rn.6` owns webhooks.

## Testing

`dart test` runs the offline unit suite: no bd binary, no Dolt server, no
credentials. The **live-state-writer tier** — `test/github/ci_rework_mint_acceptance_test.dart`,
which spawns the real `bd` binary against a hermetic temp workspace and drives a live grid state
writer over a bd proxied-server SQL endpoint — is tagged `integration` in `dart_test.yaml` and held
out of that default run by the tag config, not by a `skip:` string in the test and not by a
per-bead exclusion in a validation plan. Run it by name where `bd` and `dolt` are on `PATH`:

```bash
dart test -P integration
```

The `integration` preset in `dart_test.yaml` selects the tier and lifts only the tag's hold; a
test's own `skip:` stays in force, so a blocked case in the tier stays blocked (`--run-skipped`
would lift those too, and is not the invocation).
