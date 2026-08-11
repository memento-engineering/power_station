import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:test/test.dart';

class FakeBdRunner implements BdRunner {
  FakeBdRunner(this.results);

  final List<BdResult> results;
  final List<List<String>> argvs = [];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(List<String>.of(args));
    return results.removeAt(0);
  }
}

const record = GitHubIntakeRecord(
  nodeId: 'I_1',
  kind: 'issue',
  repository: 'memento/power_station',
  number: 42,
  actor: 'nico',
  title: 'Fix the flux capacitor',
  body: 'Details.',
);

BdResult ok(Object? data, {int schemaVersion = 1}) => BdResult(
  exitCode: 0,
  stdout: jsonEncode({'schema_version': schemaVersion, 'data': data}),
  stderr: '',
);

void main() {
  group('BdGitHubIntakeStore', () {
    test('creates a durable deferred core bead for a new node id', () async {
      final runner = FakeBdRunner([
        ok([]),
        ok({'id': 'pow-new'}),
      ]);

      await BdGitHubIntakeStore(runner).upsertDeferred(record);

      expect(runner.argvs.first, [
        'list',
        '--all',
        '--external-ref',
        'github:I_1',
        '--limit',
        '0',
        '--json',
      ]);
      final create = runner.argvs.last;
      expect(create.first, 'create');
      expect(create, containsAllInOrder(['--type', 'chore']));
      expect(create, containsAllInOrder(['--defer', '9999-12-31']));
      expect(create, containsAllInOrder(['--external-ref', 'github:I_1']));
      expect(create, isNot(contains('--ephemeral')));
      expect(create, isNot(contains('--status')));
      final metadata = jsonDecode(create[create.indexOf('--metadata') + 1]);
      expect(metadata, containsPair('github.node_id', 'I_1'));
    });

    test(
      'updates the sole correlated bead without readiness mutation',
      () async {
        final runner = FakeBdRunner([
          ok([
            {'id': 'pow-existing'},
          ]),
          ok({}),
        ]);

        await BdGitHubIntakeStore(runner).upsertDeferred(record);

        expect(runner.argvs, hasLength(2));
        expect(runner.argvs.last.take(2), ['update', 'pow-existing']);
        expect(runner.argvs.last, isNot(contains('create')));
        expect(runner.argvs.last, isNot(contains('--status')));
        expect(runner.argvs.last, isNot(contains('--defer')));
      },
    );

    test('fails loudly for multiple correlations or malformed ids', () async {
      final multiple = FakeBdRunner([
        ok([
          {'id': 'a'},
          {'id': 'b'},
        ]),
      ]);
      await expectLater(
        BdGitHubIntakeStore(multiple).upsertDeferred(record),
        throwsStateError,
      );
      for (final id in <Object?>[null, '', 3]) {
        final malformed = FakeBdRunner([
          ok([
            {'id': id},
          ]),
        ]);
        await expectLater(
          BdGitHubIntakeStore(malformed).upsertDeferred(record),
          throwsA(isA<BdParseException>()),
        );
      }
    });

    test('fails loudly for command failure and schema drift', () async {
      final failed = FakeBdRunner([
        const BdResult(exitCode: 1, stdout: '', stderr: 'nope'),
      ]);
      await expectLater(
        BdGitHubIntakeStore(failed).upsertDeferred(record),
        throwsA(isA<BdCommandFailed>()),
      );
      final drifted = FakeBdRunner([ok([], schemaVersion: 2)]);
      await expectLater(
        BdGitHubIntakeStore(drifted).upsertDeferred(record),
        throwsA(isA<BdSchemaDriftException>()),
      );
      final malformed = FakeBdRunner([
        ok({'id': 'not-a-list'}),
      ]);
      await expectLater(
        BdGitHubIntakeStore(malformed).upsertDeferred(record),
        throwsA(isA<BdParseException>()),
      );
    });
  });
}
