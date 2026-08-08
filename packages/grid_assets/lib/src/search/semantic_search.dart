library;

import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show Bead;
import 'package:grid_sdk/grid_sdk.dart' as sdk;

import 'embedding_change_key.dart';
import 'embedding_index.dart';
import 'embedding_provider.dart';
import 'station_search.dart';

const int kSemanticHitLimitPerStore = 20;

class SemanticStoreInput {
  const SemanticStoreInput({required this.scope, required this.beads});

  final sdk.SubstationScope scope;
  final List<Bead> beads;
}

class SemanticStoreCoverage {
  const SemanticStoreCoverage({
    required this.store,
    required this.indexed,
    required this.stale,
    required this.unindexed,
  });

  final String store;
  final int indexed;
  final int stale;
  final int unindexed;

  Map<String, dynamic> toJson() => {
    'store': store,
    'indexed': indexed,
    'stale': stale,
    'unindexed': unindexed,
  };
}

class SemanticSearchHit {
  const SemanticSearchHit({required this.hit, required this.score});

  final SearchHit hit;
  final double score;

  Map<String, dynamic> toJson() => {
    ...hit.toJson(),
    'path': 'semantic',
    'score': score,
  };
}

sealed class SemanticSearchOutcome {
  const SemanticSearchOutcome({required this.stores});

  final List<SemanticStoreCoverage> stores;
  Map<String, dynamic> toJson();
}

class SemanticSearched extends SemanticSearchOutcome {
  const SemanticSearched({required super.stores, required this.hits});

  final List<SemanticSearchHit> hits;

  @override
  Map<String, dynamic> toJson() => {
    'outcome': 'searched',
    'stores': [for (final store in stores) store.toJson()],
    'hits': [for (final hit in hits) hit.toJson()],
    'hitCount': hits.length,
  };
}

class SemanticUnavailable extends SemanticSearchOutcome {
  const SemanticUnavailable({required super.stores, required this.reason});

  final String reason;

  @override
  Map<String, dynamic> toJson() => {
    'outcome': 'unavailable',
    'reason': reason,
    'stores': [for (final store in stores) store.toJson()],
    'hits': const <Object>[],
    'hitCount': 0,
  };
}

abstract interface class SemanticSearchBackend {
  Future<List<double>> embedQuery(String query);
  Future<List<EmbeddingIndexedBead>> indexedBeads(String store);
  Future<List<EmbeddingIndexHit>> nearest({
    required String store,
    required List<double> queryVector,
    required int limit,
  });
}

typedef SemanticSearchBackendMount =
    Future<SemanticSearchBackend> Function(String gridHome);

class DoltSemanticSearchBackend implements SemanticSearchBackend {
  const DoltSemanticSearchBackend({
    required DoltEmbeddingIndex index,
    required EmbeddingClient client,
  }) : _index = index,
       _client = client;

  final DoltEmbeddingIndex _index;
  final EmbeddingClient _client;

  @override
  Future<List<double>> embedQuery(String query) async =>
      (await _client.embed([query])).single;

  @override
  Future<List<EmbeddingIndexedBead>> indexedBeads(String store) =>
      _index.indexedBeads(store: store);

  @override
  Future<List<EmbeddingIndexHit>> nearest({
    required String store,
    required List<double> queryVector,
    required int limit,
  }) => _index.nearest(store: store, queryVector: queryVector, limit: limit);
}

Future<SemanticSearchBackend> mountSemanticSearchBackend(
  String gridHome,
) async {
  final registry = const EmbeddingProviderRegistry();
  final provider = registry.resolve();
  final binding = EmbeddingSiteBinding.loadJsonFile(
    '$gridHome/$kEmbeddingSiteBindingFile',
  );
  final index = await DoltEmbeddingIndex.open(
    gridHome: gridHome,
    identity: provider.indexIdentity,
  );
  final client = EmbeddingClient.mount(
    registry: registry,
    environment: Platform.environment,
    indexIdentity: index.identity,
    siteBinding: binding,
  );
  return DoltSemanticSearchBackend(index: index, client: client);
}

Future<SemanticSearchOutcome> runSemanticSearch({
  required String query,
  required String gridHome,
  required List<SemanticStoreInput> stores,
  SemanticSearchBackendMount mount = mountSemanticSearchBackend,
}) async {
  final coverage = <SemanticStoreCoverage>[];
  try {
    final backend = await mount(gridHome);
    final freshByStore = <String, Map<String, Bead>>{};
    for (final input in stores) {
      final indexedRows = await backend.indexedBeads(input.scope.name);
      final keys = {for (final row in indexedRows) row.beadId: row.changeKey};
      var indexed = 0;
      var stale = 0;
      var unindexed = 0;
      final fresh = <String, Bead>{};
      for (final bead in input.beads) {
        final stored = keys[bead.id];
        if (stored == null) {
          unindexed++;
        } else if (stored != embeddingChangeKey(bead)) {
          stale++;
        } else {
          indexed++;
          fresh[bead.id] = bead;
        }
      }
      coverage.add(
        SemanticStoreCoverage(
          store: input.scope.name,
          indexed: indexed,
          stale: stale,
          unindexed: unindexed,
        ),
      );
      freshByStore[input.scope.name] = fresh;
    }

    final queryVector = await backend.embedQuery(query);
    final ranked = <({SemanticSearchHit hit, int storeIx})>[];
    for (var storeIx = 0; storeIx < stores.length; storeIx++) {
      final input = stores[storeIx];
      final current = freshByStore[input.scope.name]!;
      if (current.isEmpty) continue;
      final nearest = await backend.nearest(
        store: input.scope.name,
        queryVector: queryVector,
        limit: kSemanticHitLimitPerStore,
      );
      final winners = <String, EmbeddingIndexHit>{};
      for (final candidate in nearest) {
        final bead = current[candidate.row.beadId];
        if (bead == null ||
            candidate.row.store != input.scope.name ||
            candidate.row.changeKey != embeddingChangeKey(bead)) {
          continue;
        }
        final prior = winners[bead.id];
        if (prior == null || candidate.distance < prior.distance) {
          winners[bead.id] = candidate;
        }
      }
      for (final entry in winners.entries) {
        final bead = current[entry.key]!;
        final winner = entry.value;
        ranked.add((
          storeIx: storeIx,
          hit: SemanticSearchHit(
            score: 1.0 - winner.distance,
            hit: SearchHit(
              beadId: bead.id,
              store: input.scope.name,
              status: bead.status.wire,
              issueType: bead.issueType.wire,
              title: bead.title,
              field: winner.row.field,
              snippet: winner.row.chunkText,
            ),
          ),
        ));
      }
    }
    ranked.sort((left, right) {
      final score = right.hit.score.compareTo(left.hit.score);
      if (score != 0) return score;
      final store = left.storeIx.compareTo(right.storeIx);
      if (store != 0) return store;
      return left.hit.hit.beadId.compareTo(right.hit.hit.beadId);
    });
    return SemanticSearched(
      stores: coverage,
      hits: [for (final value in ranked) value.hit],
    );
  } on Object catch (error) {
    return SemanticUnavailable(
      reason: '$error',
      stores: [
        ...coverage,
        for (final input in stores.skip(coverage.length))
          SemanticStoreCoverage(
            store: input.scope.name,
            indexed: 0,
            stale: 0,
            unindexed: input.beads.length,
          ),
      ],
    );
  }
}
