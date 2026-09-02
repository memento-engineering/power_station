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
  /// Creates a deferred bead or updates its existing correlated bead.
  Future<void> upsertDeferred(GitHubIntakeRecord record);
}

/// The far-future date every GitHub intake bead is parked behind until a human
/// triages it.
///
/// This is the existing pending-state contract, moved verbatim onto the shared
/// builder. Bead `pow-5wo` owns replacing it with the eventual lifecycle.
const String kGitHubIntakeDeferUntil = '9999-12-31';

/// bd-CLI implementation of [GitHubIntakeStore].
///
/// Every call goes through [BdCliService] so the shared compatibility rails
/// cover this surface. Metadata is merged per key to preserve values owned by
/// other writers on the same bead.
final class BdGitHubIntakeStore implements GitHubIntakeStore {
  /// Creates a store over the shared bounded runner.
  BdGitHubIntakeStore(BdRunner runner) : _bd = BdCliService(runner);

  final BdCliService _bd;

  @override
  Future<void> upsertDeferred(GitHubIntakeRecord record) async {
    // Type-agnostic and closed-inclusive: a correlated bead may have been
    // re-typed or closed since intake, and both still count as correlated.
    final beads = (await _bd.listScope(
      externalRef: record.externalRef,
      includeClosed: true,
    )).beads;
    if (beads.length > 1) {
      throw StateError('multiple beads correlate to ${record.externalRef}');
    }
    if (beads case [final bead]) {
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
      defer: kGitHubIntakeDeferUntil,
      externalRef: record.externalRef,
      setMetadata: _metadata(record),
    );
  }

  /// The four always-present correlation keys. Flat, string-valued, and never
  /// removed, so per-key writes express the complete intake-owned map.
  Map<String, String> _metadata(GitHubIntakeRecord record) => <String, String>{
    'github.node_id': record.nodeId,
    'github.kind': record.kind,
    'github.repository': record.repository,
    'github.actor': record.actor,
  };
}
