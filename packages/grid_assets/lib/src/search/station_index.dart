/// Provider-sized prose chunking and incremental embedding-index writes.
library;

import 'dart:convert';
import 'dart:math';

import 'package:beads_dart/beads_dart.dart';
import 'package:crypto/crypto.dart';
import 'package:grid_sdk/grid_sdk.dart';

import 'embedding_index.dart';
import 'embedding_provider.dart';
import 'station_search.dart';

typedef IndexBeadChangeKey = String? Function(Bead bead);

String? _noChangeKey(Bead bead) => null;

class ProseChunk {
  const ProseChunk(this.field, this.chunkIx, this.text);

  final String field;
  final int chunkIx;
  final String text;
}

/// Splits prose into rune-safe windows at 60% of the provider context limit.
///
/// Each declared token budgets four runes and adjacent windows overlap by 20%
/// so boundary-spanning sentences remain represented in at least one chunk.
class ProseChunker {
  const ProseChunker({
    required this.contextWindowTokens,
    this.charactersPerToken = 4,
    this.windowFraction = .60,
    this.overlapFraction = .20,
  });

  final int contextWindowTokens;
  final int charactersPerToken;
  final double windowFraction;
  final double overlapFraction;

  List<ProseChunk> chunkBead(Bead bead) => [
    ...chunkField('title', bead.title),
    ...chunkField('description', bead.description),
    ...chunkField('design', bead.design),
    ...chunkField('acceptance_criteria', bead.acceptanceCriteria),
    ...chunkField('notes', bead.notes),
    ...chunkField('close_reason', bead.closeReason),
  ];

  List<ProseChunk> chunkField(String field, String text) {
    if (contextWindowTokens <= 0 ||
        charactersPerToken <= 0 ||
        windowFraction <= 0 ||
        windowFraction > 1 ||
        overlapFraction < 0 ||
        overlapFraction >= 1) {
      throw ArgumentError('invalid chunk geometry');
    }
    if (text.trim().isEmpty) return const [];
    final values = text.runes.toList(growable: false);
    final width = max(
      1,
      (contextWindowTokens * charactersPerToken * windowFraction).floor(),
    );
    final overlap = max(1, (width * overlapFraction).floor());
    final stride = max(1, width - overlap);
    final result = <ProseChunk>[];
    for (var start = 0; start < values.length; start += stride) {
      final end = min(start + width, values.length);
      result.add(
        ProseChunk(
          field,
          result.length,
          String.fromCharCodes(values.sublist(start, end)),
        ),
      );
      if (end == values.length) break;
    }
    return result;
  }
}

sealed class StoreIndexOutcome {
  const StoreIndexOutcome(this.store);
  final SubstationScope store;
  Map<String, Object?> toJson();
}

final class StoreIndexed extends StoreIndexOutcome {
  const StoreIndexed(
    super.store, {
    required this.embedded,
    required this.skippedFresh,
    required this.removed,
  });
  final int embedded;
  final int skippedFresh;
  final int removed;
  @override
  Map<String, Object?> toJson() => {
    'substation': store.name,
    'outcome': 'indexed',
    'embedded': embedded,
    'skippedFresh': skippedFresh,
    'removed': removed,
  };
}

final class IndexStoreAbsent extends StoreIndexOutcome {
  const IndexStoreAbsent(super.store, {required this.reason});
  final String reason;
  @override
  Map<String, Object?> toJson() => {
    'substation': store.name,
    'outcome': 'absent',
    'reason': reason,
  };
}

final class IndexStoreFailed extends StoreIndexOutcome {
  const IndexStoreFailed(super.store, {required this.reason});
  final String reason;
  @override
  Map<String, Object?> toJson() => {
    'substation': store.name,
    'outcome': 'failed',
    'reason': reason,
  };
}

class StationIndexReport {
  const StationIndexReport({required this.full, required this.stores});
  final bool full;
  final List<StoreIndexOutcome> stores;
  bool get succeeded => stores.every((value) => value is StoreIndexed);
  Map<String, Object?> toJson() => {
    'full': full,
    'stores': [for (final value in stores) value.toJson()],
  };
}

