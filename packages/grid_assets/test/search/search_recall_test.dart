import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_root.dart';

/// The corpus path RELATIVE to whichever root holds it — the checked-in package
/// root here, a temp copy under [_inFixtureRoot].
final String _setPath = p.join(
  'test',
  'search',
  'fixtures',
  'semantic_recall_set.json',
);
final String _reportsPath = p.join(
  'test',
  'search',
  'fixtures',
  'semantic_recall_reports.json',
);

/// The checked-in copy of a corpus fixture, anchored on the package root rather
/// than on the process cwd.
File _checkedIn(String relative) => File(p.join(packageRoot(), relative));

RecallSet loadRecallSetFixture() =>
    RecallSet.fromJsonString(_checkedIn(_setPath).readAsStringSync());

SearchHit _hit(String id, String field) => SearchHit(
  beadId: id,
  store: 'power_station',
  status: 'closed',
  issueType: 'task',
  title: 'recorded $id',
  field: field,
  snippet: 'recorded fixture',
);

StationSearchReport _report(
  String name,
  List<SearchHit> lexical,
  List<SemanticSearchHit> semantic,
) => StationSearchReport(
  query: name,
  stores: [
    StoreSearched(
      const sdk.SubstationScope(
        name: 'power_station',
        prefix: 'tg',
        root: '/grid/power_station',
      ),
      hits: lexical,
      beadsSearched: 1,
    ),
  ],
  semantic: SemanticSearched(
    stores: const [
      SemanticStoreCoverage(
        store: 'power_station',
        indexed: 1,
        stale: 0,
        unindexed: 0,
      ),
    ],
    hits: semantic,
  ),
);

Map<String, StationSearchReport> loadReportFixtures() {
  final decoded =
      jsonDecode(_checkedIn(_reportsPath).readAsStringSync()) as Map;
  expect(decoded['version'], 1);
  final rows = decoded['reports'] as Map<String, dynamic>;
  return rows.map((name, dynamic value) {
    final row = value as Map<String, dynamic>;
    final lexical = (row['lexical'] as List).map((dynamic value) {
      final hit = value as Map<String, dynamic>;
      return _hit(hit['id'] as String, hit['field'] as String);
    }).toList();
    final semantic = (row['semantic'] as List).map((dynamic value) {
      final hit = value as Map<String, dynamic>;
      return SemanticSearchHit(
        hit: _hit(hit['id'] as String, 'semantic'),
        score: (hit['score'] as num).toDouble(),
      );
    }).toList();
    return MapEntry(name, _report(name, lexical, semantic));
  });
}

StationSearchReport withoutSemanticBead(
  StationSearchReport report,
  String beadId,
) => StationSearchReport(
  query: report.query,
  stores: report.stores,
  semantic: SemanticSearched(
    stores: report.semantic.stores,
    hits: (report.semantic as SemanticSearched).hits
        .where((row) => row.hit.beadId != beadId)
        .toList(),
  ),
);

StationSearchReport reorderGuardBehindSemantic(StationSearchReport report) {
  final semantic = report.semantic as SemanticSearched;
  return StationSearchReport(
    query: report.query,
    stores: [
      StoreSearched(
        (report.stores.single as StoreSearched).store,
        hits: [semantic.hits.first.hit, ...report.hits],
        beadsSearched: 1,
      ),
    ],
    semantic: semantic,
  );
}

Map<String, StationSearchReport> reportsWithUnavailableSemantic() {
  final reports = loadReportFixtures();
  final old = reports['station-effectiveness']!;
  reports['station-effectiveness'] = StationSearchReport(
    query: old.query,
    stores: old.stores,
    semantic: const SemanticUnavailable(stores: [], reason: 'offline'),
  );
  return reports;
}

Map<String, dynamic> _liveEnvelope(
  String query, {
  bool unavailable = false,
  bool incomplete = false,
}) {
  final fixtures = loadReportFixtures();
  final set = loadRecallSetFixture();
  final name = query == set.exactIdGuard
      ? 'id-hit-still-first'
      : set.cases.singleWhere((row) => row.query == query).name;
  final report = fixtures[name]!;
  Map<String, dynamic> hitJson(SearchHit hit) => hit.toJson();
  return {
    'query': query,
    'stores': [
      {
        'substation': 'power_station',
        'prefix': 'tg',
        'root': '/grid/power_station',
        'outcome': 'searched',
        'beadsSearched': 10,
        'hits': report.hits.map(hitJson).toList(),
      },
    ],
    'hitCount': report.hits.length,
    'semantic': unavailable
        ? {
            'outcome': 'unavailable',
            'reason': 'offline',
            'stores': <Object>[],
            'hits': <Object>[],
          }
        : {
            'outcome': 'searched',
            'stores': [
              {
                'store': 'power_station',
                'indexed': 10,
                'stale': incomplete ? 1 : 0,
                'unindexed': 0,
              },
            ],
            'hits': [
              for (final row in (report.semantic as SemanticSearched).hits)
                {...row.hit.toJson(), 'path': 'semantic', 'score': row.score},
            ],
          },
  };
}

/// Runs [body] against a DISPOSABLE copy of the corpus under a temp root,
/// handing it that root and the copied corpus path.
///
/// The root is passed to [runRecall] as its `workingDirectory`; nothing assigns
/// the process working directory. That is a process property and `dart test`
/// runs test files in concurrent isolates of one process, so the record-mode
/// write this fixture exists to contain used to move it out from under every
/// sibling suite reading a relative path.
Future<T> _inFixtureRoot<T>(
  Future<T> Function(String root, String fixturePath) body,
) async {
  final temporary = await Directory.systemTemp.createTemp('recall-test-');
  final fixture = File(p.join(temporary.path, _setPath));
  await fixture.parent.create(recursive: true);
  await _checkedIn(_setPath).copy(fixture.path);
  await _checkedIn(_reportsPath).copy(p.join(temporary.path, _reportsPath));
  try {
    return await body(temporary.path, fixture.path);
  } finally {
    await temporary.delete(recursive: true);
  }
}

