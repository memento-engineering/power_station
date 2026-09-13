// Fakes — not mocks — for the two read-only seams the six VIABILITY filing
// rows are judged against. Offline by construction: nothing here spawns a
// shell or reads a store.
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart' show SubstationScope;

/// A [ValidationPlanProbe] that never spawns anything.
///
/// [outcomes] is keyed by SHELL name, so a fixture can make the lane shell
/// accept a plan that Dash refuses — the whole shape the portability row is
/// about. An unscripted shell PARSES, so a fixture pins only what it is about.
final class FakeValidationPlanProbe implements ValidationPlanProbe {
  /// Creates the probe.
  FakeValidationPlanProbe({this.outcomes = const {}});

  /// Per-shell scripted answers.
  final Map<String, PlanParse> outcomes;

  /// Every parse this probe was asked for, in order.
  final List<({String plan, String shell, String workingDirectory})> calls = [];

  @override
  Future<PlanParse> parse({
    required String plan,
    required String shell,
    required String workingDirectory,
  }) async {
    calls.add((plan: plan, shell: shell, workingDirectory: workingDirectory));
    return outcomes[shell] ?? const PlanParsed();
  }
}

/// A [FilingEvidenceSource] answering with ONE fixed value, recording which
/// beads it was asked about.
final class FakeFilingEvidenceSource implements FilingEvidenceSource {
  /// Creates the source over [evidence].
  FakeFilingEvidenceSource(this.evidence);

  /// The fixed answer.
  final FilingEvidence evidence;

  /// The bead ids collected for, in order.
  final List<String> collectedFor = [];

  @override
  Future<FilingEvidence> collect({
    required Bead bead,
    required String storeRoot,
  }) async {
    collectedFor.add(bead.id);
    return evidence;
  }
}

/// A [SubstationBeadSource] over a fixed per-root bead list, or a named read
/// failure for a root the fixture wants to prove is UNAVAILABLE rather than
/// empty.
final class FakeSubstationBeadSource implements SubstationBeadSource {
  /// Creates the source.
  FakeSubstationBeadSource({this.beadsByRoot = const {}, this.failFor = ''});

  /// Store root → the complete all-status bead list it answers with.
  final Map<String, List<Bead>> beadsByRoot;

  /// A root whose read THROWS. A partial union must never read as a smaller
  /// complete one.
  final String failFor;

  /// Every root read, in order.
  final List<String> reads = [];

  @override
  Future<List<Bead>> read(SubstationScope scope) async {
    reads.add(scope.root);
    if (scope.root == failFor) {
      throw StateError('store ${scope.root} refused the read');
    }
    return beadsByRoot[scope.root] ?? const [];
  }
}

/// Evidence in which everything the bead names already exists — the baseline a
/// fixture perturbs one row of.
FilingEvidence viableEvidence({
  Set<String> prefixes = const {},
  Set<String> ids = const {},
  Set<String> identities = const {},
  Set<String> aliases = const {},
}) => FilingEvidence(
  attachedPrefixes: prefixes,
  laneParse: const PlanParsed(),
  portabilityParse: const PlanParsed(),
  beads: BeadIdsRead(ids),
  decisions: DecisionsRead(identities: identities, aliases: aliases),
);
