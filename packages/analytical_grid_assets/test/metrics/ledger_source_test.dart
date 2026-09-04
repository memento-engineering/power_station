// The per-store read seam: READ-ONLY BY CONSTRUCTION. This suite pins the
// recorded argv — two all-status `bd list` reads and nothing else (A37).
import 'dart:convert';

import 'package:analytical_grid_assets/analytical_grid_assets.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:test/test.dart';

class _RecordingRunner implements BdRunner {
  _RecordingRunner(this.calls);

  final List<List<String>> calls;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(args);
    return BdResult(
      exitCode: 0,
      stdout: jsonEncode({
        'schema_version': kBdSchemaVersion,
        'data': <Object?>[],
      }),
      stderr: '',
    );
  }
}

void main() {
  test('the store read is exactly two all-status list reads (A37)', () async {
    final calls = <List<String>>[];
    final source = BdLedgerMetricsSource(
      runnerFor: (_) => _RecordingRunner(calls),
    );
    final projection = await source.project(
      MetricsStore(name: 'g', gridRoot: '/g'),
    );

    expect(calls, [
      ['list', '-t', 'session', '--all', '--json', '--limit', '0'],
      ['list', '-t', 'step', '--all', '--json', '--limit', '0'],
    ]);
    for (final verb in ['show', 'update', 'create', 'close', 'dep', 'export']) {
      expect(calls.expand((c) => c), isNot(contains(verb)));
    }
    expect(projection.sessionsById, isEmpty);
  });

  test(
    'the runner is spawned in the store runtime dir, not the work root',
    () async {
      final dirs = <String>[];
      await BdLedgerMetricsSource(
        runnerFor: (dir) {
          dirs.add(dir);
          return _RecordingRunner([]);
        },
      ).project(MetricsStore(name: 'g', gridRoot: '/g'));
      expect(dirs, ['/g/.grid']);
    },
  );
}
