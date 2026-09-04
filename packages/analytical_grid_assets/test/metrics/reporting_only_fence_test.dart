// The two fences that make "REPORTING ONLY" falsifiable rather than a claim in
// a doc comment: no live view (the cockpit owns what is running now) and no
// enforcement surface (a cap is a later decision, taken after retained metrics
// exist).
import 'dart:convert';
import 'dart:io';

import 'package:analytical_grid_assets/analytical_grid_assets.dart';
import 'package:test/test.dart';

String _libSource() {
  final lib = Directory('lib');
  if (!lib.existsSync()) {
    fail('run this suite from packages/analytical_grid_assets');
  }
  return lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .map((file) => file.readAsStringSync())
      .join('\n');
}

void main() {
  test('the pack renders no LIVE view — no timer, stream or watch', () {
    final source = _libSource();
    for (final live in [
      // Each pattern is anchored so it matches a CONSTRUCTION or a CALL, not
      // an identifier that merely ends in the same letters.
      RegExp(r'(?<![A-Za-z0-9_])Timer\('),
      RegExp(r'(?<![A-Za-z0-9_])StreamSubscription\b'),
      RegExp(r'(?<![A-Za-z0-9_])Directory\('),
      RegExp(r'\.listen\('),
      RegExp(r'\bwatch<'),
    ]) {
      expect(
        source,
        isNot(matches(live)),
        reason: 'live view: ${live.pattern}',
      );
    }
  });

  test('the report enforces nothing — no budget or cap key in the JSON', () {
    final json = jsonEncode(
      buildStationMetricsReport(
        outcomes: const [],
        projections: const [],
      ).toJson(),
    );
    for (final forbidden in [
      'globalCap',
      'recommendedCap',
      'tokenCap',
      'budget',
      '"global"',
    ]) {
      expect(
        json,
        isNot(contains(forbidden)),
        reason: 'enforcement: $forbidden',
      );
    }
  });

  test('the recommendation surface is per-circuit and per-task only', () {
    final recommendations = buildStationMetricsReport(
      outcomes: const [],
      projections: const [],
    ).recommendations.toJson();
    expect(recommendations.keys, [
      'headroomFactor',
      'basis',
      'perCircuit',
      'perTask',
    ]);
    expect(recommendations['basis'], contains('reporting only'));
  });
}
