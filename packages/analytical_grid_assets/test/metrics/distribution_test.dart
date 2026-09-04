// The split distribution: nearest-rank percentiles, worst-session provenance,
// and an EXPLICIT insufficient-data floor rather than a false zero.
import 'package:analytical_grid_assets/analytical_grid_assets.dart';
import 'package:test/test.dart';

void main() {
  test('nearest-rank percentiles retain worst-session provenance', () {
    final distribution = Distribution.from(const [
      (value: 1, sessionId: 's1'),
      (value: 2, sessionId: 's2'),
      (value: 3, sessionId: 's3'),
      (value: 4, sessionId: 's4'),
      (value: 100, sessionId: 's5'),
    ]);
    expect(distribution.sampleCount, 5);
    expect(distribution.sessionCount, 5);
    expect(distribution.p50, 3);
    expect(distribution.p90, 100);
    expect(distribution.p99, 100);
    expect(distribution.max, 100);
    expect(distribution.worstSessionId, 's5');
  });

  test('a reported percentile is always a value that occurred', () {
    final distribution = Distribution.from(const [
      (value: 10, sessionId: 's1'),
      (value: 20, sessionId: 's2'),
      (value: 30, sessionId: 's3'),
      (value: 40, sessionId: 's4'),
      (value: 50, sessionId: 's5'),
      (value: 60, sessionId: 's6'),
    ]);
    for (final reading in [
      distribution.p50,
      distribution.p90,
      distribution.p99,
      distribution.max,
    ]) {
      expect([10, 20, 30, 40, 50, 60], contains(reading));
    }
    expect(distribution.p50, 30);
  });

  test('four sampled sessions are explicitly insufficient-data', () {
    final distribution = Distribution.from(const [
      (value: 1, sessionId: 's1'),
      (value: 2, sessionId: 's2'),
      (value: 3, sessionId: 's3'),
      (value: 4, sessionId: 's4'),
    ]);
    expect(distribution.insufficientData, isTrue);
    expect(distribution.p50, isNull);
    expect(distribution.insufficientDataReason, contains('insufficient-data'));
    expect(distribution.insufficientDataReason, contains('4 session(s)'));
  });

  test('the floor counts SESSIONS, not observations', () {
    final distribution = Distribution.from(const [
      (value: 1, sessionId: 's1'),
      (value: 2, sessionId: 's1'),
      (value: 3, sessionId: 's1'),
      (value: 4, sessionId: 's1'),
      (value: 5, sessionId: 's1'),
      (value: 6, sessionId: 's1'),
    ]);
    expect(distribution.sampleCount, 6);
    expect(distribution.sessionCount, 1);
    expect(distribution.insufficientData, isTrue);
  });

  test('zero samples are named and emit no percentile key', () {
    final distribution = Distribution.from(const []);
    expect(distribution.sampleCount, 0);
    expect(distribution.insufficientData, isTrue);
    expect(distribution.toJson(), isNot(contains('p50')));
    expect(distribution.toJson()['sampleCount'], 0);
  });

  test('a non-positive sparse floor is refused loudly', () {
    expect(
      () => Distribution.from(const [], threshold: 0),
      throwsArgumentError,
    );
  });
}
