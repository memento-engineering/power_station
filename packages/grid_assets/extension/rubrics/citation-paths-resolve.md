# citation-paths-resolve [GATING]

A gating lane of the DOCS committee. It does not weigh opinion — it is a
DETERMINISTIC check run in Dart (`DocsCheckCapability`; no model, no
judgement). It answers the question a prose committee could not otherwise
answer: does this document still point at things that exist?

## What it checks

Every repo-relative path CITED on a line the diff ADDED must resolve in the
worktree — as a file or a directory, relative to the repo root or to the citing
document's own directory. A citation is a backticked span or a markdown-link
target that names a path: no whitespace, no URL scheme, at least one `/`, and
either a trailing `/` or a file extension. A trailing `#anchor` and a trailing
`:Symbol` locator are stripped first. Globs and commit ranges are not paths and
are never probed.

Only ADDED lines are read — the scope-pinning doctrine one level down: a
citation this change did not write is not this change's finding.

## Bands

- **A** — every cited path resolves.
- **F** — one or more do not; each is named with its citing document.

A grade of **F** here is a hard block: the route parks the bead at a gate
(`gated`) for rework. There is no partial credit and no judgement in this lane.
