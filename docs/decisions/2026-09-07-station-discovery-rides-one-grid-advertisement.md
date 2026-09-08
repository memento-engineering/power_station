---
status: accepted
date: 2026-09-07
decision-makers:
  - "Nico Spencer"
consulted: []
informed: []
register:
  spec: 1
  slug: station-discovery-rides-one-grid-advertisement
  surfaces:
    - "packages/zero_conf_grid_assets/**"
    - "packages/federated_grid_assets/lib/src/membership.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: pow-awgw
  legacy-id: null
---

# Station discovery rides one `_grid._tcp` advertisement

## Context and Problem Statement

A cockpit has to find a station's CONTROL DOOR — the `host:port` where station
control answers HTTP `/status` and the authenticated WebSocket `/stream` —
without being told the port. The station already advertises itself on the LAN:
`zero_conf_grid_assets` publishes one `_grid._tcp` service instance per station
(`kGridServiceType`, the D-B1/D-Z8 pin), whose TXT record carried four fields —
station id, federation-bus endpoint, hosted substation prefixes, trust hint.

Two shapes were on the table. The framework side proposed a SECOND service type,
`_grid-cockpit._tcp`, advertised alongside the first, so the control door had its
own discovery namespace. The alternative was to extend the record the station
already publishes.

A second service type means a station announces itself twice, a browser issues
two PTR lookups and correlates the answers by instance name, and the two
advertisements can disagree or arrive out of order — a station whose cockpit ad
lands without its grid ad is discoverable as neither.

## Decision Outcome

A station advertises ONCE. The control door is a field of the existing
`_grid._tcp` TXT record, under the short key `door`, carrying a bare `host:port`
authority — no scheme, no route. The proposal to add `_grid-cockpit._tcp` is
REJECTED, and no second service type is introduced for station discovery.

Concretely:

* `kGridServiceType` stays exactly `_grid._tcp`, one instance per station.
* `StationAd.controlDoor` is OPTIONAL, and its absence is the DEFAULT posture:
  a station advertises a door only when it has been told to bind one. `toTxt`
  emits `door` only when there is one, so a record from a station that exposes
  no door is byte-identical to the record shipped before the field existed, and
  an already-published ad decodes exactly as it did. TXT records are
  size-bounded — hence a three-letter key, and hence "absent" rather than an
  empty value.
* The door reaches consumers through the seams that already exist. It rides
  `StationAd.toPeer` into `federated_grid_assets`' `Peer.controlDoor` (likewise
  optional, likewise omitted from JSON when null), so the browse path, the
  topology resolver, the trust gate, and the membership shape acquire the field
  without a second parser, a second packet, or a second lookup.

The door is DISTINCT from the bus address: `Peer.address` remains the federation
bus, and a station may answer the two on different ports. Advertising a door is
not trusting one — an ad still passes the trust gate before it reaches
membership (D-Z6, discovered ≠ trusted).

### Consequences

* Good, because a client picks a station and dials its control door from a
  single browse, with nothing to correlate and no partial-discovery state.
* Good, because the wire stays backward compatible in both directions: an older
  browser ignores an unknown key, and a newer browser reads a door-less record
  as a station with no door.
* Good, because the framework-side cockpit browser now has one record to read
  rather than a service type to register and maintain.
* Bad, because every future station-discovery datum inherits this record's size
  budget; a payload that does not fit a TXT record will force this decision to
  be revisited rather than extended.
* Neutral: this entry governs only what is ADVERTISED. Binding the control door
  on a LAN interface, and composing the advertiser into a station at all, are
  separate changes elsewhere — `zero_conf_grid_assets` is composed into no
  station today.
