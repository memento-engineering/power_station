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
