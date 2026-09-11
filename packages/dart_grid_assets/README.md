# dart_grid_assets

The Dart domain grid assets — the typed grid.dart envelope, pub dev-time linkage, and the exported DartCommand.

## Status

Early development (0.1.x). Part of [power_station](https://github.com/memento-engineering/power_station) — memento.engineering's grid asset packs. APIs move fast; pin exact versions.

## One-command workspace release

`dart release publish` releases a whole pub workspace in one wave. From the
workspace root:

A release moves on **two independent axes**: `--change` is the SEMVER MOVE
(`docs`/`additive`/`fix`/`breaking`) and `--rung` is the PRERELEASE RUNG
(`stable`/`dev`/`beta`/`rc`). The rung belongs to each PACKAGE, not to the wave,
so `--rung` is optional here: omitted, each changed package's rung is read off
its authored version and a mixed `dev`/`beta` wave is ordinary.

```sh
# a stable wave — tags directly, but only after every consumer passes
dart run melos run release -- --change fix --consumers consumers.json

# the same wave, stopping after the gates (nothing is tagged or pushed)
dart run melos run release -- --change fix --consumers consumers.json --dry-run

# breaking work enters the ladder at dev — no human in the loop, no consumer
# gate here (the separate ops carry it)
dart run melos run release -- --change breaking --rung dev

# the API is frozen for this target version; the bugs are not
dart run melos run release -- --change breaking --rung beta

# rc means a human has declared intent to promote, so it must be declared
dart run melos run release -- --change breaking --rung rc --promotion-intent

# the compatibility spelling of the line above, kept for existing callers
dart run melos run release -- --change rc --promotion-intent
```

`dev`, `beta` and `rc` are the three rungs of the prerelease ladder, per
package. **Only a human sets `rc`** — its entry condition is a declared intent
to promote rather than a computed one, so an agent publishes breaking work at
`dev` or `beta` on its own authority and never reaches `rc`. Moving between
rungs restarts the counter in either direction (`0.2.0-dev.3` -> `0.2.0-beta.1`,
and a demoted `0.2.0-rc.9` -> `0.2.0-beta.1`); the target core never moves
again once the ladder is entered.

The wave, in order:

1. **Changed set.** Every workspace member that is not `publish_to: none` is
   polled on pub.dev. A member whose authored version is already published is
   skipped. For the rest, the published version the authored one bumps off is
   resolved through the same version math `release plan` uses — a package
   pub.dev has never seen is a first release. Each package's rung comes from
   its authored version (no prerelease is `stable`; a prerelease must be a
   supported `<dev|beta|rc>.<N>`), and an explicit `--rung` must AGREE with
   every one of them. A version that no published version reaches under the
   declared move and rung is refused, as is any pub.dev answer other than 200
   or 404, an unsupported prerelease shape, and an `rc` package with no
   `--promotion-intent`.
2. **Gates.** The scrub gate (content scan plus the declared-floors
   resolution) for every changed package, then the dependency-order publish
   sequence, then `dart pub publish --dry-run` for every package in it.
   Nothing mutates until all of them pass.
3. **Consumer validation** (only when the planned wave carries a STABLE
   package — the gate follows the plan, not the declared move). The release commit is
   `HEAD`, and it is refused unless it is reachable from an `origin/` ref —
   pub takes a commit SHA as a git `ref:` exactly as it takes a tag, so
   consumers resolve against the very commit being released. Each consumer's
   `pubspec_overrides.yaml` is restored byte-for-byte afterwards (and removed
   if the wave generated it). One failing consumer refuses the whole wave
   before any tag exists: a "non-breaking" change that fails a consumer is
   breaking, and the refusal says to put it on the ladder with
   `--change breaking --rung dev` instead.
4. **Tag, push, wait.** One `<package>-v<version>` tag per package in
   dependency order, one `git push origin <tag>` each, and a pub.dev poll loop
   until the version appears before the next dependent is tagged. **The tag
   push is the publish** — the tag-triggered publish workflow does the upload,
   so the wave never runs `dart pub publish` for real.

A breaking move authored as a **stable** version is refused at the plan stage,
before any gate runs: breaking work enters the prerelease ladder at `dev`, and
the stable base is promoted through the separate `release validate-consumers`
and `release promote` operations once a human declares `rc`. Nothing reaches a
stable version until every consumer passes — `release promote` still requires a
green validation report.

A stop is structured — `{"stage": ..., "package": ..., "message": ...}` — and
it is a hard stop. A gate failure leaves zero tags; a failure after the wave
starts mutating leaves only what its own stage already did, and every later
package untagged and unpushed.

The consumers manifest is the same shape `release validate-consumers` takes:

```json
{
  "consumers": [
    {
      "name": "space_station",
      "directory": "../space_station",
      "links": [
        {
          "package": "grid_assets",
          "git_url": "git@github.com:memento-engineering/power_station.git"
        }
      ]
    }
  ]
}
```
