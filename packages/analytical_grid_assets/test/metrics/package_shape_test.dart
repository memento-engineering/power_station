// The pack's boundary, made independently falsifiable: one workspace member,
// no Station subclass, and every direct grid_engine import limited to the
// ledger READ MODEL this pack presents (it never re-derives the projection).
import 'dart:io';

import 'package:test/test.dart';

String _libSource() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .map((file) => file.readAsStringSync())
    .join('\n');

void main() {
  test('the pack is composable and imports only the ledger read model', () {
    final source = _libSource();
    expect(source, isNot(matches(RegExp(r'extends\s+(sdk\.)?Station\b'))));

    final engineImports = RegExp(
      r"import 'package:grid_engine/grid_engine.dart'\s+show\s+([^;]+);",
      multiLine: true,
    ).allMatches(source).toList();
    expect(engineImports, isNotEmpty);
    expect(
      RegExp(r'package:grid_engine/').allMatches(source).length,
      engineImports.length,
      reason: 'every grid_engine import must use an explicit show-list',
    );

    // Every name below is declared by
    // grid_engine/lib/src/domain/session_ledger_metrics_projection.dart.
    const allowed = <String>{
      'CacheTokenTotals',
      'FalseFMetrics',
      'LandedDeliveryTotals',
      'LedgerGrade',
      'LedgerNodeMetrics',
      'LedgerSessionMetrics',
      'ResultTransport',
      'ResultTransportAbsent',
      'ResultTransportFailClosedDefault',
      'ResultTransportOperatorRuling',
      'ResultTransportReported',
      'SessionLedgerMetricsProjection',
      'projectSessionLedgerMetrics',
    };
    for (final match in engineImports) {
      final symbols = match.group(1)!.split(',').map((part) => part.trim());
      expect(symbols, everyElement(isIn(allowed)));
    }

    final packagePubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      RegExp(r'^  grid_engine:', multiLine: true).allMatches(packagePubspec),
      hasLength(1),
    );
    final workspacePubspec = File('../../pubspec.yaml').readAsStringSync();
    expect(
      RegExp(
        r'^  - packages/analytical_grid_assets$',
        multiLine: true,
      ).allMatches(workspacePubspec),
      hasLength(1),
    );
  });

  test('roster resolution is REUSED from grid_assets, never re-derived', () {
    final source = _libSource();
    expect(source, contains('mountedRosterOf'));
    expect(
      source,
      isNot(matches(RegExp(r'List<sdk\.SubstationScope>\s+mountedRosterOf'))),
    );
  });

  test('the reserved Agent Seat noun is not minted as a code symbol', () {
    // `the_grid#agent-seat-and-agent-disc` (accepted; its surfaces include
    // `**/*_grid_assets/**`) reserves `seat` for a standing agent position and
    // names space-5rp as the work freeing the word from existing code symbols.
    // This pack's axis is a CIRCUIT COORDINATE, so the noun appears only in
    // the doc comments that explain the distinction — never in code, never in
    // a rendered string.
    final code = _libSource()
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp(r'^[ \t]*//.*', multiLine: true), '');
    expect(code, isNot(matches(RegExp(r'\bseats?\b', caseSensitive: false))));
    expect(_libSource(), contains('agent-seat-and-agent-disc'));
  });
}
