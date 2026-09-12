// The DART-domain VERIFICATION service + exported `dart verify` Commands — the
// asymmetric output contract: a GREEN run answers in one bounded JSON line, a
// RED run keeps the whole transcript. Pins the four argv shapes, the machine
// (JSON) reporter as the only source of test counts, the hard green cap, the
// uncapped failure payload, exit-code identity, and the ABSENCE of a cache
// (a cached green can mask a live red). Offline throughout: the one process
// edge rides the injected ProcessRunner seam as a Fake (Fakes, not mocks).
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_grid_assets/dart_grid_assets.dart';
import 'package:test/test.dart';

/// A Fake [ProcessRunner]: records every call and answers either one standing
/// result or a queue of them.
class _FakeVerifyProcess {
  _FakeVerifyProcess.always(ProcessResult result)
    : _standing = result,
      _queue = [];

  _FakeVerifyProcess.queue(List<ProcessResult> results)
    : _standing = null,
      _queue = [...results];

  final ProcessResult? _standing;
  final List<ProcessResult> _queue;

  final calls =
      <
        ({String executable, List<String> arguments, String? workingDirectory})
      >[];

  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    calls.add((
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
    ));
    final standing = _standing;
    if (standing != null) return standing;
    if (_queue.isEmpty) {
      throw StateError(
        'unexpected process call: $executable ${arguments.join(' ')}',
      );
    }
    return _queue.removeAt(0);
  }
}

ProcessResult _result(int exitCode, {String out = '', String err = ''}) =>
    ProcessResult(4242, exitCode, out, err);

/// A `dart test --reporter=json` stream, shaped exactly like the real one: a
/// `start`/`suite` preamble, a HIDDEN loading `testDone` that must never be
/// counted, then one `testStart`/`testDone` pair per test, then `done`.
String _reporterStream({
  int passed = 0,
  int skipped = 0,
  int elapsed = 484,
  bool done = true,
}) {
  final lines = <String>[
    jsonEncode({
      'protocolVersion': '0.1.1',
      'runnerVersion': '1.32.0',
      'pid': 4242,
      'type': 'start',
      'time': 0,
    }),
    jsonEncode({
      'suite': {'id': 0, 'platform': 'vm', 'path': 'test/probe_test.dart'},
      'type': 'suite',
      'time': 0,
    }),
    jsonEncode({
      'testID': 1,
      'result': 'success',
      'skipped': false,
      'hidden': true,
      'type': 'testDone',
      'time': 3,
    }),
  ];
  var id = 2;
  for (var i = 0; i < passed + skipped; i++) {
    final isSkip = i >= passed;
    lines
      ..add(
        jsonEncode({
          'test': {'id': id, 'name': 'probe $id', 'suiteID': 0},
          'type': 'testStart',
          'time': 10 + i,
        }),
      )
      ..add(
        jsonEncode({
          'testID': id,
          'result': 'success',
          'skipped': isSkip,
          'hidden': false,
          'type': 'testDone',
          'time': 11 + i,
        }),
      );
    id++;
  }
  if (done) {
    lines.add(jsonEncode({'success': true, 'type': 'done', 'time': elapsed}));
  }
  return '${lines.join('\n')}\n';
}

/// A long failure transcript with an exact first and last line, so a test can
/// prove nothing was clipped off either end.
String _failureTranscript(String tag) {
  final filler = List.generate(
    200,
    (i) => '  $tag line $i: expected <true> but was <false>',
  ).join('\n');
  return 'BEGIN-$tag\n$filler\nEND-$tag';
}

/// One `dart verify …` invocation through a runner hosting [DartCommand]
/// exactly as a station app assembles it — the leaves are reachable only if
/// this path works.
Future<({int code, String out, String err})> _runVerify(
  List<String> args, {
  required _FakeVerifyProcess process,
}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final runner = CommandRunner<int>('t', 'test station')
    ..addCommand(
      DartCommand(
        verificationService: DartVerificationService(runProcess: process.call),
        verificationOut: out,
        verificationErr: err,
      ),
    );
  final code = await runner.run(args) ?? 0;
  return (code: code, out: out.toString(), err: err.toString());
}

