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