class StationIndexService {
  const StationIndexService({
    required DoltEmbeddingIndex index,
    required EmbeddingClient client,
    required EmbeddingProvider provider,
    SubstationBeadSource source = const BdExportBeadSource(),
    IndexBeadChangeKey changeKeyOf = _noChangeKey,
    DirectoryProbe dirExists = defaultDirectoryProbe,
  }) : _index = index,
       _client = client,
       _provider = provider,
       _source = source,
       _changeKeyOf = changeKeyOf,
       _dirExists = dirExists;

  final DoltEmbeddingIndex _index;
  final EmbeddingClient _client;
  final EmbeddingProvider _provider;
  final SubstationBeadSource _source;
  final IndexBeadChangeKey _changeKeyOf;
  final DirectoryProbe _dirExists;

  Future<StationIndexReport> indexRoster({
    required List<SubstationScope> roster,
    bool full = false,
  }) async {
    final outcomes = <StoreIndexOutcome>[];
    for (final scope in roster) {
      if (!_dirExists('${scope.root}/.beads')) {
        outcomes.add(
          IndexStoreAbsent(
            scope,
            reason: '${scope.root}/.beads does not exist',
          ),
        );
        continue;
      }
      try {
        final beads = await _source.read(scope);
        final persisted = await _index.changeKeys(store: scope.name);
        final currentIds = beads.map((bead) => bead.id).toSet();
        final removed = persisted.keys
            .where((id) => !currentIds.contains(id))
            .toList(growable: false);
        final stale = <_PendingBead>[];
        var skippedFresh = 0;
        for (final bead in beads) {
          final key = _freshnessKey(bead);
          if (!full && persisted[bead.id] == key) {
            skippedFresh++;
          } else {
            stale.add(_PendingBead(bead, key));
          }
        }

        final chunker = ProseChunker(
          contextWindowTokens: _provider.contextWindowTokens,
        );
        final chunks = <ProseChunk>[];
        final ranges = <({int start, int end})>[];
        for (final pending in stale) {
          final start = chunks.length;
          chunks.addAll(chunker.chunkBead(pending.bead));
          ranges.add((start: start, end: chunks.length));
        }
        final vectors = await _client.embed([
          for (final chunk in chunks) chunk.text,
        ]);
        if (vectors.length != chunks.length) {
          throw StateError(
            'embedding provider returned ${vectors.length} vectors for '
            '${chunks.length} chunks',
          );
        }
        final rowsByBead = <List<EmbeddingIndexRow>>[];
        for (var beadIx = 0; beadIx < stale.length; beadIx++) {
          final pending = stale[beadIx];
          final range = ranges[beadIx];
          rowsByBead.add([
            for (var chunkIx = range.start; chunkIx < range.end; chunkIx++)
              EmbeddingIndexRow(
                store: scope.name,
                beadId: pending.bead.id,
                field: chunks[chunkIx].field,
                chunkIx: chunks[chunkIx].chunkIx,
                changeKey: pending.key,
                chunkText: chunks[chunkIx].text,
                vector: vectors[chunkIx],
              ),
          ]);
        }

        for (var beadIx = 0; beadIx < stale.length; beadIx++) {
          await _index.replaceBead(
            store: scope.name,
            beadId: stale[beadIx].bead.id,
            rows: rowsByBead[beadIx],
          );
        }
        await _index.deleteBeads(store: scope.name, beadIds: removed);
        outcomes.add(
          StoreIndexed(
            scope,
            embedded: chunks.length,
            skippedFresh: skippedFresh,
            removed: removed.length,
          ),
        );
      } catch (error) {
        outcomes.add(IndexStoreFailed(scope, reason: '$error'));
      }
    }
    return StationIndexReport(full: full, stores: outcomes);
  }

  String _freshnessKey(Bead bead) {
    final supplied = _changeKeyOf(bead);
    if (supplied != null && supplied.trim().isNotEmpty) return supplied;
    final fields = <(String, String)>[
      ('title', bead.title),
      ('description', bead.description),
      ('design', bead.design),
      ('acceptance_criteria', bead.acceptanceCriteria),
      ('notes', bead.notes),
      ('close_reason', bead.closeReason),
    ];
    final prose = fields
        .map((field) => '${field.$1}\u0000${field.$2}')
        .join('\u0001');
    return sha256.convert(utf8.encode(prose)).toString();
  }
}

class _PendingBead {
  const _PendingBead(this.bead, this.key);
  final Bead bead;
  final String key;
}
