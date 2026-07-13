// The `install` Command — the THIN CLI adapter over the operator-install lib:
// parses argv, resolves the grid home from the injected resident-station
// context, renders the diff, commits nothing. Everything behavioral is the
// lib's (overlay_install_test.dart); this suite pins the adapter contract a
// composing station (`space install`) relies on. Offline: fake delegate, fake
// root resolver, captured sinks.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The composing station's resident-station context, rooted at [root].
class _StationDelegate extends sdk.GridDelegate {
  _StationDelegate(this.root);

  @override
  final String root;
  var disposed = false;

  @override
  Seed build(TreeContext context, sdk.GridConfiguration configuration) =>
      sdk.RawAssetGrid(root: root, assets: const []);

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// A delegate that authors NO grid root (a bare `Station` provides a
/// StationScope, never a GridRoot) — the LOUD-refusal case.
class _RootlessDelegate extends sdk.GridDelegate {
  _RootlessDelegate(this.root);

  @override
  final String root;

  @override
  Seed build(TreeContext context, sdk.GridConfiguration configuration) =>
      sdk.Station(name: 'test-station', root: root);
}

File _write(Directory root, List<String> segments, String contents) =>
    File(p.join(root.path, p.joinAll(segments)))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);

/// This package's root, resolved the CWD-INDEPENDENT way (the loader's own
/// package-config resolution, whose root is `<packageRoot>/extension`). Never a
/// cwd walk: `Directory.current` is process-global and the suites run
/// concurrently, so a sibling suite that chdirs to prove cwd-independence would
/// race a walk done here.
String _packageRoot() => p.dirname(PackagedAssetLoader().root);

void main() {
  late Directory temp;
  late Directory overlay;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('grid-install-cmd-');
    overlay = Directory(p.join(temp.path, 'pack'));
    _write(overlay, ['skills', 'discover', 'SKILL.md'],
        'call {{runner}} search, file into {{gridHome}}');
    _write(overlay, ['agents', 'governor', 'AGENT.md'], 'the operator');
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  ({
    CommandRunner<int> runner,
    _StationDelegate Function() lastDelegate,
    StringBuffer out,
    StringBuffer err,
  }) harness({List<String>? roots}) {
    final out = StringBuffer();
    final err = StringBuffer();
    _StationDelegate? last;
    final runner = CommandRunner<int>('space', 'test station')
      ..addCommand(
        InstallCommand(
          delegate: () => last = _StationDelegate(temp.path),
          roots: (gridHome) async => roots ?? [overlay.path],
          out: out,
          err: err,
        ),
      );
    return (runner: runner, lastDelegate: () => last!, out: out, err: err);
  }

  test(
      "expands the overlay into the grid home's OWN .claude/ by default, "
      'binding {{runner}} from the CLI verb and {{gridHome}} from the mounted '
      'GridRoot', () async {
    final h = harness();

    final code = await h.runner.run(['install']);

    expect(code, 0);
    final skill = File(
      p.join(temp.path, '.claude', 'skills', 'discover', 'SKILL.md'),
    );
    expect(skill.existsSync(), isTrue);
    expect(
        skill.readAsStringSync(), 'call space search, file into ${temp.path}');
    expect(
      File(p.join(temp.path, '.claude', 'agents', 'governor', 'AGENT.md'))
          .existsSync(),
      isTrue,
      reason: 'agents expand alongside skills',
    );
    expect(h.out.toString(), contains('--- /dev/null'));
    expect(h.out.toString(), contains('NOTHING was committed'));
    expect(h.lastDelegate().disposed, isTrue,
        reason: 'the command owns the delegate it asked for');
  });

  test('--target expands into an explicit dir; a re-run overwrites nothing',
      () async {
    final target = Directory(p.join(temp.path, 'elsewhere'));
    _write(
        target, ['skills', 'discover', 'SKILL.md'], 'the operator wrote this');

    final code =
        await harness().runner.run(['install', '--target', target.path]);

    expect(code, 0);
    expect(
      File(p.join(target.path, 'skills', 'discover', 'SKILL.md'))
          .readAsStringSync(),
      'the operator wrote this',
    );
  });

  test('--no-diff prints no diff body and never names a pre-existing file',
      () async {
    final target = Directory(p.join(temp.path, 'elsewhere'));
    _write(target, ['skills', 'discover', 'SKILL.md'], 'mine');
    final h = harness();

    final code =
        await h.runner.run(['install', '--no-diff', '--target', target.path]);

    expect(code, 0);
    expect(h.out.toString(), isNot(contains('--- /dev/null')));
    expect(h.out.toString(), isNot(contains('skipped (already present')));
    expect(h.out.toString(), contains('installed '));
  });

  test('an UNBOUND hole exits non-zero and says so on stdout (LOUD)', () async {
    _write(overlay, ['skills', 'ops', 'SKILL.md'], 'boot {{unbound}}');
    final h = harness();

    final code = await h.runner.run(['install']);

    expect(code, 1);
    expect(h.out.toString(), contains('REFUSED '));
    expect(h.out.toString(), contains('{{unbound}}'));
    expect(
      File(p.join(temp.path, '.claude', 'skills', 'ops', 'SKILL.md'))
          .existsSync(),
      isFalse,
    );
  });

  test('no overlay in scope is a LOUD non-answer, never a silent no-op',
      () async {
    final h = harness(roots: const []);

    final code = await h.runner.run(['install']);

    expect(code, 1);
    expect(h.err.toString(), contains('no package in ${temp.path} vends'));
  });

  test('a resident-station context with no grid root REFUSES and names the '
      'lever', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = CommandRunner<int>('space', 'test station')
      ..addCommand(
        InstallCommand(
          delegate: () => _RootlessDelegate(temp.path),
          roots: (gridHome) async => [overlay.path],
          out: out,
          err: err,
        ),
      );

    final code = await runner.run(['install']);

    expect(code, 1);
    expect(err.toString(), contains('--grid-home'));
  });

  test(
      'a LOUD lib refusal (no package config) is reported, never a stack trace',
      () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = CommandRunner<int>('space', 'test station')
      ..addCommand(
        InstallCommand(
          delegate: () => _StationDelegate(temp.path),
          roots: (gridHome) async =>
              throw StateError('no package config at $gridHome'),
          out: out,
          err: err,
        ),
      );

    final code = await runner.run(['install']);

    expect(code, 1);
    expect(err.toString(), contains('install: no package config'));
  });

  group('it COMMITS NOTHING — by construction', () {
    test('the operator-install source names no git and no process surface', () {
      final dir = Directory(p.join(_packageRoot(), 'lib', 'src', 'assets'));
      final source = [
        File(p.join(dir.path, 'install_command.dart')).readAsStringSync(),
        File(p.join(dir.path, 'overlay_install.dart')).readAsStringSync(),
      ].join('\n');

      for (final forbidden in const [
        'GitOps',
        'SourceControl',
        'Process.run',
        'Process.start',
        'Process.runSync',
        '.gitignore',
      ]) {
        expect(source, isNot(contains(forbidden)),
            reason: 'the operator leg commits nothing and writes no git '
                'artifact — the operator reviews the diff and commits');
      }
    });
  });
}
