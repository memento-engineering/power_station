## 0.3.0

- PROMOTED from 0.3.0-rc.2. This is the stable release of the 0.3.0 line; the code is the
  candidate's, unchanged. Every family dependency constraint is rewritten from its prerelease
  form to the stable one, because pub refuses a stable package that depends on a prerelease.
- Consumers on a `^0.3.0-rc.N` constraint resolve this automatically: a caret range admits the
  release above its own prereleases, so no downstream pubspec edit is required to pick it up.

## 0.3.0-rc.2

- Added: `StationAd.controlDoor` and `Peer.controlDoor` — the advertisement's TXT carries the StationControl door endpoint (`door=host:port`, optional, omitted when unset) so a browser can resolve the control door from the one `_grid._tcp` ad; the token stays out of the ad (pow-awgw, #255).
- Floors `federated_grid_assets` to `^0.3.0-rc.4`, where `Peer.controlDoor` was introduced.

# Changelog

## 0.3.0-rc.1

- Breaking: tracks `federated_grid_assets ^0.3.0-rc.1`. Published as a
  prerelease for the same reason. No API change of its own.

## 0.2.0

- Breaking: rides the 0.2.0 substrate wave via federated_grid_assets ^0.2.0.

## 0.1.0

- Initial release: zero-conf mDNS/DNS-SD discovery and topology opinions applied over federated_grid_assets.
