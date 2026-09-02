import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:test/test.dart';

/// A scripted [BdRunner] (fake, not mock) recording every argv and stdin.
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

const beadTitle =
    '[GitHub issue memento/power_station#42] Fix the flux capacitor';
const description =
    'GitHub issue opened by @nico in memento/power_station#42.\n'
    'GitHub node_id: I_1\n'
    '\n'
    'Details.';
const metadataArgs = [
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

/// The fleet binary's create help: whole-object metadata, no per-key writes.
BdResult createHelpWithoutSetMetadata() => const BdResult(
  exitCode: 0,
  stdout: 'Flags:\n      --metadata string   Set custom metadata (JSON)\n',
  stderr: '',
);

BdResult createHelpWithSetMetadata() => const BdResult(
  exitCode: 0,
  stdout: 'Flags:\n      --set-metadata stringArray   Set metadata key=value\n',
  stderr: '',
);

void main() {
  setUp(BdCliService.resetCreateMetadataCapabilityForTesting);

  group('BdGitHubIntakeStore', () {
    test('correlates, then creates a deferred chore bead (fleet bd)', () async {
      final runner = FakeBdRunner([
        ok([]),
        createHelpWithoutSetMetadata(),
        ok({'id': 'pow-new'}),
        ok(<String, Object?>{}),
      ]);

      await BdGitHubIntakeStore(runner).upsertDeferred(record);

      expect(runner.argvs, hasLength(4));
      expect(runner.argvs[0], [
        'list',
        '--all',
        '--external-ref',
        'github:I_1',
        '--json',
        '--limit',
        '0',
      ]);
      expect(runner.argvs[1], ['create', '--help']);
      expect(runner.argvs[2], [
        'create',
        '--json',
        '--actor',
        'grid-controller',
        '--title',
        beadTitle,
        '--type',
        'chore',
        '--priority',
        '2',
        '--description',
        description,
        '--defer',
        '9999-12-31',
        '--external-ref',
        'github:I_1',
      ]);
      expect(runner.argvs[3], [
        'update',
        'pow-new',
        '--json',
        '--actor',
        'grid-controller',
        ...metadataArgs,
      ]);
      for (final argv in runner.argvs) {
        expect(argv, isNot(contains('--metadata')));
        expect(argv, isNot(contains('--ephemeral')));
        expect(argv, isNot(contains('--status')));
      }
    });

    test(
      'creates in one spawn when create advertises --set-metadata',
      () async {
        final runner = FakeBdRunner([
          ok([]),
          createHelpWithSetMetadata(),
          ok({'id': 'pow-new'}),
        ]);

        await BdGitHubIntakeStore(runner).upsertDeferred(record);

        expect(runner.argvs, hasLength(3));
        expect(runner.argvs.last, [
          'create',
          '--json',
          '--actor',
          'grid-controller',
          '--title',
          beadTitle,
          '--type',
          'chore',
          '--priority',
          '2',
          '--description',
          description,
          '--defer',
          '9999-12-31',
          '--external-ref',
          'github:I_1',
          ...metadataArgs,
        ]);
      },
    );

    test(
      'updates the sole correlated bead without readiness mutation',
      () async {
        final runner = FakeBdRunner([
          ok([
            {'id': 'pow-existing'},
          ]),
          ok(<String, Object?>{}),
        ]);

        await BdGitHubIntakeStore(runner).upsertDeferred(record);

        expect(runner.argvs, hasLength(2));
        expect(runner.argvs.last, [
          'update',
          'pow-existing',
          '--json',
          '--actor',
          'grid-controller',
          '--title',
          beadTitle,
          '--body-file',
          '-',
          ...metadataArgs,
        ]);
        expect(runner.stdins.last, description);
        expect(runner.argvs.last, isNot(contains('--metadata')));
        expect(runner.argvs.last, isNot(contains('--defer')));
        expect(runner.argvs.last, isNot(contains('--status')));
        expect(runner.argvs.last, isNot(contains('show')));
      },
    );

    test('fails loudly for multiple correlations or a malformed id', () async {
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

      final empty = FakeBdRunner([
        ok([
          {'id': ''},
        ]),
      ]);
      await expectLater(
        BdGitHubIntakeStore(empty).upsertDeferred(record),
        throwsA(isA<BdParseException>()),
      );

      // A non-string id is refused by the typed decode one layer down.
      for (final id in <Object?>[null, 3]) {
        final malformed = FakeBdRunner([
          ok([
            {'id': id},
          ]),
        ]);
        await expectLater(
          BdGitHubIntakeStore(malformed).upsertDeferred(record),
          throwsA(isA<TypeError>()),
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
