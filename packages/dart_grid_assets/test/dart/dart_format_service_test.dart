// The DART-domain FORMAT probe — the deterministic "would `dart format` change
// this?" question, asked WITHOUT ever rewriting a file. The process edge rides
// an injected Fake (Fakes, not mocks), so the whole surface tests offline: the
// argv, the sorted/deduplicated sweep, the accumulate-every-dirty-file posture,
// the zero-file no-process case, and the operational-failure terminal.
import 'dart:io';

import 'package:dart_grid_assets/dart_grid_assets.dart';
import 'package:test/test.dart';

/// A Fake [ProcessRunner]: records every call and answers from a per-file map
/// of canned results (a file with no entry is a clean exit).
class _FakeProcess {
  _FakeProcess.queue(this._resultByFile);

  final Map<String, ProcessResult> _resultByFile;
  final calls =
      <
        ({String executable, List<String> arguments, String? workingDirectory})
      >[];

  /// The file argument of every call, in call order.
  List<String> get files => [for (final c in calls) c.arguments.last];

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
    return _resultByFile[arguments.last] ?? ProcessResult(0, 0, '', '');
  }
}

/// A [ProcessRunner] that never launches — the `dart` that is not on PATH.
Future<ProcessResult> _explodingProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async => throw const ProcessException('dart', ['format'], 'no such file', 2);

void main() {
  group('DartFormatService.check', () {
    test(
      'checks each sorted, unique file once with the non-mutating argv',
      () async {
        final fake = _FakeProcess.queue(const {});
        final outcome = await DartFormatService(runProcess: fake.call).check(
          workspaceDir: '/worktree',
          files: const [
            'packages/b.dart',
            'packages/a.dart',
            'packages/b.dart',
          ],
        );

        expect(fake.files, ['packages/a.dart', 'packages/b.dart']);
        expect(fake.calls.first.executable, 'dart');
        expect(fake.calls.first.arguments, [
          'format',
          '--output=none',
          '--set-exit-if-changed',
          'packages/a.dart',
        ]);
        expect(fake.calls.first.workingDirectory, '/worktree');
        expect(outcome, isA<DartFormatClean>());
        expect((outcome as DartFormatClean).files, [
          'packages/a.dart',
          'packages/b.dart',
        ]);
      },
    );

    test('exit 1 names the file — and the sweep continues, so ONE call names '
        'EVERY dirty file', () async {
      final fake = _FakeProcess.queue({
        'packages/b.dart': ProcessResult(2, 1, 'Changed packages/b.dart\n', ''),
        'packages/c.dart': ProcessResult(3, 1, 'Changed packages/c.dart\n', ''),
      });
      final outcome = await DartFormatService(runProcess: fake.call).check(
        workspaceDir: '/worktree',
        files: const ['packages/c.dart', 'packages/b.dart', 'packages/a.dart'],
      );

      expect(fake.files, [
        'packages/a.dart',
        'packages/b.dart',
        'packages/c.dart',
      ]);
      expect(outcome, isA<DartFormatDirty>());
      expect((outcome as DartFormatDirty).files, [
        'packages/b.dart',
        'packages/c.dart',
      ]);
    });

    test('no files ⇒ clean with NO process spawned', () async {
      final fake = _FakeProcess.queue(const {});
      final outcome = await DartFormatService(
        runProcess: fake.call,
      ).check(workspaceDir: '/worktree', files: const []);

      expect(fake.calls, isEmpty);
      expect(outcome, isA<DartFormatClean>());
      expect((outcome as DartFormatClean).files, isEmpty);
    });

    test('a non-1 exit is an OPERATIONAL failure naming the file — never a '
        'clean bill', () async {
      final fake = _FakeProcess.queue({
        'packages/broken.dart': ProcessResult(
          1,
          65,
          '',
          'Could not format because the source could not be parsed',
        ),
      });
      final outcome = await DartFormatService(runProcess: fake.call).check(
        workspaceDir: '/worktree',
        files: const ['packages/broken.dart', 'packages/z.dart'],
      );

      expect(outcome, isA<DartFormatProbeFailed>());
      final failed = outcome as DartFormatProbeFailed;
      expect(failed.file, 'packages/broken.dart');
      expect(failed.exitCode, 65);
      expect(failed.output, contains('could not be parsed'));
      // Short-circuited: the sweep stops at the undecidable file.
      expect(fake.files, ['packages/broken.dart']);
    });

    test('a process that will not launch is an operational failure with a null '
        'exit code', () async {
      final outcome = await const DartFormatService(
        runProcess: _explodingProcess,
      ).check(workspaceDir: '/worktree', files: const ['packages/a.dart']);

      expect(outcome, isA<DartFormatProbeFailed>());
      final failed = outcome as DartFormatProbeFailed;
      expect(failed.file, 'packages/a.dart');
      expect(failed.exitCode, isNull);
      expect(failed.output, contains('no such file'));
    });
  });
}
