# Changelog

## 0.3.0-rc.3

- Adopts grid_engine 0.3.0-rc.12 (floor); doc comments name `StationDriver` instead of the deleted `StationKernel` (#193, #195). No API change.

## 0.3.0-rc.2

- Breaking: none new in this candidate — it continues the 0.3.0 line so that
  main and pub.dev agree.
- The federation bus serves multiple lease kinds (#100); model environments
  route through typed seats (pow-n6n.2, #168).
## 0.3.0-rc.1

- Breaking: adopts `grid_engine ^0.3.0-rc.1` from the_grid's prerelease wave.
  Published as a prerelease because pub requires a package depending on a
  prerelease to be one itself. No API change of its own.

## 0.2.0

- Breaking: rides the 0.2.0 substrate wave — grid_engine ^0.2.0,
  genesis_tree ^0.2.0.

## 0.1.0

- Initial release: cross-station federation impls — the HTTP station bus, the owner-authoritative lease manager, static membership, git-over-LAN sync, and the serve/lease CLI commands.
