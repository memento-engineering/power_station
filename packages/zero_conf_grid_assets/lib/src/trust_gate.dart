/// The discovered-is-not-TRUSTED TRUST GATE (`SCRATCH-multi-root-federation.md`
/// D-Z6): entry from DISCOVERED (an mDNS/DNS-SD answer) to trusted/admitted
/// membership passes an allow-list decision — the SAME LAN-trust posture as
/// `federated_grid_assets`' `Peer.token` (a pre-shared secret configured
/// out-of-band by the operator, never the self-claimed hint a discovered
/// station broadcasts over an unauthenticated multicast). Reputation/ledger
/// trust is later work (ADR-0008's `Trust` seam) — allow-list is this round's
/// posture, same as the static membership file.
library;

import 'station_ad.dart';

/// Gates discovered [StationAd]s against a configured allow-list — D-Z6's
/// "discovered ≠ trusted." LOUD both ways per the guard principle: every
/// admission and every refusal is logged through [onLog], always naming the
/// claimed station id, so a gate that quietly drops a peer is never mistaken
/// for a peer that is simply offline.
class TrustGate {
  /// Creates a gate over [allowed]: station id → the token it must present
  /// (a `null` value entry means no token is required — being listed is
  /// enough, matching `Peer(token: null)`'s "the peer requires no token").
  /// [onLog] observes every admit/refuse decision; defaults to a no-op.
  TrustGate({required this.allowed, void Function(String)? onLog})
    : _onLog = onLog ?? ((String _) {});

  /// The allow-listed station ids and the token each must present.
  final Map<String, String?> allowed;

  final void Function(String) _onLog;

  /// Runs [ad] through the gate. Returns `true` (admitted) or `false`
  /// (refused); always LOUD, naming the claimed station id either way.
  bool admits(StationAd ad) {
    if (!allowed.containsKey(ad.station)) {
      _onLog(
        'discovery REFUSED "${ad.station}" @ ${ad.address}: not on the '
        'allow-list',
      );
      return false;
    }
    final expected = allowed[ad.station];
    if (expected != null && expected != ad.trustHint) {
      _onLog(
        'discovery REFUSED "${ad.station}" @ ${ad.address}: trust hint '
        'mismatch',
      );
      return false;
    }
    _onLog('discovery ADMITTED "${ad.station}" @ ${ad.address}');
    return true;
  }
}
