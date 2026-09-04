/// Durable semantic-search recall evaluation and its explicit live runner.
///
/// This is one of the pack's two retained-corpus measurements; the other is
/// `code/spec_contract_shadow.dart`, which measures the spec record grammar
/// and states there exactly what the two share and what they deliberately do
/// not. The shared piece is [recordArtifact], the one writer of a recorded
/// artifact.
library;

import 'dart:convert';
import 'dart:io';

import 'package:grid_sdk/grid_sdk.dart' as sdk;

import '../io/recorded_artifact.dart';
import 'semantic_search.dart';
import 'station_search.dart';

/// Whether a corpus row is a genuine lexical miss or an existing lexical hit.
enum RecallCaseKind { recall, control }

/// One durable query and the bead ids that count as its expected answer.
class RecallCase {
  /// Creates a recall case.
  const RecallCase({
    required this.name,
    required this.query,
    required this.expectedBeadIds,
  });

  /// Stable fixture key used to associate a search report with this case.
  final String name;

  /// Natural-language search query.
  final String query;

  /// Bead ids any one of which satisfies this case.
  final List<String> expectedBeadIds;
}

/// A versioned recall corpus, exact-id guard, and recorded live baseline.
class RecallSet {
  /// Creates a decoded recall set.
  const RecallSet({
    required this.cases,
    required this.exactIdGuard,
    required this.baseline,
  });

  /// The query/expected-bead cases in durable order.
  final List<RecallCase> cases;

  /// Bead id whose lexical id-field match must remain first.
  final String exactIdGuard;

  /// First-green rank and score, keyed by case name.
  final Map<String, ({int rank, double score})> baseline;

  /// Decodes and validates the version-1 recall-set JSON contract.
  factory RecallSet.fromJsonString(String source) {
    final dynamic value;
    try {
      value = jsonDecode(source);
    } on FormatException {
      rethrow;
    }
    if (value is! Map<String, dynamic> || value['version'] != 1) {
      throw const FormatException('recall set: version must be 1');
    }
    final rows = value['cases'];
    final guard = value['exactIdGuard'];
    if (rows is! List ||
        rows.isEmpty ||
        guard is! String ||
        guard.trim().isEmpty) {
      throw const FormatException(
        'recall set: cases and exactIdGuard are required',
      );
    }
    final cases = <RecallCase>[];
    final names = <String>{};
    for (final row in rows) {
      if (row is! Map<String, dynamic> ||
          row['name'] is! String ||
          row['query'] is! String ||
          row['expectedBeadIds'] is! List) {
        throw const FormatException('recall set: malformed case');
      }
      final rawIds = row['expectedBeadIds'] as List;
      if (rawIds.any((id) => id is! String)) {
        throw const FormatException('recall set: malformed case');
      }
      final ids = rawIds.cast<String>();
      final name = row['name'] as String;
      final query = row['query'] as String;
      if (name.trim().isEmpty ||
          !names.add(name) ||
          query.trim().isEmpty ||
          ids.isEmpty ||
          ids.any((id) => id.trim().isEmpty)) {
        throw const FormatException('recall set: invalid case values');
      }
      cases.add(RecallCase(name: name, query: query, expectedBeadIds: ids));
    }
    final baseline = <String, ({int rank, double score})>{};
    final baselineRows = value['baseline'];
    if (baselineRows is! Map<String, dynamic>) {
      throw const FormatException('recall set: baseline object is required');
    }
    for (final MapEntry(:key, :value) in baselineRows.entries) {
      if (value is! Map<String, dynamic> ||
          value['rank'] is! int ||
          value['score'] is! num ||
          (value['rank'] as int) < 1 ||
          !(value['score'] as num).isFinite) {
        throw const FormatException('recall set: malformed baseline');
      }
      baseline[key] = (
        rank: value['rank'] as int,
        score: (value['score'] as num).toDouble(),
      );
    }
    return RecallSet(cases: cases, exactIdGuard: guard, baseline: baseline);
  }
}

/// The evaluated outcome for one recall case.
class RecallCaseResult {
  /// Creates a case result.
  const RecallCaseResult({
    required this.recallCase,
    required this.kind,
    required this.semanticRank,
    required this.semanticScore,
  });

  /// The source corpus row.
  final RecallCase recallCase;

  /// Whether the row is eligible recall or a lexical control.
  final RecallCaseKind kind;

  /// One-based rank of the first expected semantic hit, or null on a miss.
  final int? semanticRank;

  /// Score of the first expected semantic hit, or null on a miss.
  final double? semanticScore;

  /// Whether this row passes; controls never count as retrieval failures.
  bool get passed => kind == RecallCaseKind.control || semanticRank != null;
}