void main() {
  group('semantic recall set', () {
    test('recorded real misses yield 2/2 recall and two controls', () {
      final set = loadRecallSetFixture();
      final result = evaluateRecall(
        recallSet: set,
        reports: loadReportFixtures(),
      );
      expect(result.recallTotal, 2);
      expect(result.recallFound, 2);
      expect(result.controlCount, 2);
      expect(result.idGuardPassed, isTrue);
      expect(result.passed, isTrue);
    });

    test('a semantic miss fails recall', () {
      final reports = loadReportFixtures()
        ..update(
          'station-effectiveness',
          (report) => withoutSemanticBead(report, 'tg-5drf'),
        );
      final result = evaluateRecall(
        recallSet: loadRecallSetFixture(),
        reports: reports,
      );
      expect(result.recallFound, 1);
      expect(result.passed, isFalse);
    });

    test('a lexical hit is a control and cannot inflate recall', () {
      final result = evaluateRecall(
        recallSet: loadRecallSetFixture(),
        reports: loadReportFixtures(),
      );
      expect(
        result.cases
            .where((row) => row.kind == RecallCaseKind.control)
            .map((row) => row.recallCase.name),
        ['refinement-vocabulary', 'production-observability'],
      );
    });

    test('exact id remains the first lexical id-field hit', () {
      final reports = loadReportFixtures();
      expect(
        evaluateRecall(
          recallSet: loadRecallSetFixture(),
          reports: reports,
        ).idGuardPassed,
        isTrue,
      );
      reports['id-hit-still-first'] = reorderGuardBehindSemantic(
        reports['id-hit-still-first']!,
      );
      expect(
        evaluateRecall(
          recallSet: loadRecallSetFixture(),
          reports: reports,
        ).idGuardPassed,
        isFalse,
      );
    });

    test('malformed corpus and unavailable semantic reports refuse loudly', () {
      expect(
        () => RecallSet.fromJsonString('{"version":2}'),
        throwsFormatException,
      );
      expect(
        () => evaluateRecall(
          recallSet: loadRecallSetFixture(),
          reports: reportsWithUnavailableSemantic(),
        ),
        throwsStateError,
      );
    });

    test('fixture preserves the four real pairs and empty baseline', () {
      final set = loadRecallSetFixture();
      expect(set.cases.map((row) => [row.name, row.query, row.expectedBeadIds]), [
        [
          'refinement-vocabulary',
          'refine',
          ['tg-mles'],
        ],
        [
          'production-observability',
          'observability',
          ['tg-dwc'],
        ],
        [
          'station-effectiveness',
          'are our automated work sessions getting healthier and more effective over time',
          ['tg-5drf'],
        ],
        [
          'single-store-owner',
          'how do we stop two stations fighting over one store',
          ['tg-s6gk', 'tg-0edw'],
        ],
      ]);
      expect(set.baseline, isEmpty);
    });

    test(
      'live runner uses exact query order and is read-only by default',
      () async {
        await _inFixtureRoot((root, fixturePath) async {
          final before = await File(fixturePath).readAsString();
          final calls = <List<String>>[];
          Future<ProcessResult> fake(
            String executable,
            List<String> argv,
          ) async {
            calls.add([executable, ...argv]);
            return ProcessResult(1, 0, jsonEncode(_liveEnvelope(argv[2])), '');
          }

          expect(
            await runRecall(
              runner: 'space',
              gridHome: '/grid',
              recordBaseline: false,
              processRunner: fake,
              workingDirectory: root,
            ),
            0,
          );
          expect(calls, [
            for (final query in [
              'refine',
              'observability',
              'are our automated work sessions getting healthier and more effective over time',
              'how do we stop two stations fighting over one store',
              'tg-5drf',
            ])
              ['space', 'search', '--json', query, '--grid-home', '/grid'],
          ]);
          expect(await File(fixturePath).readAsString(), before);
        });
      },
    );

    test('live runner refuses unavailable and incomplete coverage', () async {
      for (final mode in ['unavailable', 'incomplete']) {
        await _inFixtureRoot((root, _) async {
          Future<ProcessResult> fake(String _, List<String> argv) async =>
              ProcessResult(
                1,
                0,
                jsonEncode(
                  _liveEnvelope(
                    argv[2],
                    unavailable: mode == 'unavailable',
                    incomplete: mode == 'incomplete',
                  ),
                ),
                '',
              );
          expect(
            await runRecall(
              runner: 'space',
              gridHome: '/grid',
              recordBaseline: false,
              processRunner: fake,
              workingDirectory: root,
            ),
            1,
          );
        });
      }
    });

    test('record mode writes every live rank and score', () async {
      await _inFixtureRoot((root, fixturePath) async {
        Future<ProcessResult> fake(String _, List<String> argv) async =>
            ProcessResult(1, 0, jsonEncode(_liveEnvelope(argv[2])), '');
        expect(
          await runRecall(
            runner: 'space',
            gridHome: '/grid',
            recordBaseline: true,
            processRunner: fake,
            workingDirectory: root,
          ),
          0,
        );
        final recorded = RecallSet.fromJsonString(
          await File(fixturePath).readAsString(),
        );
        expect(recorded.baseline.keys, [
          'refinement-vocabulary',
          'production-observability',
          'station-effectiveness',
          'single-store-owner',
        ]);
        expect(recorded.baseline['station-effectiveness']?.rank, 1);
        expect(recorded.baseline['station-effectiveness']?.score, 0.724);
      });
    });
  });
}
