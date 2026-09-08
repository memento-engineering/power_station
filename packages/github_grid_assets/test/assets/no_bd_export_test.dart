// The package library's READ-PATH FENCE.
//
// Every org store — and lunar's own grid state store — runs bd in
// PROXIED-SERVER mode, where `bd export` is refused outright ("export is not
// supported in proxied-server mode"). A library read that runs it therefore
// fails on EVERY cycle, and a failing delivery leg head-of-line blocks the
// reconciler's pending queue: the seat's GitHub poll stops advancing entirely.
// The engine retired export from its read paths for exactly this reason; this
// fence keeps the consumer from re-introducing it.
//
// SOURCE fence only. Test fixtures may still mention the refusal — that is how
// they prove the posture — and `beads_dart` remains a consumed external
// package with its own surface.
import 'dart:io';

import 'package:test/test.dart';

/// A direct `.run([...])` whose FIRST argv element is `export`, tolerating
/// whitespace, a newline-wrapped argument list and an optional `const`.
final RegExp _exportRun = RegExp(
  r'''\.run\(\s*(?:const\s+)?<?\s*(?:String)?\s*>?\s*\[\s*(?:'export'|"export")''',
);

void main() {
  test('no library source runs bd export', () {
    final library = Directory('lib');
    expect(
      library.existsSync(),
      isTrue,
      reason: 'the fence must run from the package root',
    );

    final offenders = <String>[
      for (final entity in library.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          if (_exportRun.hasMatch(entity.readAsStringSync())) entity.path,
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'a proxied-server store REFUSES `bd export`; read one scope with '
          "`BdCliService.listScope` instead (see CiFeedbackProjection's "
          'session read)',
    );
  });

  test('the fence itself is falsifiable', () {
    // A literal the fence must catch, so an empty offender list above means
    // "nothing runs export", not "the pattern never matches anything".
    const sample = "await bd.run(const ['export', '--all']);";
    expect(_exportRun.hasMatch(sample), isTrue);
    expect(_exportRun.hasMatch("await bd.run(const ['list', '-t'])"), isFalse);
  });
}
