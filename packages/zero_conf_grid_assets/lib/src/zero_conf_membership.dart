/// Ties zero-conf discovery to a `federated_grid_assets` [Membership]:
/// browse → gate ([TrustGate], D-Z6) → shape per topology ([Topology], D-B1).
/// This is AL-7's whole point — "topology opinions as configuration over
/// `federated_grid_assets`' seams" — so a station runner wires it alongside
/// its `ServeCommand`/`LeaseCommand` and gets a live [Membership] off the LAN
/// instead of (or in addition to) a static `MembershipLoader` file.
library;

import 'dart:async';

import 'package:federated_grid_assets/federated_grid_assets.dart';

import 'mdns_browser.dart';
import 'topology.dart';

/// A discovery loop: one [browse]/gate/shape pass at a time
/// ([ZeroConfMembership.discover]), or a repeating [Stream] of fresh snapshots
/// ([ZeroConfMembership.watch]).
class ZeroConfMembership {
  /// Creates a loop browsing with [browser] and resolving admitted ads
  /// through [resolver], always excluding [selfStation] from its own result.
  ZeroConfMembership({
    required this.browser,
    required this.resolver,
    required this.selfStation,
    this.browseTimeout = const Duration(seconds: 5),
  });

  /// The mDNS/DNS-SD browse seam (real or, in tests, a fake canned stream).
  final MdnsBrowser browser;

  /// The trust-gated topology opinion ([Topology.mesh]/[Topology.gridHub]).
  final TopologyResolver resolver;

  /// This station's own id — never included in the resolved [Membership].
  final String selfStation;

  /// How long each [browse] call listens before the pass concludes.
  final Duration browseTimeout;

  /// One discovery pass → the resolved [Membership].
  Future<Membership> discover() async {
    final ads = await browser.browse(timeout: browseTimeout).toList();
    return resolver.resolve(ads, selfStation: selfStation);
  }

  /// Repeats [discover] every [refreshEvery], emitting a fresh [Membership]
  /// snapshot on each pass — including an unchanged one; deciding what to do
  /// with a repeat (D-Z2's reconcile-from-membership doctrine) is the
  /// consumer's job, not this seam's.
  Stream<Membership> watch({
    Duration refreshEvery = const Duration(seconds: 30),
  }) async* {
    while (true) {
      yield await discover();
      await Future<void>.delayed(refreshEvery);
    }
  }
}
