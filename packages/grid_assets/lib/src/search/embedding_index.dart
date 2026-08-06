library;

import 'dart:convert';
import 'dart:io';

/// The immutable provider shape that built one embedding index.
class EmbeddingIndexIdentity {
  const EmbeddingIndexIdentity({
    required this.providerId,
    required this.model,
    required this.dimensions,
  }) : assert(dimensions > 0);

  final String providerId;
  final String model;
  final int dimensions;

  @override
  bool operator ==(Object other) =>
      other is EmbeddingIndexIdentity &&
      other.providerId == providerId &&
      other.model == model &&
      other.dimensions == dimensions;

  @override
  int get hashCode => Object.hash(providerId, model, dimensions);
}

/// Thrown at open time when an existing index was built by another identity.
class EmbeddingIndexIdentityMismatch implements Exception {
  const EmbeddingIndexIdentityMismatch({
    required this.expected,
    required this.actual,
  });

  final EmbeddingIndexIdentity expected;
  final EmbeddingIndexIdentity actual;

  @override
  String toString() =>
      'EmbeddingIndexIdentityMismatch(expected: '
      '${expected.providerId}/${expected.model}/${expected.dimensions}, actual: '
      '${actual.providerId}/${actual.model}/${actual.dimensions}); delete '
      '.grid/embeddings and rebuild the derived index';
}

/// One persisted embedding chunk.
class EmbeddingIndexRow {
  const EmbeddingIndexRow({
    required this.store,
    required this.beadId,
    required this.field,
    required this.chunkIx,
    required this.changeKey,
    required this.chunkText,
    required this.vector,
  });

  final String store;
  final String beadId;
  final String field;
  final int chunkIx;
  final String changeKey;
  final String chunkText;
  final List<double> vector;
}

/// One nearest-neighbour row with the distance computed by Dolt.
class EmbeddingIndexHit {
  const EmbeddingIndexHit({required this.row, required this.distance});

  final EmbeddingIndexRow row;
  final double distance;
}

/// Measured chunk-row cardinality, never a capacity estimate.
class EmbeddingIndexRowCount {
  const EmbeddingIndexRowCount({required this.total, required this.byStore});

  final int total;
  final Map<String, int> byStore;
}

/// Result of one Dolt CLI invocation.
class DoltCommandResult {
  const DoltCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Injectable process seam for Dolt CLI invocations.
abstract interface class DoltCommandRunner {
  Future<DoltCommandResult> run(
    List<String> arguments, {
    required String workingDirectory,
  });
}

/// The real `dolt` CLI runner.
class ProcessDoltCommandRunner implements DoltCommandRunner {
  const ProcessDoltCommandRunner();

  @override
  Future<DoltCommandResult> run(
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    final result = await Process.run(
      'dolt',
      arguments,
      workingDirectory: workingDirectory,
    );
    return DoltCommandResult(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  }
}

/// Grid-home-owned, derived Dolt index shared by indexing and search.
class DoltEmbeddingIndex {
  DoltEmbeddingIndex._({
    required this.root,
    required this.identity,
    required DoltCommandRunner runner,
  }) : _runner = runner;

  /// Opens or creates `<gridHome>/.grid/embeddings` and validates identity.
  static Future<DoltEmbeddingIndex> open({
    required String gridHome,
    required EmbeddingIndexIdentity identity,
    DoltCommandRunner runner = const ProcessDoltCommandRunner(),
  }) async {
    if (identity.providerId.trim().isEmpty || identity.model.trim().isEmpty) {
      throw ArgumentError('providerId and model must be non-empty');
    }
    final root = '$gridHome/.grid/embeddings';
    final directory = Directory(root);
    final created = !directory.existsSync();
    if (created) directory.createSync(recursive: true);
    final index = DoltEmbeddingIndex._(
      root: root,
      identity: identity,
      runner: runner,
    );
    if (created || !Directory('$root/.dolt').existsSync()) {
      await index._run(const ['init', '--name', 'grid-embeddings']);
      await index._createSchema();
      await index._commit('initialize embedding index');
    } else {
      final actual = await index._readIdentity();
      if (actual != identity) {
        throw EmbeddingIndexIdentityMismatch(
          expected: identity,
          actual: actual,
        );
      }
    }
    return index;
  }

  final String root;
  final EmbeddingIndexIdentity identity;
  final DoltCommandRunner _runner;

  Future<void> _createSchema() async {
    await _sqlRun('''
CREATE TABLE embedding_index_metadata (
  singleton TINYINT NOT NULL PRIMARY KEY,
  provider_id VARCHAR(255) NOT NULL,
  model VARCHAR(255) NOT NULL,
  dimensions INT UNSIGNED NOT NULL,
  CHECK (singleton = 1)
);
INSERT INTO embedding_index_metadata VALUES
  (1, '${_sql(identity.providerId)}', '${_sql(identity.model)}', ${identity.dimensions});
CREATE TABLE bead_vectors (
  store VARCHAR(255) NOT NULL,
  bead_id VARCHAR(255) NOT NULL,
  field VARCHAR(64) NOT NULL,
  chunk_ix INT UNSIGNED NOT NULL,
  change_key VARCHAR(255) NOT NULL,
  chunk_text LONGTEXT NOT NULL,
  v VECTOR(${identity.dimensions}) NOT NULL,
  PRIMARY KEY (store, bead_id, field, chunk_ix)
);
CREATE VECTOR INDEX bead_vectors_v_idx ON bead_vectors (v);
''');
  }

