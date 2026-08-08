import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:test/test.dart';

class _Backend implements SemanticSearchBackend {
  _Backend({required this.beads, required this.hits});

  final Map<String, List<EmbeddingIndexedBead>> beads;
  final Map<String, List<EmbeddingIndexHit>> hits;
  final List<String> calls = [];
  String? failAt;

  @override
  Future<List<double>> embedQuery(String query) async {
    calls.add('embed:$query');
    if (failAt == 'embed') throw StateError('provider offline');
    return const [1, 0];
  }

  @override
  Future<List<EmbeddingIndexedBead>> indexedBeads(String store) async {
    calls.add('indexed:$store');
    if (failAt == 'indexed:$store') throw StateError('index broken');
    return beads[store] ?? const [];
  }

  @override
  Future<List<EmbeddingIndexHit>> nearest({
    required String store,
    required List<double> queryVector,
    required int limit,
  }) async {
    calls.add('nearest:$store');
    if (failAt == 'nearest:$store') throw StateError('nearest broken');
    expect(limit, kSemanticHitLimitPerStore);
    return hits[store] ?? const [];
  }
}

EmbeddingIndexHit _hit(
  String store,
  Bead bead,
  String field,
  String text,
  double distance,
) => EmbeddingIndexHit(
  row: EmbeddingIndexRow(
    store: store,
    beadId: bead.id,
    field: field,
    chunkIx: 0,
    changeKey: embeddingChangeKey(bead),
    chunkText: text,
    vector: const [1, 0],
  ),
  distance: distance,
);

void main() {
  const alpha = Bead(id: 'al-1', title: 'current alpha');
  const betaA = Bead(id: 'be-2', title: 'current beta two');
  const betaB = Bead(id: 'be-1', title: 'current beta one');
  const stale = Bead(id: 'al-2', title: 'changed since indexing');
  const unindexed = Bead(id: 'al-3', title: 'never indexed');
  final inputs = [
    SemanticStoreInput(
      scope: const sdk.SubstationScope(
        name: 'alpha',
        root: '/alpha',
        prefix: 'al',
      ),
      beads: const [alpha, stale, unindexed],
    ),
    SemanticStoreInput(
      scope: const sdk.SubstationScope(
        name: 'beta',
        root: '/beta',
        prefix: 'be',
      ),
      beads: const [betaB, betaA],
    ),
  ];

  test(
    'classifies freshness, embeds once, deduplicates chunks and ranks',
    () async {
      final backend = _Backend(
        beads: {
          'alpha': [
            EmbeddingIndexedBead(
              beadId: alpha.id,
              changeKey: embeddingChangeKey(alpha),
            ),
            const EmbeddingIndexedBead(beadId: 'al-2', changeKey: 'old'),
          ],
          'beta': [
            for (final bead in [betaA, betaB])
              EmbeddingIndexedBead(
                beadId: bead.id,
                changeKey: embeddingChangeKey(bead),
              ),
          ],
        },
        hits: {
          'alpha': [
            _hit('alpha', alpha, 'title', 'losing chunk', 0.4),
            _hit('alpha', alpha, 'design', 'winning chunk', 0.2),
            _hit('alpha', stale, 'title', 'stale row', 0.01),
          ],
          'beta': [
            _hit('beta', betaA, 'title', 'tie two', 0.2),
            _hit('beta', betaB, 'title', 'tie one', 0.2),
          ],
        },
      );
      final outcome =
          await runSemanticSearch(
                query: 'conceptual wording',
                gridHome: '/grid/home',
                stores: inputs,
                mount: (_) async => backend,
              )
              as SemanticSearched;

      expect(backend.calls, [
        'indexed:alpha',
        'indexed:beta',
        'embed:conceptual wording',
        'nearest:alpha',
        'nearest:beta',
      ]);
      expect(outcome.stores.first.toJson(), {
        'store': 'alpha',
        'indexed': 1,
        'stale': 1,
        'unindexed': 1,
      });
      expect(outcome.hits.map((hit) => hit.hit.beadId), [
        'al-1',
        'be-1',
        'be-2',
      ]);
      expect(outcome.hits.first.hit.field, 'design');
      expect(outcome.hits.first.hit.snippet, 'winning chunk');
      expect(outcome.hits.first.score, closeTo(0.8, 1e-12));
      expect(outcome.hits.first.toJson(), containsPair('path', 'semantic'));
    },
  );

  test(
    'every boundary failure is named and coverage remains complete',
    () async {
      final backend = _Backend(beads: const {}, hits: const {})
        ..failAt = 'indexed:beta';
      final unavailable =
          await runSemanticSearch(
                query: 'query',
                gridHome: '/grid/home',
                stores: inputs,
                mount: (_) async => backend,
              )
              as SemanticUnavailable;
      expect(unavailable.reason, contains('index broken'));
      expect(unavailable.stores, hasLength(2));
      expect(unavailable.stores.last.unindexed, 2);

      final mountFailure =
          await runSemanticSearch(
                query: 'query',
                gridHome: '/grid/home',
                stores: inputs,
                mount: (_) async => throw StateError('provider offline'),
              )
              as SemanticUnavailable;
      expect(mountFailure.reason, contains('provider offline'));
      expect(mountFailure.stores.map((store) => store.unindexed), [3, 2]);
    },
  );
}
