## 0.3.0

- PROMOTED from 0.3.0-rc.5. This is the stable release of the 0.3.0 line; the code is the
  candidate's, unchanged. Every family dependency constraint is rewritten from its prerelease
  form to the stable one, because pub refuses a stable package that depends on a prerelease.
- Consumers on a `^0.3.0-rc.N` constraint resolve this automatically: a caret range admits the
  release above its own prereleases, so no downstream pubspec edit is required to pick it up.

## 0.3.0-rc.5

- Fixed: `LeaseManager` owns its wait deadlines. An injected `timerFactory` seam (defaults to `Timer.new`) arms ONE timer at the earliest held or queued deadline and re-arms it on every acquire, release, and expiry, so `leaseWait` is enforced without an external `reapInterval` pump; `close()` cancels it and `StationServer.close` calls it. `tick()` and `reapInterval` are unchanged and `serve_command.dart` is untouched (pow-gc1, #258).

## 0.3.0-rc.4

- Added: `Peer.controlDoor`, an optional StationControl door endpoint carried through JSON (omitted when unset, part of equality) so a discovered peer resolves its control door without a second service type (pow-awgw, #255).

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