  /// Replaces every chunk for one bead in one transaction and commits it.
  Future<void> replaceBead({
    required String store,
    required String beadId,
    required List<EmbeddingIndexRow> rows,
  }) async {
    for (final row in rows) {
      if (row.store != store || row.beadId != beadId) {
        throw ArgumentError('every row must belong to $store/$beadId');
      }
      _requireDimensions(row.vector);
    }
    final values = rows.map(_rowSql).join(',\n');
    await _sqlRun('''
START TRANSACTION;
DELETE FROM bead_vectors
 WHERE store = '${_sql(store)}' AND bead_id = '${_sql(beadId)}';
${rows.isEmpty ? '' : 'INSERT INTO bead_vectors (store, bead_id, field, chunk_ix, change_key, chunk_text, v) VALUES\n$values;'}
COMMIT;
''');
    await _commit('index $store/$beadId');
  }

  /// Returns top-k neighbours for [store], ordered by ascending distance.
  Future<List<EmbeddingIndexHit>> nearest({
    required String store,
    required List<double> queryVector,
    required int limit,
  }) async {
    _requireDimensions(queryVector);
    if (limit <= 0) throw ArgumentError.value(limit, 'limit');
    final vector = jsonEncode(queryVector);
    final rows = await _query('''
SELECT store, bead_id, field, chunk_ix, change_key, chunk_text,
       VEC_DISTANCE(v, VEC_FromText('${_sql(vector)}')) AS distance
  FROM bead_vectors
 WHERE store = '${_sql(store)}'
 ORDER BY distance ASC
 LIMIT $limit;
''');
    return [
      for (final value in rows)
        EmbeddingIndexHit(
          row: _rowFromJson(value, vector: queryVector),
          distance: (value['distance'] as num).toDouble(),
        ),
    ];
  }

  /// Counts the real persisted chunk rows, total and grouped by store.
  Future<EmbeddingIndexRowCount> rowCount() async {
    final rows = await _query(
      'SELECT store, COUNT(*) AS row_count FROM bead_vectors '
      'GROUP BY store ORDER BY store;',
    );
    final byStore = {
      for (final row in rows)
        '${row['store']}': (row['row_count'] as num).toInt(),
    };
    return EmbeddingIndexRowCount(
      total: byStore.values.fold(0, (sum, count) => sum + count),
      byStore: byStore,
    );
  }

  Future<EmbeddingIndexIdentity> _readIdentity() async {
    final rows = await _query(
      'SELECT provider_id, model, dimensions FROM '
      'embedding_index_metadata WHERE singleton = 1;',
    );
    if (rows.length != 1) {
      throw StateError('embedding index metadata must contain exactly one row');
    }
    final row = rows.single;
    return EmbeddingIndexIdentity(
      providerId: '${row['provider_id']}',
      model: '${row['model']}',
      dimensions: (row['dimensions'] as num).toInt(),
    );
  }

  Future<List<Map<String, dynamic>>> _query(String statement) async {
    final result = await _run(['sql', '-r', 'json', '-q', statement]);
    final decoded = jsonDecode(result.stdout) as Map<String, dynamic>;
    return (decoded['rows'] as List<dynamic>? ?? const [])
        .map((row) => (row as Map).cast<String, dynamic>())
        .toList();
  }

  Future<void> _sqlRun(String statement) async {
    await _run(['sql', '-q', statement]);
  }

  Future<DoltCommandResult> _run(List<String> arguments) async {
    final result = await _runner.run(arguments, workingDirectory: root);
    if (result.exitCode != 0) {
      throw StateError(
        'dolt ${arguments.first} failed (${result.exitCode}): ${result.stderr}',
      );
    }
    return result;
  }

  Future<void> _commit(String message) async {
    await _run(const ['add', '.']);
    await _run(['commit', '--allow-empty', '-m', message]);
  }

  void _requireDimensions(List<double> vector) {
    if (vector.length != identity.dimensions) {
      throw ArgumentError(
        'vector width ${vector.length} does not match ${identity.dimensions}',
      );
    }
  }

  String _rowSql(EmbeddingIndexRow row) =>
      "('${_sql(row.store)}', '${_sql(row.beadId)}', '${_sql(row.field)}', "
      "${row.chunkIx}, '${_sql(row.changeKey)}', '${_sql(row.chunkText)}', "
      "VEC_FromText('${_sql(jsonEncode(row.vector))}'))";

  static EmbeddingIndexRow _rowFromJson(
    Map<String, dynamic> row, {
    required List<double> vector,
  }) => EmbeddingIndexRow(
    store: '${row['store']}',
    beadId: '${row['bead_id']}',
    field: '${row['field']}',
    chunkIx: (row['chunk_ix'] as num).toInt(),
    changeKey: '${row['change_key']}',
    chunkText: '${row['chunk_text']}',
    vector: vector,
  );

  static String _sql(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", "''");
}
