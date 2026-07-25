// The WAIT PRIMITIVE's own contract (bead `pow-d26`).
//
// `settle` is the shared bounded wait every acceptance suite here builds its
// private `_settle` fixed-point wrapper on. Its load-bearing property is NOT
// "pump the event queue": the molecule mint's pour crosses a REAL filesystem
// boundary below the fake `BdRunner` seam (`BdCliService.applyGraph` writes the
// graph-apply plan to a temp file), and an event-queue pump grants only
// microseconds of wall clock. So `settle` must yield REAL time per unsatisfied
// round, or a pending OS completion is indistinguishable from quiescence and
// the suite reads an empty observable. These tests pin that contract LOUD, so a
// revert to a pump-only wait fails HERE instead of reappearing as a ~25%
// acceptance flake.
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'support/asset_fakes.dart';

void main() {
  group('settle — the bounded wait grants REAL wall clock', () {
    test('an ALREADY-satisfied condition costs exactly one check', () async {
      var checks = 0;
      await settle(() {
        checks++;
        return true;
      });
      expect(
        checks,
        1,
        reason: 'settle checks FIRST and sleeps only when unsatisfied',
      );
    });

    test(
      'an unsatisfied condition is checked ONCE per bounded round',
      () async {
        var checks = 0;
        await settle(() {
          checks++;
          return false;
        }, maxPumps: 3);
        expect(
          checks,
          3,
          reason:
              'the acceptance suites count their stableRounds plateau in '
              'these checks — one per round, or the plateau silently halves',
        );
      },
    );

    test('each unsatisfied round sleeps a REAL slice', () async {
      final sw = Stopwatch()..start();
      await settle(
        () => false,
        maxPumps: 5,
        ioSlice: const Duration(milliseconds: 4),
      );
      sw.stop();
      expect(
        sw.elapsedMilliseconds,
        greaterThanOrEqualTo(20),
        reason:
            'five unsatisfied rounds at 4ms each — a pump-only wait '
            'returns in microseconds and can never outlast a filesystem call',
      );
    });

    test(
      'a pending REAL filesystem round trip lands inside the budget',
      () async {
        var landed = false;
        unawaited(_tempPlanFileRoundTrip().then((_) => landed = true));
        await settle(() => landed, maxPumps: 200);
        expect(
          landed,
          isTrue,
          reason:
              'this is the exact IO shape BdCliService.applyGraph performs '
              'for every molecule pour',
        );
      },
    );
  });
}

/// The IO shape `BdCliService.applyGraph` performs for every molecule pour: a
/// temp dir, a plan write, a recursive delete.
Future<void> _tempPlanFileRoundTrip() async {
  final dir = await Directory.systemTemp.createTemp('settle-io-probe');
  await File('${dir.path}/plan.json').writeAsString('{"nodes":[]}');
  await dir.delete(recursive: true);
}
