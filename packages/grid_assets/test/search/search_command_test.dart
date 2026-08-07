// The `search` Command (bead `pow-ovh`) — the THIN CLI adapter over
// StationSearchService: parses argv, resolves the roster from the injected
// resident-station context, renders the report. Everything behavioral is the
// service's (station_search_test.dart); this suite pins the adapter contract
// a composing station (`space search <query>`) and the discover skill rely
// on. Offline: fake source, fake probe, captured sinks.
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show Bead, BeadStatus, IssueType;
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:test/test.dart';

/// The composing station's resident-station context: two literal seats.
class _StationDelegate extends sdk.GridDelegate {
  _StationDelegate(this.root);

  @override
  final String root;
  var disposed = false;

  @override
  Seed build(TreeContext context, sdk.GridConfiguration configuration) =>
      sdk.RawAssetGrid(
        root: root,
        assets: [
          sdk.Station(
            name: 'test-station',
            assets: [
              sdk.Substations(
                substations: [
                  sdk.Substation('alpha', '/roots/alpha', prefix: 'al'),
                  sdk.Substation('beta', '/roots/beta'),
                ],
              ),
            ],
          ),
        ],
      );

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _FakeBeadSource implements SubstationBeadSource {
  _FakeBeadSource(this.byRoot);

  final Map<String, List<Bead>> byRoot;

  @override
  Future<List<Bead>> read(sdk.SubstationScope scope) async =>
      byRoot[scope.root] ?? const [];
}

class _SemanticBackend implements SemanticSearchBackend {
  _SemanticBackend(this.beads);

  final Map<String, List<Bead>> beads;

  @override
  Future<List<double>> embedQuery(String query) async => const [1];

  @override
  Future<List<EmbeddingIndexedBead>> indexedBeads(String store) async => [
    for (final bead in beads[store] ?? const <Bead>[])
      EmbeddingIndexedBead(
        beadId: bead.id,
        changeKey: embeddingChangeKey(bead),
      ),
  ];

