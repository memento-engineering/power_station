import 'dart:io';

import 'package:args/args.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The SHARED `--state-root` contract, on its own, now that only the verbs
/// which genuinely reach the grid home's state store register it (`park`,
/// `show`).
///
/// `filing`, `approve` and `unpark` retired the option with the cross-store
/// read that was its only reader
/// (`power_station#the-dependencies-row-is-a-projection-of-bd-dependency-rows`),
/// so the module's own resolution rules are asserted here rather than through
/// a verb that no longer takes it.

/// Creates a REAL grid home — `<home>/.grid/.beads` — because the resolver
/// probes the filesystem to tell a grid home from its own state store.
String _gridHome() {
  final home = Directory.systemTemp.createTempSync('grid-home-');
  Directory(p.join(home.path, '.grid', '.beads')).createSync(recursive: true);
  addTearDown(() => home.deleteSync(recursive: true));
  return home.path;
}

/// Creates a directory holding NEITHER `.grid` nor `.beads`.
String _unrelatedRoot() {
  final root = Directory.systemTemp.createTempSync('not-a-grid-home-');
  addTearDown(() => root.deleteSync(recursive: true));
  return root.path;
}

void main() {
  test('the option accepts a grid home or its state store, and refuses an '
      'unrelated root', () {
    final parser = ArgParser();
    addStateRootOption(parser);
    String? resolve(String? value) => resolveStateRoot(
      parser.parse(value == null ? const [] : ['--state-root', value]),
      noStateRoot,
    );

    // The help documents the GRID HOME, and both accepted forms land on the
    // same `.grid` state store — so the documented value is the working one.
    // It names the home rather than either store because that is where the
    // session-lifecycle beads live.
    expect(
      kStateRootHelp,
      'The grid home whose .grid/.beads holds the session-lifecycle state '
      'beads.',
    );
    final home = _gridHome();
    final store = p.join(home, '.grid');
    expect(resolve(home), store);
    expect(resolve('$home${p.separator}.'), store);
    expect(resolve(store), store);

    // No value on either seam means no home was named at all.
    expect(noStateRoot(), isNull);
    expect(resolve(null), isNull);
    expect(resolve('   '), isNull);
    expect(resolveStateRoot(parser.parse(const []), () => home), store);
    expect(resolveStateRoot(parser.parse(const []), () => '  '), isNull);

    // Guards LOUD or GONE: a root holding neither child is refused by name.
    final unrelated = _unrelatedRoot();
    expect(
      () => resolve(unrelated),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains(unrelated), contains('.grid'), contains('.beads')),
        ),
      ),
    );
  });
}