/// Aggregate recall and exact-id ordering results for one run.
class RecallRunResult {
  /// Creates an aggregate run result.
  const RecallRunResult({required this.cases, required this.idGuardPassed});

  /// Evaluated corpus rows in corpus order.
  final List<RecallCaseResult> cases;

  /// Whether the exact id remained the first lexical id-field hit.
  final bool idGuardPassed;

  /// Number of genuine lexical misses in the denominator.
  int get recallTotal =>
      cases.where((c) => c.kind == RecallCaseKind.recall).length;

  /// Number of genuine lexical misses found semantically.
  int get recallFound =>
      cases.where((c) => c.kind == RecallCaseKind.recall && c.passed).length;

  /// Number of cases excluded because lexical search already found them.
  int get controlCount =>
      cases.where((c) => c.kind == RecallCaseKind.control).length;

  /// Whether every genuine miss and the exact-id ordering guard passed.
  bool get passed => recallFound == recallTotal && idGuardPassed;
}

/// Evaluates recorded or live station search reports against [recallSet].
RecallRunResult evaluateRecall({
  required RecallSet recallSet,
  required Map<String, StationSearchReport> reports,
}) {
  final results = <RecallCaseResult>[];
  for (final recallCase in recallSet.cases) {
    final report = reports[recallCase.name];
    if (report == null || report.semantic is! SemanticSearched) {
      throw StateError('recall: ${recallCase.name} has no semantic result');
    }
    final lexicalIds = report.hits.map((hit) => hit.beadId).toSet();
    final kind = recallCase.expectedBeadIds.any(lexicalIds.contains)
        ? RecallCaseKind.control
        : RecallCaseKind.recall;
    final semantic = (report.semantic as SemanticSearched).hits;
    int? rank;
    double? score;
    for (var index = 0; index < semantic.length; index++) {
      if (recallCase.expectedBeadIds.contains(semantic[index].hit.beadId)) {
        rank = index + 1;
        score = semantic[index].score;
        break;
      }
    }
    results.add(
      RecallCaseResult(
        recallCase: recallCase,
        kind: kind,
        semanticRank: rank,
        semanticScore: score,
      ),
    );
  }
  final guard = reports['id-hit-still-first'];
  final guardLexical = guard?.hits ?? const <SearchHit>[];
  final guardPassed =
      guardLexical.isNotEmpty &&
      guardLexical.first.beadId == recallSet.exactIdGuard &&
      guardLexical.first.field == 'id';
  return RecallRunResult(cases: results, idGuardPassed: guardPassed);
}

/// Injectable process seam matching the command invocation used by [runRecall].
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Runs the durable corpus through the vended search command.
///
/// The normal mode is read-only. [recordBaseline] atomically updates the
/// corpus only after a completely green run. Returns zero on green and one on
/// a search refusal or failed recall/guard.
Future<int> runRecall({
  required String runner,
  required String gridHome,
  required bool recordBaseline,
  ProcessRunner processRunner = Process.run,
}) async {
  if (runner.trim().isEmpty || !File(gridHome).isAbsolute) {
    return 1;
  }
  final file = File('test/search/fixtures/semantic_recall_set.json');
  try {
    final set = RecallSet.fromJsonString(await file.readAsString());
    final reports = <String, StationSearchReport>{};
    for (final recallCase in set.cases) {
      reports[recallCase.name] = await _runStationSearch(
        processRunner: processRunner,
        runner: runner,
        gridHome: gridHome,
        query: recallCase.query,
      );
    }
    reports['id-hit-still-first'] = await _runStationSearch(
      processRunner: processRunner,
      runner: runner,
      gridHome: gridHome,
      query: set.exactIdGuard,
    );
    final result = evaluateRecall(recallSet: set, reports: reports);
    for (final row in result.cases) {
      stdout.writeln(
        '${row.recallCase.name}: ${row.kind.name} '
        'rank=${row.semanticRank ?? "miss"} '
        'score=${row.semanticScore ?? "miss"}',
      );
    }
    stdout.writeln(
      'recall=${result.recallFound}/${result.recallTotal} '
      'controls=${result.controlCount} '
      'guard=${result.idGuardPassed ? "1/1" : "0/1"}',
    );
    if (recordBaseline && result.passed) {
      await _writeBaselineAtomically(file, set, result);
    }
    return result.passed ? 0 : 1;
  } on Object catch (error) {
    stderr.writeln('recall: $error');
    return 1;
  }
}

