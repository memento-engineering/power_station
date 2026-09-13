// The GitHub pack's WAKE FENCE.
//
// A resident seat owns no wake mechanism. The station's fenced service tick
// decides when reconciliation runs, through the query a station registers in
// `TrajectoryConfig.obligationQueryExtensions`. A seat that scheduled itself
// could not raise its own funeral: when the retired one-minute poll died on
// five of eight seats it stayed dead for weeks, because the only thing that
// would have reported the death was the thing that died.
//
// This file is the DURABLE form of that invariant. It reads the committed
// library source, so it holds on a clean tree and a dirty one alike. A
// working-tree diff check cannot: it goes quiet the moment the offending line
// is committed, and would pass a change that reintroduced the very loop this
// design retired.
//
// CODE fence: whole-line comments are stripped before matching, so prose may
// still name the construct it retired. Everything the compiler sees is fenced.
//
// This is also the ONE file in the pack that names those constructs on purpose
// — a text scan of the diff will find `Timer` and `Future.any` here. They are
// the fence's own falsifiability samples, and they are what makes an empty
// offender list mean something.
import 'dart:io';

import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:test/test.dart';

/// The ONE library file allowed to name a delayed future: the poll
/// coordinator's injectable minimum-spacing default. That spacing is a
/// TRANSPORT RATE — how closely two requests may follow one another — and
/// never a schedule.
const _sanctionedDelay = 'lib/src/github/github_reconciler_runtime.dart';

/// The SCHEDULING SURFACE: the runtime that performs one reconciliation, and
/// the two assets that mount it. A wall-clock loop here would be a second wake
/// mechanism. The pagination loops inside the reconciliation WORK
/// (`github_reconciler.dart`) walk an HTTP response rather than the clock, are
/// out of this fence deliberately, and are no part of what moved to the tick.
const _schedulingSurface = <String>[
  'lib/src/github/github_reconciler_runtime.dart',
  'lib/src/assets/github_reconciler_assets.dart',
  'lib/src/assets/github_grid_assets.dart',
];

/// The reconciliation WORK, which must not learn who schedules it.
const _work = 'lib/src/github/github_reconciler.dart';

final RegExp _timer = RegExp(r'\bTimer\b');
final RegExp _periodic = RegExp(r'\.\s*periodic\b');
final RegExp _futureAny = RegExp(r'\bFuture\s*(?:<[^>]*>)?\s*\.\s*any\b');
final RegExp _delayed = RegExp(r'\bFuture\s*(?:<[^>]*>)?\s*\.\s*delayed\b');
final RegExp _pollLoop = RegExp(r'\b(?:while\s*\(|do\s*\{)');
final RegExp _reconcilerCall = RegExp(r'\breconciler\.([A-Za-z_]\w*)');

/// The sanctioned delay, matched over collapsed whitespace so `dart format`
/// may rewrap the initializer without silently retiring the fence.
final RegExp _spacingSeam = RegExp(
  r'_delay = delay \?\? Future<void>\.delayed',
);