  @override
  Future<List<EmbeddingIndexHit>> nearest({
    required String store,
    required List<double> queryVector,
    required int limit,
  }) async {
    final bead = (beads[store] ?? const <Bead>[]).firstOrNull;
    if (bead == null) return const [];
    return [
      EmbeddingIndexHit(
        row: EmbeddingIndexRow(
          store: store,
          beadId: bead.id,
          field: 'design',
          chunkIx: 0,
          changeKey: embeddingChangeKey(bead),
          chunkText: 'semantic winning chunk',
          vector: const [1],
        ),
        distance: 0.2,
      ),
    ];
  }
}

void main() {
  final beads = {
    '/roots/alpha': const [
      Bead(
        id: 'al-1',
        title: 'Decide the wiring standard',
        closeReason: 'ratified: soldered flux joints',
        status: BeadStatus.closed,
        issueType: IssueType.decision,
      ),
    ],
    '/roots/beta': const [
      Bead(id: 'beta-1', title: 'flux chore', issueType: IssueType.chore),
    ],
  };

  ({
    CommandRunner<int> runner,
    _StationDelegate Function() lastDelegate,
    StringBuffer out,
    StringBuffer err,
  })
  harness({
    Set<String>? existing,
    String Function()? gridHomeDefault,
    SemanticSearchBackendMount? semanticMount,
  }) {
    final out = StringBuffer();
    final err = StringBuffer();
    _StationDelegate? last;
    final runner = CommandRunner<int>('space', 'test station')
      ..addCommand(
        SearchCommand(
          delegate: (gridHome) => last = _StationDelegate(gridHome),
          gridHomeDefault: gridHomeDefault ?? () => '/grid/home',
          service: StationSearchService(
            source: _FakeBeadSource(beads),
            dirExists:
                (existing ?? {'/roots/alpha/.beads', '/roots/beta/.beads'})
                    .contains,
            semanticBackendMount:
                semanticMount ??
                (_) async => throw StateError('provider offline'),
          ),
          out: out,
          err: err,
        ),
      );
    return (runner: runner, lastDelegate: () => last!, out: out, err: err);
  }

  test('`search --json <query>` emits ONE JSON object carrying the '
      'structured report — the surface the discover skill consumes', () async {
    final h = harness();
    final code = await h.runner.run(['search', '--json', 'flux']);

    expect(code, 0);
    final json = jsonDecode(h.out.toString()) as Map<String, dynamic>;
    expect(json['query'], 'flux');
    expect(json['hitCount'], 2);
    expect(json.keys, ['query', 'stores', 'hitCount', 'semantic']);
    expect((json['semantic'] as Map)['outcome'], 'unavailable');
    final stores = json['stores'] as List;
    expect(
      stores.map((s) => (s as Map)['substation']),
      ['alpha', 'beta'],
      reason: 'roster order, from the mounted resident-station context',
    );
    final hit = ((stores.first as Map)['hits'] as List).single as Map;
    expect(hit['id'], 'al-1');
    expect(hit['status'], 'closed');
    expect(hit['type'], 'decision');
  });

  test(
    'always-on semantics are additive, marked, scored, and have no flag',
    () async {
      final byStore = {
        'alpha': beads['/roots/alpha']!,
        'beta': beads['/roots/beta']!,
      };
      final h = harness(semanticMount: (_) async => _SemanticBackend(byStore));
      final command = h.runner.commands['search']!;
      expect(command.argParser.options, isNot(contains('semantic')));
      expect(await h.runner.run(['search', '--json', 'flux']), 0);
      final json = jsonDecode(h.out.toString()) as Map<String, dynamic>;
      final semantic = json['semantic'] as Map<String, dynamic>;
      expect(semantic['outcome'], 'searched');
      expect(semantic['stores'], [
        {'store': 'alpha', 'indexed': 1, 'stale': 0, 'unindexed': 0},
        {'store': 'beta', 'indexed': 1, 'stale': 0, 'unindexed': 0},
      ]);
      final hit = (semantic['hits'] as List).first as Map;
      expect(hit['path'], 'semantic');
      expect(hit['score'], closeTo(0.8, 1e-12));
      expect(hit['snippet'], 'semantic winning chunk');
    },
  );

  test('multi-word rest args join into one query', () async {
    final h = harness();
    final code = await h.runner.run(['search', 'wiring', 'standard']);
    expect(code, 0);
    expect(h.out.toString(), contains('al-1'));
    expect(h.out.toString(), contains('1 hit(s) across 2 substation(s)'));
  });

  test(
    'the human render names every store outcome and the hit fields',
    () async {
      final h = harness(existing: {'/roots/alpha/.beads'});
      final code = await h.runner.run(['search', 'flux']);
      expect(code, 0);
      final text = h.out.toString();
      expect(text, contains('alpha: 1 hit(s)'));
      expect(text, contains('close_reason: ratified: soldered flux joints'));
      expect(text, contains('beta: store absent'));
      expect(
        text,
        contains('semantic: unavailable — Bad state: provider offline'),
      );
    },
  );

  test(
    'no query is a usage refusal: exit 64, loud on stderr, no search run',
    () async {
      final h = harness();
      final code = await h.runner.run(['search']);
      expect(code, 64);
      expect(h.err.toString(), contains('a query is required'));
      expect(h.out.toString(), isEmpty);
    },
  );

  test('a roster whose every store is absent is a loud non-answer: exit 1, '
      'report still rendered', () async {
    final h = harness(existing: const {});
    final code = await h.runner.run(['search', 'flux']);
    expect(code, 1);
    expect(h.out.toString(), contains('store absent'));
  });

  test(
    'the command OWNS the delegate it asked for — disposed after the run',
    () async {
      final h = harness();
      await h.runner.run(['search', 'flux']);
      expect(h.lastDelegate().disposed, isTrue);
    },
  );

  test(
    'grid home defaults, trims, and normalizes before delegate construction',
    () async {
      final defaulted = harness(gridHomeDefault: () => '/grid/default/../home');
      expect(await defaulted.runner.run(['search', 'flux']), 0);
      expect(defaulted.lastDelegate().root, '/grid/home');

      final overridden = harness(gridHomeDefault: () => '/unused');
      expect(
        await overridden.runner.run([
          'search',
          '--grid-home',
          '  /grid/override/../home  ',
          'flux',
        ]),
        0,
      );
      expect(overridden.lastDelegate().root, '/grid/home');
    },
  );

  test(
    'a relative grid home is a LOUD usage refusal with the roster reason',
    () async {
      final h = harness(gridHomeDefault: () => 'relative/grid');

      await expectLater(
        h.runner.run(['search', 'flux']),
        throwsA(
          isA<UsageException>()
              .having((error) => error.message, 'message', contains('ABSOLUTE'))
              .having(
                (error) => error.message,
                'reason',
                contains('re-imports the ambience the v3 model kills'),
              ),
        ),
      );
    },
  );
}
