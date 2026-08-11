import 'dart:convert';

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

/// bd-CLI implementation of [GitHubIntakeStore].
final class BdGitHubIntakeStore implements GitHubIntakeStore {
  /// Creates a store over the shared bounded runner.
  const BdGitHubIntakeStore(this._runner);

  final BdRunner _runner;

  @override
  Future<void> upsertDeferred(GitHubIntakeRecord record) async {
    final rows = (await _run(<String>[
      'list',
      '--all',
      '--external-ref',
      record.externalRef,
      '--limit',
      '0',
      '--json',
    ])).dataList;
    if (rows.length > 1) {
      throw StateError('multiple beads correlate to ${record.externalRef}');
    }
    if (rows case [final row]) {
      final id = row['id'];
      if (id is! String || id.isEmpty) {
        throw const BdParseException('correlated bead has no string id');
      }
      await _run(<String>[
        'update',
        id,
        '--title',
        record.beadTitle,
        '--description',
        record.description,
        '--metadata',
        _metadata(record),
        '--actor',
        'grid-controller',
        '--json',
      ]);
      return;
    }
    await _run(<String>[
      'create',
      '--title',
      record.beadTitle,
      '--description',
      record.description,
      '--type',
      'chore',
      '--priority',
      '2',
      '--defer',
      '9999-12-31',
      '--external-ref',
      record.externalRef,
      '--metadata',
      _metadata(record),
      '--actor',
      'grid-controller',
      '--json',
    ]);
  }

  String _metadata(GitHubIntakeRecord record) => jsonEncode(<String, String>{
    'github.node_id': record.nodeId,
    'github.kind': record.kind,
    'github.repository': record.repository,
    'github.actor': record.actor,
  });

  Future<BdEnvelope> _run(List<String> args) async {
    final result = await _runner.run(args);
    if (!result.ok) {
      throw BdCommandFailed.fromOutput(
        command: <String>['bd', ...args],
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
      );
    }
    return BdEnvelope.parse(result.stdout);
  }
}
