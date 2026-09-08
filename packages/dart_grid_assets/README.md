# dart_grid_assets

The Dart domain grid assets — the typed grid.dart envelope, pub dev-time linkage, and the exported DartCommand.

## Status

Early development (0.1.x). Part of [power_station](https://github.com/memento-engineering/power_station) — memento.engineering's grid asset packs. APIs move fast; pin exact versions.

## One-command workspace release

`dart release publish` releases a whole pub workspace in one wave. From the
workspace root:

```sh
# a docs/additive/fix wave — tags directly, but only after every consumer passes
dart run melos run release -- --change fix --consumers consumers.json

# the same wave, stopping after the gates (nothing is tagged or pushed)
dart run melos run release -- --change fix --consumers consumers.json --dry-run

# a candidate wave — cuts rc.N tags only, no consumer gate here
dart run melos run release -- --change rc
```

The wave, in order:

1. **Changed set.** Every workspace member that is not `publish_to: none` is
   polled on pub.dev. A member whose authored version is already published is
   skipped. For the rest, the published version the authored one bumps off is
   resolved through the same version math `release plan` uses — a package
   pub.dev has never seen is a first release. A version that no published
   version reaches under the declared change class is refused, as is any
   pub.dev answer other than 200 or 404.
2. **Gates.** The scrub gate (content scan plus the declared-floors
   resolution) for every changed package, then the dependency-order publish
   sequence, then `dart pub publish --dry-run` for every package in it.
   Nothing mutates until all of them pass.
3. **Consumer validation** (docs/additive/fix only). The release commit is
   `HEAD`, and it is refused unless it is reachable from an `origin/` ref —
   pub takes a commit SHA as a git `ref:` exactly as it takes a tag, so
   consumers resolve against the very commit being released. Each consumer's
   `pubspec_overrides.yaml` is restored byte-for-byte afterwards (and removed
   if the wave generated it). One failing consumer refuses the whole wave
   before any tag exists: a "non-breaking" change that fails a consumer is
   breaking, and the refusal says to cut it with `--change rc` instead.
4. **Tag, push, wait.** One `<package>-v<version>` tag per package in
   dependency order, one `git push origin <tag>` each, and a pub.dev poll loop
   until the version appears before the next dependent is tagged. **The tag
   push is the publish** — the tag-triggered publish workflow does the upload,
   so the wave never runs `dart pub publish` for real.

`--change breaking` is refused outright, before any filesystem, process or
network work: a breaking base goes candidate-first and is promoted through the
separate `release validate-consumers` and `release promote` operations.

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