Future<StationSearchReport> _runStationSearch({
  required ProcessRunner processRunner,
  required String runner,
  required String gridHome,
  required String query,
}) async {
  final process = await processRunner(runner, [
    'search',
    '--json',
    query,
    '--grid-home',
    gridHome,
  ]);
  if (process.exitCode != 0) {
    throw StateError('search exited ${process.exitCode}: ${process.stderr}');
  }
  final dynamic decoded;
  try {
    decoded = jsonDecode(process.stdout as String);
  } on Object catch (error) {
    throw FormatException('search returned non-JSON output', error);
  }
  if (decoded is! Map<String, dynamic> ||
      decoded['query'] is! String ||
      decoded['stores'] is! List ||
      decoded['semantic'] is! Map<String, dynamic>) {
    throw const FormatException('search report: absent expected sections');
  }
  final semanticJson = decoded['semantic'] as Map<String, dynamic>;
  if (semanticJson['outcome'] != 'searched' ||
      semanticJson['stores'] is! List ||
      semanticJson['hits'] is! List) {
    throw StateError('search report: semantic result unavailable');
  }
  final coverage = <SemanticStoreCoverage>[];
  for (final row in semanticJson['stores'] as List) {
    if (row is! Map<String, dynamic> ||
        row['store'] is! String ||
        row['indexed'] is! int ||
        row['stale'] is! int ||
        row['unindexed'] is! int) {
      throw const FormatException('search report: malformed coverage');
    }
    final item = SemanticStoreCoverage(
      store: row['store'] as String,
      indexed: row['indexed'] as int,
      stale: row['stale'] as int,
      unindexed: row['unindexed'] as int,
    );
    if (item.stale > 0 || item.unindexed > 0) {
      throw StateError('search report: incomplete semantic coverage');
    }
    coverage.add(item);
  }
  final stores = <StoreSearchOutcome>[];
  for (final row in decoded['stores'] as List) {
    if (row is! Map<String, dynamic> ||
        row['substation'] is! String ||
        row['prefix'] is! String ||
        row['root'] is! String ||
        row['outcome'] is! String) {
      throw const FormatException('search report: malformed store');
    }
    final scope = sdk.SubstationScope(
      name: row['substation'] as String,
      prefix: row['prefix'] as String,
      root: row['root'] as String,
    );
    if (row['outcome'] != 'searched' ||
        row['beadsSearched'] is! int ||
        row['hits'] is! List) {
      throw StateError('search report: store was not searched');
    }
    stores.add(
      StoreSearched(
        scope,
        beadsSearched: row['beadsSearched'] as int,
        hits: _decodeHits(row['hits'] as List),
      ),
    );
  }
  final semanticHits = <SemanticSearchHit>[];
  for (final row in semanticJson['hits'] as List) {
    if (row is! Map<String, dynamic> || row['score'] is! num) {
      throw const FormatException('search report: malformed semantic hit');
    }
    semanticHits.add(
      SemanticSearchHit(
        hit: _decodeHit(row),
        score: (row['score'] as num).toDouble(),
      ),
    );
  }
  return StationSearchReport(
    query: decoded['query'] as String,
    stores: stores,
    semantic: SemanticSearched(stores: coverage, hits: semanticHits),
  );
}

List<SearchHit> _decodeHits(List<dynamic> rows) => [
  for (final row in rows)
    if (row is Map<String, dynamic>)
      _decodeHit(row)
    else
      throw const FormatException('search report: malformed lexical hit'),
];

SearchHit _decodeHit(Map<String, dynamic> row) {
  const keys = ['id', 'store', 'status', 'type', 'title', 'field', 'snippet'];
  if (keys.any((key) => row[key] is! String)) {
    throw const FormatException('search report: malformed hit');
  }
  return SearchHit(
    beadId: row['id'] as String,
    store: row['store'] as String,
    status: row['status'] as String,
    issueType: row['type'] as String,
    title: row['title'] as String,
    field: row['field'] as String,
    snippet: row['snippet'] as String,
  );
}

Future<void> _writeBaselineAtomically(
  File file,
  RecallSet set,
  RecallRunResult result,
) async {
  final baseline = <String, Object?>{};
  for (final row in result.cases) {
    if (row.semanticRank != null && row.semanticScore != null) {
      baseline[row.recallCase.name] = {
        'rank': row.semanticRank,
        'score': row.semanticScore,
      };
    }
  }
  final json = <String, Object?>{
    'version': 1,
    'cases': [
      for (final row in set.cases)
        {
          'name': row.name,
          'query': row.query,
          'expectedBeadIds': row.expectedBeadIds,
        },
    ],
    'exactIdGuard': set.exactIdGuard,
    'baseline': baseline,
  };
  await recordArtifact(
    file,
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );
}