/// Source with whole-line comments removed — what the compiler actually sees.
String _code(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

String _collapsed(String source) =>
    source.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Every library file's code, keyed by its package-relative path.
Map<String, String> _library() {
  final library = Directory('lib');
  expect(
    library.existsSync(),
    isTrue,
    reason: 'the fence must run from the package root',
  );
  return <String, String>{
    for (final entity in library.listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart'))
        entity.path: _code(entity.readAsStringSync()),
  };
}

void main() {
  test('no library source owns a timer, a periodic stream or a delay race', () {
    final sources = _library();
    expect(sources, isNotEmpty, reason: 'a fence that reads nothing proves it');

    for (final pattern in <String, RegExp>{
      'a Timer': _timer,
      'a periodic stream': _periodic,
      'a Future.any race': _futureAny,
    }.entries) {
      final offenders = <String>[
        for (final source in sources.entries)
          if (pattern.value.hasMatch(source.value)) source.key,
      ];
      expect(
        offenders,
        isEmpty,
        reason:
            '${pattern.key} is a wake mechanism: it decides on its own '
            'schedule when work enters the station, and reports to nobody '
            'when it stops. Attach the work to the station tick through '
            'GitHubReconciliationQuery instead',
      );
    }
  });

  test('exactly one library line delays, and it is the transport rate', () {
    final sources = _library();
    final offenders = <String>[];
    var sanctioned = 0;
    for (final source in sources.entries) {
      final hits = _delayed.allMatches(source.value).length;
      if (hits == 0) continue;
      if (source.key == _sanctionedDelay) {
        sanctioned = hits;
      } else {
        offenders.add(source.key);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'take an injectable PollDelay (GitHubPollCoordinator) instead of '
          'sleeping in library code',
    );
    expect(
      sanctioned,
      1,
      reason:
          '$_sanctionedDelay defaults the coordinator PollDelay seam exactly '
          'once',
    );
    expect(
      _spacingSeam.hasMatch(_collapsed(sources[_sanctionedDelay]!)),
      isTrue,
      reason:
          'the one sanctioned delay is the coordinator minimum-spacing '
          'default; any other use of it is a schedule wearing a rate costume',
    );
  });

  test('the scheduling surface owns no poll loop', () {
    final sources = _library();
    for (final path in _schedulingSurface) {
      final source = sources[path];
      expect(
        source,
        isNotNull,
        reason: 'the fenced path $path moved or vanished; re-aim the fence',
      );
      expect(
        _pollLoop.hasMatch(source!),
        isFalse,
        reason:
            '$path is the scheduling surface: a loop here decides when '
            'reconciliation happens, which belongs to the station tick',
      );
    }
  });

  test('the runtime enters the reconciler through reconcileOnce alone', () {
    final entered = <String>{
      for (final match in _reconcilerCall.allMatches(
        _library()[_sanctionedDelay]!,
      ))
        match.group(1)!,
    };
    expect(
      entered,
      <String>{'reconcileOnce'},
      reason:
          'moving the schedule must not reach into the WORK: one full cycle '
          'per run, behind the installation budget, and nothing else',
    );
  });

  test('the reconciliation work names nothing that schedules it', () {
    final work = _library()[_work]!;
    for (final scheduler in const <String>[
      'GitHubReconcilerRuntime',
      'GitHubReconciliationQuery',
      'GitHubPollCoordinator',
      'ObligationQuery',
    ]) {
      expect(
        work.contains(scheduler),
        isFalse,
        reason:
            '$_work is the work, not the schedule; it must stay usable by a '
            'caller that reconciles directly',
      );
    }
  });

  test('the coordinator keeps its default transport rate', () {
    expect(GitHubPollCoordinator().minimumSpacing, const Duration(seconds: 5));
  });

  test('the fence is falsifiable', () {
    // Literals the fence MUST catch — so an empty offender list above means
    // "no seat schedules itself", not "the patterns never match anything".
    // The delay and race samples are the retired loop's own two lines.
    expect(
      _timer.hasMatch('Timer.periodic(interval, (_) => runOnce());'),
      isTrue,
    );
    expect(
      _periodic.hasMatch('Stream<void>.periodic(interval).listen(run);'),
      isTrue,
    );
    expect(
      _futureAny.hasMatch('await Future.any([_delay(interval), stop.future]);'),
      isTrue,
    );
    expect(_delayed.hasMatch('await Future<void>.delayed(interval);'), isTrue);
    expect(_delayed.hasMatch('_delay = delay ?? Future.delayed,'), isTrue);
    expect(_pollLoop.hasMatch('    while (!_stopped) {'), isTrue);
    expect(_pollLoop.hasMatch('    do {'), isTrue);
    expect(_reconcilerCall.hasMatch('reconciler.reconcileForever()'), isTrue);

    // Shapes the fence must TOLERATE, or it would refuse the design it guards.
    expect(
      _pollLoop.hasMatch('/// inert while GitHub is unavailable.'),
      isFalse,
    );
    expect(_futureAny.hasMatch('seats.any((seat) => seat.isStale)'), isFalse);
    expect(
      _delayed.hasMatch('if (wait > Duration.zero) await _delay(wait);'),
      isFalse,
    );
    expect(_timer.hasMatch('final timerless = true;'), isFalse);
    // `/// Bound per-seat reconciler.` ends a sentence, not a member access.
    expect(
      _reconcilerCall.hasMatch('/// Bound per-seat reconciler.\n  final'),
      isFalse,
    );

    // Comment stripping keeps the fence about CODE, and only about code.
    expect(
      _code('  // Timer.periodic once lived here.\nvar x = 1;'),
      'var x = 1;',
    );
    expect(
      _code("const uri = 'https://api.github.test';"),
      "const uri = 'https://api.github.test';",
    );
  });
}
