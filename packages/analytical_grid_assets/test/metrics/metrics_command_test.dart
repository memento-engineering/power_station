// The `metrics report` Command — the THIN CLI adapter over
// StationMetricsService: parses argv, resolves the store set from the injected
// resident-station context, renders. Everything behavioral belongs to the
// builder (report_builder_test.dart); this suite pins the adapter contract a
// composing station (`space metrics report`) and its skills rely on.
import 'dart:convert';

import 'package:analytical_grid_assets/analytical_grid_assets.dart';
import 'package:args/command_runner.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:test/test.dart';

/// The composing station's resident-station context: one literal seat, so the
/// store set is the grid home plus that seat.
class _StationDelegate extends sdk.GridDelegate {
  _StationDelegate(this.root);

  @override
  final String root;

  var disposed = false;

  @override
  Seed build(TreeContext context, sdk.GridConfiguration configuration) =>
      sdk.RawAssetGrid(
        root: root,
        assets: [
          sdk.Station(
            name: 'test-station',
            assets: [
              sdk.Substations(
                substations: [sdk.Substation('alpha', '/roots/alpha')],
              ),
            ],
          ),
        ],
      );

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _FakeSource implements LedgerMetricsSource {
  _FakeSource({this.failRoots = const {}});

  final Set<String> failRoots;
  final List<String> reads = [];

  @override
  Future<SessionLedgerMetricsProjection> project(MetricsStore store) async {
    final root = store.store.gridRoot;
    reads.add(root);
    if (failRoots.contains(root)) throw StateError('read failed at $root');
    return const SessionLedgerMetricsProjection(
      sessionsById: {
        's1': LedgerSessionMetrics(
          sessionId: 's1',
          workBeadId: 'pow-1',
          nodes: [
            LedgerNodeMetrics(
              beadId: 'step-1',
              nodePath: 'pow-1/land',
              lane: 'land',
              tokensIn: 10,
            ),
          ],
        ),
      },
    );
  }
}

typedef _Harness = ({
  CommandRunner<int> runner,
  _FakeSource source,
  StringBuffer out,
  StringBuffer err,
  _StationDelegate? Function() delegate,
});

_Harness _harness({
  bool storeExists = true,
  String Function()? gridHomeDefault,
}) {
  final source = _FakeSource();
  final out = StringBuffer();
  final err = StringBuffer();
  _StationDelegate? delegate;
  final runner = CommandRunner<int>('space', 'test station')
    ..addCommand(
      MetricsCommand(
        delegate: (gridHome) => delegate = _StationDelegate(gridHome),
        gridHomeDefault: gridHomeDefault ?? () => '/g',
        service: StationMetricsService(
          source: source,
          dirExists: (_) => storeExists,
        ),
        out: out,
        err: err,
      ),
    );
  return (
    runner: runner,
    source: source,
    out: out,
    err: err,
    delegate: () => delegate,
  );
}

void main() {
  test('`metrics report --json` emits exactly one JSON object', () async {
    final h = _harness();
    expect(await h.runner.run(['metrics', 'report', '--json']), 0);
    final lines = const LineSplitter()
        .convert(h.out.toString())
        .where((line) => line.isNotEmpty)
        .toList();
    expect(lines, hasLength(1));
    final json = jsonDecode(lines.single) as Map<String, dynamic>;
    expect(json['sparseSampleThreshold'], kDefaultSparseSampleThreshold);
    expect(h.delegate()!.disposed, isTrue);
  });

  test('the store set is the grid home plus every mounted seat', () async {
    final h = _harness();
    expect(await h.runner.run(['metrics', 'report', '--json']), 0);
    expect(h.source.reads, ['/g', '/roots/alpha']);
  });

  test('the human face states the threshold and insufficient-data', () async {
    final h = _harness();
    expect(await h.runner.run(['metrics', 'report']), 0);
    expect(h.out.toString(), contains('sparse threshold:'));
    expect(h.out.toString(), contains('insufficient-data'));
  });

  test(
    'a relative grid home exits 64 before constructing a delegate',
    () async {
      final h = _harness(gridHomeDefault: () => 'relative/grid');
      expect(await h.runner.run(['metrics', 'report']), 64);
      expect(h.err.toString(), contains('must be an ABSOLUTE path'));
      expect(h.delegate(), isNull);
      expect(h.source.reads, isEmpty);
    },
  );

  test('invalid sparse thresholds and headroom exit 64', () async {
    for (final argv in [
      ['--sparse-threshold', '0'],
      ['--sparse-threshold', 'many'],
      ['--headroom', '0.5'],
      ['--headroom', 'NaN'],
    ]) {
      final h = _harness();
      expect(
        await h.runner.run(['metrics', 'report', ...argv]),
        64,
        reason: '$argv must be refused',
      );
      expect(h.source.reads, isEmpty);
      expect(h.delegate(), isNull);
    }
  });

  test('the service reads in set order and isolates a failed store', () async {
    final source = _FakeSource(failRoots: {'/bad'});
    final report =
        await StationMetricsService(
          source: source,
          dirExists: (_) => true,
        ).report(
          stores: [
            MetricsStore(name: 'good', gridRoot: '/good'),
            MetricsStore(name: 'bad', gridRoot: '/bad'),
            MetricsStore(name: 'next', gridRoot: '/next'),
          ],
        );

    expect(source.reads, ['/good', '/bad', '/next']);
    expect(report.stores, [
      isA<StoreLedgerRead>(),
      isA<StoreLedgerFailed>(),
      isA<StoreLedgerRead>(),
    ]);
    expect(report.readAnyStore, isTrue);
  });

  test('the service refuses an empty store-set input loudly', () async {
    await expectLater(
      const StationMetricsService().report(stores: const []),
      throwsArgumentError,
    );
  });

  test('an all-absent store set renders its outcome and exits 1', () async {
    final h = _harness(storeExists: false);
    expect(await h.runner.run(['metrics', 'report']), 1);
    expect(h.out.toString(), contains('no state store'));
    expect(h.err.toString(), contains('loud non-answer'));
    expect(h.source.reads, isEmpty);
  });

  test('the delegate is disposed even when the read set is empty', () async {
    final h = _harness(storeExists: false);
    await h.runner.run(['metrics', 'report']);
    expect(h.delegate()!.disposed, isTrue);
  });
}
