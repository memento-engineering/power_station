// The package library's READ-PATH FENCE.
//
// A per-store `SubstationBeadSource` read is SCOPED, and `bd export --all` is
// not issued by any source here:
// power_station#the-per-store-bead-read-is-scoped-never-the-export-surface,
// which amends A11 clause (3) — where the ratified per-store read WAS the
// export argv, "held BY CONSTRUCTION, not by a runtime guard".
//
// This fence is what keeps that phrase true after the mechanism changed. The
// export surface cannot answer a store read at all: every org store runs bd in
// PROXIED-SERVER mode — the only mode a CGO-free bd offers — where it is
// refused outright ("export is not supported in proxied-server mode"), and
// older builds were worse, returning exit zero and an EMPTY export for a
// NON-empty store. `BdCliService.exportAll` survives upstream only as a
// refusal tombstone. An empty read that cannot be told apart from an
// unreachable store is the one answer a bead catalog must never produce,
// because it would refuse every id a bead cites.
//
// The sibling `github_grid_assets` carries the same fence over its own lib.
//
// SOURCE fence only. Tests and fixtures may still mention the refusal — that
// is how they prove the posture — and `beads_dart` remains a consumed external
// package with its own surface.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/package_root.dart';

/// A direct `.run([...])` whose FIRST argv element is `export`, tolerating
/// whitespace, a newline-wrapped argument list and an optional `const`.
final RegExp _exportRun = RegExp(
  r'''\.run\(\s*(?:const\s+)?<?\s*(?:String)?\s*>?\s*\[\s*(?:'export'|"export")''',
);

void main() {
  test('no library source runs bd export', () {
    // `packageRoot()`, never the process cwd: concurrent isolates share that
    // global, so a cwd-relative read here is a cross-suite race.
    final library = Directory(p.join(packageRoot(), 'lib'));
    expect(
      library.existsSync(),
      isTrue,
      reason: 'the fence must resolve this package\'s own lib/',
    );

    final offenders = <String>[
      for (final entity in library.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          if (_exportRun.hasMatch(entity.readAsStringSync()))
            p.relative(entity.path, from: packageRoot()),
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'a proxied-server store REFUSES `bd export`; read one scope instead '
          '— an all-status `query` for a match corpus (BdExportBeadSource) or '
          'a per-core-type `list` for an id catalog (BdListAllStatusBeadSource)',
    );
  });

  test('the fence itself is falsifiable', () {
    // A literal the fence must catch, so an empty offender list above means
    // "nothing runs export", not "the pattern never matches anything".
    const sample = "await bd.run(const ['export', '--all']);";
    expect(_exportRun.hasMatch(sample), isTrue);
    // And the two scoped reads this package DOES issue must survive it.
    expect(
      _exportRun.hasMatch("await runner.run(['list', '-t', 'task'])"),
      isFalse,
    );
    expect(
      _exportRun.hasMatch("await runner.run(['query', expression])"),
      isFalse,
    );
  });
}
