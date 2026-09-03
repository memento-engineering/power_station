import 'package:beads_dart/beads_dart.dart';

/// Thin GitHub entity content projected into a bead.
class GitHubIntakeRecord {
  /// Creates one normalized intake record.
  const GitHubIntakeRecord({
    required this.nodeId,
    required this.kind,
    required this.repository,
    required this.number,
    required this.actor,
    required this.title,
    required this.body,
  });

  final String nodeId;
  final String kind;
  final String repository;
  final int number;
  final String actor;
  final String title;
  final String body;

  String get externalRef => 'github:$nodeId';
  String get beadTitle => '[GitHub $kind $repository#$number] $title';
  String get description => [
    'GitHub $kind opened by @$actor in $repository#$number.',
    'GitHub node_id: $nodeId',
    if (body.isNotEmpty) '',
    if (body.isNotEmpty) body,
  ].join('\n');
}

/// Upserts GitHub intake records by stable node id.
abstract interface class GitHubIntakeStore {
  /// Creates an OPEN, unstamped bead or updates its existing correlated bead.
  Future<void> upsert(GitHubIntakeRecord record);
}

/// bd-CLI implementation of [GitHubIntakeStore].
///
/// Every spawn rides [BdCliService] over the injected [BdRunner], so this
/// surface inherits beads_dart's bd compatibility rails — the corpus replay,
/// the fixture-drift audit, and the exact-argv pins in
/// `beads_dart/test/services/bd_cli_service_test.dart` — instead of
/// hand-building argv that no rail covers (bead `pow-0nvg`).
///
/// **Metadata is written per key, never as one whole object.** The four intake
/// keys ride [BdCliService.update]'s merge channel (one set-metadata flag per
/// key), whose server-side merge overwrites named keys and preserves absent
/// ones. bd's whole-object create-time metadata form REPLACES the map, which
/// would clobber the `validation_plan` and approval-stamp keys other writers
/// own on the same bead (`the_grid#bd-create-metadata-rides-a-follow-up-update`).
///
/// **Intake beads are filed OPEN, with no parking date and no approval
/// marker.** Absence of the approve verb's `grid.approved_*` stamp IS the
/// pending state: it is readiness-based rather than time-based, and it never
/// fires on its own
/// (`power_station#github-intake-files-open-and-unstamped`). This store passes
/// no date argument and writes no approval key and no label; `grid_assets`'s
/// `lib/src/filing/approve_command.dart` remains the only writer of the stamp
/// that `mountEligibilityFindings` reads, so an intake bead is VISIBLE to
/// `bd ready` and still unmountable until a human runs the approve verb.
final class BdGitHubIntakeStore implements GitHubIntakeStore {
  /// Creates a store over the shared bounded runner.
  BdGitHubIntakeStore(BdRunner runner) : _bd = BdCliService(runner);

  final BdCliService _bd;

  @override
  Future<void> upsert(GitHubIntakeRecord record) async {
    final correlated = (await _bd.listScope(
      externalRef: record.externalRef,
      includeClosed: true,
    )).beads;
    if (correlated.length > 1) {
      throw StateError('multiple beads correlate to ${record.externalRef}');
    }
    if (correlated case [final bead]) {
      if (bead.id.isEmpty) {
        throw const BdParseException('correlated bead has no string id');
      }
      await _bd.update(
        bead.id,
        title: record.beadTitle,
        description: record.description,
        mergeMetadata: _metadata(record),
      );
      return;
    }
    await _bd.create(
      title: record.beadTitle,
      type: IssueType.chore,
      priority: 2,
      description: record.description,
      externalRef: record.externalRef,
      setMetadata: _metadata(record),
    );
  }

  Map<String, String> _metadata(GitHubIntakeRecord record) => <String, String>{
    'github.node_id': record.nodeId,
    'github.kind': record.kind,
    'github.repository': record.repository,
    'github.actor': record.actor,
  };
}