void main() {
  group('DartVerificationService', () {
    test('runs dart test through the machine reporter', () async {
      final process = _FakeVerifyProcess.always(
        _result(0, out: _reporterStream(passed: 1)),
      );
      await DartVerificationService(runProcess: process.call).run(
        kind: DartVerificationKind.test,
        workspaceDir: '/tmp/acvm-workspace',
      );
      expect(process.calls, hasLength(1));
      expect(process.calls.single.executable, 'dart');
      expect(process.calls.single.arguments, ['test', '--reporter=json']);
      expect(process.calls.single.workingDirectory, '/tmp/acvm-workspace');
    });

    test('runs the analyze, format and pub argv shapes', () async {
      final shapes = {
        DartVerificationKind.analyze: ['analyze'],
        DartVerificationKind.format: ['format'],
        DartVerificationKind.pub: ['pub', 'get'],
      };
      for (final entry in shapes.entries) {
        final process = _FakeVerifyProcess.always(_result(0));
        await DartVerificationService(
          runProcess: process.call,
        ).run(kind: entry.key, workspaceDir: '/tmp/acvm-workspace');
        expect(process.calls.single.arguments, entry.value);
      }
    });

    test('forwards caller arguments after the kind argv', () async {
      final process = _FakeVerifyProcess.always(_result(0));
      await DartVerificationService(runProcess: process.call).run(
        kind: DartVerificationKind.test,
        workspaceDir: '/tmp/acvm-workspace',
        arguments: const ['--concurrency=1', 'test/probe_test.dart'],
      );
      expect(process.calls.single.arguments, [
        'test',
        '--reporter=json',
        '--concurrency=1',
        'test/probe_test.dart',
      ]);
    });

    test('refuses a forwarded reporter override before spawning', () async {
      for (final override in const [
        '-r',
        '--reporter',
        '--reporter=expanded',
        '-rexpanded',
      ]) {
        final process = _FakeVerifyProcess.always(_result(0));
        await expectLater(
          DartVerificationService(runProcess: process.call).run(
            kind: DartVerificationKind.test,
            workspaceDir: '/tmp/acvm-workspace',
            arguments: [override],
          ),
          throwsArgumentError,
          reason: '$override displaces the machine protocol',
        );
        expect(
          process.calls,
          isEmpty,
          reason: 'the refusal lands before the spawn',
        );
      }
    });

    test('derives counts and elapsed time from reporter events', () async {
      final process = _FakeVerifyProcess.always(
        _result(0, out: _reporterStream(passed: 3, skipped: 2, elapsed: 812)),
      );
      final report = await DartVerificationService(runProcess: process.call)
          .run(
            kind: DartVerificationKind.test,
            workspaceDir: '/tmp/acvm-workspace',
          );
      expect(report.greenSummary, {
        'command': 'dart test --reporter=json',
        'verdict': 'green',
        'exitCode': 0,
        'passed': 3,
        'skipped': 2,
        'elapsedMilliseconds': 812,
        'withheld': 'full transcript',
        'show': 'rerun this command with --full',
      });
    });

    test('reads the changed count from the last formatter line', () async {
      final process = _FakeVerifyProcess.always(
        _result(
          0,
          out:
              'Formatted 1 file (1 changed) in 0.01 seconds.\n'
              'Formatted 761 files (4 changed) in 1.20 seconds.\n',
        ),
      );
      final report = await DartVerificationService(runProcess: process.call)
          .run(
            kind: DartVerificationKind.format,
            workspaceDir: '/tmp/acvm-workspace',
          );
      expect(report.greenSummary?['changedFiles'], 4);
      expect(report.greenSummary, isNot(contains('summaryWarning')));
    });

    test('a formatter transcript with no summary line warns', () async {
      final process = _FakeVerifyProcess.always(_result(0, out: 'nothing\n'));
      final report = await DartVerificationService(runProcess: process.call)
          .run(
            kind: DartVerificationKind.format,
            workspaceDir: '/tmp/acvm-workspace',
          );
      expect(report.greenSummary?['changedFiles'], isNull);
      expect(report.greenSummary?['summaryWarning'], isNotNull);
    });

    test('an unreadable reporter stream warns, never reports zero', () async {
      final process = _FakeVerifyProcess.always(
        _result(0, out: '00:02 +761: All tests passed!\n'),
      );
      final report = await DartVerificationService(runProcess: process.call)
          .run(
            kind: DartVerificationKind.test,
            workspaceDir: '/tmp/acvm-workspace',
          );
      expect(report.greenSummary?['passed'], isNull);
      expect(report.greenSummary?['skipped'], isNull);
      expect(report.greenSummary?['elapsedMilliseconds'], isNull);
      expect(report.greenSummary?['summaryWarning'], isNotNull);
    });

    test('a reporter stream with no done event warns', () async {
      final process = _FakeVerifyProcess.always(
        _result(0, out: _reporterStream(passed: 2, done: false)),
      );
      final report = await DartVerificationService(runProcess: process.call)
          .run(
            kind: DartVerificationKind.test,
            workspaceDir: '/tmp/acvm-workspace',
          );
      expect(report.greenSummary?['passed'], 2);
      expect(report.greenSummary?['elapsedMilliseconds'], isNull);
      expect(report.greenSummary?['summaryWarning'], isNotNull);
    });

    test('a huge green transcript still summarises under the cap', () async {
      final noise = List.generate(
        4000,
        (i) => '{"type":"print","message":"chatter $i"}',
      ).join('\n');
      final process = _FakeVerifyProcess.always(
        _result(0, out: '$noise\n${_reporterStream(passed: 761)}'),
      );
      final report = await DartVerificationService(runProcess: process.call)
          .run(
            kind: DartVerificationKind.test,
            workspaceDir: '/tmp/acvm-workspace',
          );
      expect(report.stdout.length, greaterThan(100000));
      expect(report.greenSummary?['passed'], 761);
      expect(
        jsonEncode(report.greenSummary).length,
        lessThanOrEqualTo(kMaxGreenVerificationOutputChars),
      );
    });

    test('an oversize summary is replaced whole, never clipped', () async {
      final process = _FakeVerifyProcess.always(
        _result(0, out: _reporterStream(passed: 1)),
      );
      final report = await DartVerificationService(runProcess: process.call)
          .run(
            kind: DartVerificationKind.test,
            workspaceDir: '/tmp/acvm-workspace',
            arguments: [List.filled(600, 'x').join()],
          );
      final encoded = jsonEncode(report.greenSummary);
      expect(
        encoded.length,
        lessThanOrEqualTo(kMaxGreenVerificationOutputChars),
      );
      expect(jsonDecode(encoded), isA<Map<String, Object?>>());
      expect(report.greenSummary?['command'], 'dart test --reporter=json');
      expect(report.greenSummary?['summaryWarning'], isNotNull);
      expect(report.greenSummary?['withheld'], 'full transcript');
    });

    test('a red run keeps both raw channels and has no summary', () async {
      final process = _FakeVerifyProcess.always(
        _result(
          1,
          out: _failureTranscript('STDOUT'),
          err: _failureTranscript('STDERR'),
        ),
      );
      final report = await DartVerificationService(runProcess: process.call)
          .run(
            kind: DartVerificationKind.analyze,
            workspaceDir: '/tmp/acvm-workspace',
          );
      expect(report.greenSummary, isNull);
      expect(report.isGreen, isFalse);
      expect(report.stdout, _failureTranscript('STDOUT'));
      expect(report.stderr, _failureTranscript('STDERR'));
    });

    test('every call spawns afresh — nothing is cached', () async {
      final process = _FakeVerifyProcess.queue([
        _result(0, out: _reporterStream(passed: 1)),
        _result(1, out: 'the tree moved under the previous green'),
      ]);
      final service = DartVerificationService(runProcess: process.call);
      final first = await service.run(
        kind: DartVerificationKind.test,
        workspaceDir: '/tmp/acvm-workspace',
      );
      final second = await service.run(
        kind: DartVerificationKind.test,
        workspaceDir: '/tmp/acvm-workspace',
      );
      expect(process.calls, hasLength(2));
      expect(first.isGreen, isTrue);
      expect(
        second.isGreen,
        isFalse,
        reason: 'a cached green would have masked this live red',
      );
      expect(second.greenSummary, isNull);
    });
  });

  group('dart verify', () {
    test('is reachable from the dart umbrella a station assembles', () {
      final verify = DartCommand().subcommands['verify'];
      expect(verify, isNotNull);
      expect(
        verify!.subcommands.keys,
        containsAll(<String>['test', 'analyze', 'format', 'pub']),
      );
    });

    test('green test bounded', () async {
      final process = _FakeVerifyProcess.always(
        _result(
          0,
          out: _reporterStream(passed: 761, skipped: 1, elapsed: 12345),
        ),
      );
      final run = await _runVerify([
        'dart',
        'verify',
        'test',
        '--dir',
        '/tmp/acvm-workspace',
      ], process: process);

      expect(run.code, 0);
      expect(run.err, isEmpty);
      expect(run.out.trim(), isNot(contains('\n')));
      expect(
        run.out.trim().length,
        lessThanOrEqualTo(kMaxGreenVerificationOutputChars),
      );
      expect(jsonDecode(run.out), {
        'command': 'dart test --reporter=json',
        'verdict': 'green',
        'exitCode': 0,
        'passed': 761,
        'skipped': 1,
        'elapsedMilliseconds': 12345,
        'withheld': 'full transcript',
        'show': 'rerun this command with --full',
      });
    });

    test('green analyze bounded', () async {
      final process = _FakeVerifyProcess.always(
        _result(0, out: 'Analyzing power_station...\nNo issues found!\n'),
      );
      final run = await _runVerify([
        'dart',
        'verify',
        'analyze',
        '--dir',
        '/tmp/acvm-workspace',
      ], process: process);

      expect(run.code, 0);
      expect(run.err, isEmpty);
      expect(
        run.out.trim().length,
        lessThanOrEqualTo(kMaxGreenVerificationOutputChars),
      );
      expect(jsonDecode(run.out), {
        'command': 'dart analyze',
        'verdict': 'green',
        'exitCode': 0,
        'issues': 0,
        'withheld': 'full transcript',
        'show': 'rerun this command with --full',
      });
    });

    test('green format bounded', () async {
      final process = _FakeVerifyProcess.always(
        _result(0, out: 'Formatted 761 files (0 changed) in 1.20 seconds.\n'),
      );
      final run = await _runVerify([
        'dart',
        'verify',
        'format',
        '--dir',
        '/tmp/acvm-workspace',
      ], process: process);

      expect(run.code, 0);
      expect(run.err, isEmpty);
      expect(
        run.out.trim().length,
        lessThanOrEqualTo(kMaxGreenVerificationOutputChars),
      );
      expect(jsonDecode(run.out), {
        'command': 'dart format',
        'verdict': 'green',
        'exitCode': 0,
        'changedFiles': 0,
        'withheld': 'full transcript',
        'show': 'rerun this command with --full',
      });
    });

    test('green pub bounded', () async {
      final process = _FakeVerifyProcess.always(
        _result(
          0,
          out: 'Resolving dependencies...\nGot dependencies!\n',
          err: 'Downloading packages...\n',
        ),
      );
      final run = await _runVerify([
        'dart',
        'verify',
        'pub',
        '--dir',
        '/tmp/acvm-workspace',
      ], process: process);

      expect(run.code, 0);
      expect(
        run.err,
        isEmpty,
        reason: 'a bounded green says nothing on the error channel',
      );
      expect(
        run.out.trim().length,
        lessThanOrEqualTo(kMaxGreenVerificationOutputChars),
      );
      expect(jsonDecode(run.out), {
        'command': 'dart pub get',
        'verdict': 'green',
        'exitCode': 0,
        'resolution': 'succeeded',
        'withheld': 'full transcript',
        'show': 'rerun this command with --full',
      });
    });

    test('green --full replays transcript', () async {
      final transcript = _failureTranscript('GREEN-CHATTER');
      final process = _FakeVerifyProcess.always(
        _result(0, out: transcript, err: 'a warning nobody capped\n'),
      );
      final run = await _runVerify([
        'dart',
        'verify',
        'analyze',
        '--dir',
        '/tmp/acvm-workspace',
        '--full',
      ], process: process);

      expect(run.code, 0);
      expect(run.out, transcript);
      expect(run.err, 'a warning nobody capped\n');
      expect(
        run.out.length,
        greaterThan(kMaxGreenVerificationOutputChars),
        reason: '--full opts back into the whole transcript',
      );
      expect(run.out, isNot(contains('"verdict"')));
    });

    test('red test full payload', () => _expectRedPayload('test'));
    test('red analyze full payload', () => _expectRedPayload('analyze'));
    test('red format full payload', () => _expectRedPayload('format'));
    test('red pub full payload', () => _expectRedPayload('pub'));

    test('returns the child exit code unchanged', () async {
      for (final leaf in const ['test', 'analyze', 'format', 'pub']) {
        for (final code in const [0, 1, 2, 65, 127]) {
          final process = _FakeVerifyProcess.always(
            _result(
              code,
              out: code == 0 ? _reporterStream(passed: 1) : 'boom',
              err: code == 0 ? '' : 'boom',
            ),
          );
          final run = await _runVerify([
            'dart',
            'verify',
            leaf,
            '--dir',
            '/tmp/acvm-workspace',
          ], process: process);
          expect(
            run.code,
            code,
            reason: '`dart verify $leaf` must pass exit $code straight through',
          );
        }
      }
    });

    test('JSON reporter drives test counts', () async {
      final stream = _reporterStream(passed: 3, skipped: 1, elapsed: 99);
      final prose = [
        '00:02 +900 ~7: All tests passed!',
        'a stray line pretending to be a count: 42 passed',
      ].join('\n');
      final process = _FakeVerifyProcess.always(
        _result(0, out: '$prose\n$stream'),
      );
      final run = await _runVerify([
        'dart',
        'verify',
        'test',
        '--dir',
        '/tmp/acvm-workspace',
      ], process: process);

      expect(process.calls.single.arguments.join(' '), 'test --reporter=json');
      final summary = jsonDecode(run.out) as Map<String, Object?>;
      expect(summary['passed'], 3, reason: 'prose cannot alter a count');
      expect(summary['skipped'], 1);
      expect(summary['elapsedMilliseconds'], 99);

      final override = _FakeVerifyProcess.always(_result(0));
      final refused = await _runVerify([
        'dart',
        'verify',
        'test',
        '--dir',
        '/tmp/acvm-workspace',
        '--',
        '--reporter=expanded',
      ], process: override);
      expect(refused.code, 64);
      expect(refused.err, contains('cannot be overridden'));
      expect(override.calls, isEmpty, reason: 'the usage refusal never spawns');
    });

    test('forwards the working directory and trailing arguments', () async {
      final process = _FakeVerifyProcess.always(
        _result(0, out: _reporterStream(passed: 1)),
      );
      await _runVerify([
        'dart',
        'verify',
        'test',
        '--dir',
        '/tmp/acvm-elsewhere',
        '--',
        '--concurrency=1',
        'test/probe_test.dart',
      ], process: process);

      expect(process.calls.single.workingDirectory, '/tmp/acvm-elsewhere');
      expect(process.calls.single.arguments, [
        'test',
        '--reporter=json',
        '--concurrency=1',
        'test/probe_test.dart',
      ]);
    });

    test('an omitted --dir runs in the current directory', () async {
      final process = _FakeVerifyProcess.always(_result(0));
      await _runVerify(['dart', 'verify', 'analyze'], process: process);
      expect(process.calls.single.workingDirectory, Directory.current.path);
    });
  });
}

/// The shared RED assertion: the whole child transcript reaches both sinks
/// uncapped, with its exact first and last line intact and no summary in sight.
Future<void> _expectRedPayload(String leaf) async {
  final out = _failureTranscript('OUT-${leaf.toUpperCase()}');
  final err = _failureTranscript('ERR-${leaf.toUpperCase()}');
  final process = _FakeVerifyProcess.always(_result(1, out: out, err: err));
  final run = await _runVerify([
    'dart',
    'verify',
    leaf,
    '--dir',
    '/tmp/acvm-workspace',
  ], process: process);

  expect(run.code, 1);
  expect(run.out, out);
  expect(run.err, err);
  expect(run.out, startsWith('BEGIN-OUT-${leaf.toUpperCase()}\n'));
  expect(run.out, endsWith('END-OUT-${leaf.toUpperCase()}'));
  expect(run.err, startsWith('BEGIN-ERR-${leaf.toUpperCase()}\n'));
  expect(run.err, endsWith('END-ERR-${leaf.toUpperCase()}'));
  expect(
    run.out.length,
    greaterThan(kMaxGreenVerificationOutputChars),
    reason: 'a failure payload is never capped',
  );
  expect(run.out, isNot(contains('"verdict"')));
}
