---
status: accepted
date: 2026-09-07
decision-makers:
  - "Nico Spencer"
consulted:
  - "governor (agent seat)"
informed: []
register:
  spec: 1
  slug: agent-assets-install-from-a-pub-reference
  surfaces:
    - "packages/grid_assets/lib/src/assets/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-upsl
  legacy-id: null
---

# Agent assets install from a pub reference

## Context and Problem Statement

Refining lenny's `test-with-leonard` skill epic on 2026-09-07 raised a
placement question: does the skill ship from `leonard_cli` (the CLI package
on pub) or from `leonard_grid_assets` (an overlay pack composed into a
station)? Both answers assumed the way a repo gets an agent asset is either a
CLI that copies files or a station whose resolved package closure carries the
pack. Today the vended `assets install` walks only the station's closure —
`asset_resolution.dart` reads each root's `.dart_tool/package_config.json` and
the pack is discovered through `package:extension_discovery`'s
`extension/mcp/config.yaml` — so a pack the station does not depend on is
invisible, and `leonard_grid_assets` is composed into no station at all.

Nico's ruling, verbatim in substance: "How would you install skills from
`leonard_cli`? That doesn't make any sense to me. We should have a generic
`grid_cli` command that installs agent assets from a pub reference; pub.dev,
private pub server, git ref, git tag pattern matching."

## Decision Outcome

Agent assets — skills, agent definitions, harness settings — ship INSIDE pub
packages that carry an overlay, and any repository installs them by naming
the package to the vended assets verb. Concretely:

* The install verb accepts a pub reference as its source: a pub.dev package
  (with an optional version constraint), a package on a private pub server, a
  git url + ref (branch, tag, or sha, with an optional monorepo path), or a git
  tag PATTERN resolved to the highest matching tag by pub version order.
* Installation from a reference resolves it the way pub does (a scratch
  pubspec whose one dependency is the reference) and then feeds that root into
  the SAME resolution walk and overlay materializer the station-composed path
  uses — provenance-stamped, commits nothing, `--check` reports drift.
* A CLI package (such as `leonard_cli`) is never an asset-install path, and a
  pack never has to be composed into a station to reach a repo.
* The SKILLS-HOME rule (2026-07-14, and A32's pending placement correction)
  still governs WHERE a skill lives inside its pack; this entry governs how a
  pack reaches a repo and does not amend placement.

Implementation bead: `pow-8mlj`. First consumer: lenny's `test-with-leonard`
skill, whose home is therefore `leonard_grid_assets`.

### Consequences

* Good, because every harness — a station, a bare repo, another org — installs
  the same assets by the same verb, and a pack's release on pub is its whole
  distribution story.
* Good, because a pack no longer needs a station to compose it before its
  skills are reachable.
* Bad, because the verb takes a network dependency (pub resolution, git tag
  listing) that the station-composed path never had, and tag-pattern
  resolution is new logic with its own version-ordering edge cases.
