import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:test/test.dart';

class FakeBdRunner implements BdRunner {
  FakeBdRunner(this.results);

  final List<BdResult> results;
  final List<List<String>> argvs = [];
  final List<String?> stdins = [];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(List<String>.of(args));
    stdins.add(stdin);
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

const expectedTitle =
    '[GitHub issue memento/power_station#42] Fix the flux capacitor';

const expectedBody =
    'GitHub issue opened by @nico in memento/power_station#42.\n'
    'GitHub node_id: I_1\n'
    '\n'
    'Details.';

/// The per-key metadata channel: one flag pair per key, never one whole object.
const expectedSetMetadata = <String>[
  '--set-metadata',
  'github.node_id=I_1',
  '--set-metadata',
  'github.kind=issue',
  '--set-metadata',
  'github.repository=memento/power_station',
  '--set-metadata',
  'github.actor=nico',
];

BdResult ok(Object? data, {int schemaVersion = 1}) => BdResult(
  exitCode: 0,
  stdout: jsonEncode({'schema_version': schemaVersion, 'data': data}),
  stderr: '',
);

void main() {
  group('BdGitHubIntakeStore', () {
    test('creates a durable OPEN core bead for a new node id', () async {
      final runner = FakeBdRunner([
        ok([]),
        ok({'id': 'pow-new'}),
        ok({'id': 'pow-new'}),
      ]);

      await BdGitHubIntakeStore(runner).upsert(record);

      expect(runner.argvs, hasLength(3));
      expect(runner.argvs[0], [
        'list',
        '--all',
        '--external-ref',
        'github:I_1',
        '--json',
        '--limit',
        '0',
      ]);
      expect(runner.argvs[1], [
        'create',
        '--json',
        '--actor',
        'grid-controller',
        '--title',
        expectedTitle,
        '--type',
        'chore',
        '--priority',
        '2',
        '--description',
        expectedBody,
        '--external-ref',
        'github:I_1',
      ]);
      expect(runner.argvs[2], [
        'update',
        'pow-new',
        '--json',
        '--actor',
        'grid-controller',
        ...expectedSetMetadata,
      ]);
      final flattened = runner.argvs.expand((argv) => argv).toList();
      expect(flattened, isNot(contains('--metadata')));
      expect(flattened, isNot(contains('--ephemeral')));
      expect(flattened, isNot(contains('--status')));
    });

    test(
      'the create argv carries no parking date and no approval marker',
      () async {
        final runner = FakeBdRunner([
          ok([]),
          ok({'id': 'pow-new'}),
          ok({'id': 'pow-new'}),
        ]);

        await BdGitHubIntakeStore(runner).upsert(record);

        final flattened = runner.argvs.expand((argv) => argv).toList();
        expect(flattened, isNot(contains('--defer')));
        expect(flattened.where((arg) => arg.contains('9999')), isEmpty);
        expect(
          flattened.where((arg) => arg.contains('grid.approved')),
          isEmpty,
          reason: 'the approve verb is the only writer of the approval stamp',
        );
        expect(flattened, isNot(contains('--label')));
        expect(flattened, isNot(contains('--add-label')));
      },
    );

    test(
      'updates the sole correlated bead without readiness mutation',
      () async {
        final runner = FakeBdRunner([
          ok([
            {'id': 'pow-existing'},
          ]),
          ok({'id': 'pow-existing'}),
        ]);

        await BdGitHubIntakeStore(runner).upsert(record);

        expect(runner.argvs, hasLength(2));
        expect(runner.argvs[1], [
          'update',
          'pow-existing',
          '--json',
          '--actor',
          'grid-controller',
          '--title',
          expectedTitle,
          '--body-file',
          '-',
          ...expectedSetMetadata,
        ]);
        expect(runner.stdins[1], expectedBody);
        expect(runner.argvs[1], isNot(contains('--metadata')));
        expect(runner.argvs[1], isNot(contains('--defer')));
        expect(runner.argvs[1], isNot(contains('--status')));
        expect(runner.argvs[1], isNot(contains('create')));
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
        BdGitHubIntakeStore(multiple).upsert(record),
        throwsStateError,
      );

      final empty = FakeBdRunner([
        ok([
          {'id': ''},
        ]),
      ]);
      await expectLater(
        BdGitHubIntakeStore(empty).upsert(record),
        throwsA(isA<BdParseException>()),
      );

      for (final id in <Object?>[null, 3]) {
        final malformed = FakeBdRunner([
          ok([
            {'id': id},
          ]),
        ]);
        await expectLater(
          BdGitHubIntakeStore(malformed).upsert(record),
          throwsA(isA<TypeError>()),
        );
      }
    });

    test('fails loudly for command failure and schema drift', () async {
      final failed = FakeBdRunner([
        const BdResult(exitCode: 1, stdout: '', stderr: 'nope'),
      ]);
      await expectLater(
        BdGitHubIntakeStore(failed).upsert(record),
        throwsA(isA<BdCommandFailed>()),
      );
      final drifted = FakeBdRunner([ok([], schemaVersion: 2)]);
      await expectLater(
        BdGitHubIntakeStore(drifted).upsert(record),
        throwsA(isA<BdSchemaDriftException>()),
      );
      final malformed = FakeBdRunner([
        ok({'id': 'not-a-list'}),
      ]);
      await expectLater(
        BdGitHubIntakeStore(malformed).upsert(record),
        throwsA(isA<BdParseException>()),
      );
    });
  });
}
