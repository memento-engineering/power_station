// The `assets install` Command — the THIN CLI adapter over the operator-install
// lib: parses argv, resolves the grid home from the injected resident-station
// context, renders the diff, commits nothing. Everything behavioral is the
// lib's (overlay_install_test.dart); this suite pins the adapter contract a
// composing station (`space assets install`) relies on. Offline: fake delegate,
// fake root resolver, injected source ref (so no git subprocess), captured sinks.
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
    temp = Directory.systemTemp.createTempSync('grid-assets-cmd-');
    overlay = Directory(p.join(temp.path, 'pack'));
    _write(
      overlay,
      ['.claude', 'skills', 'discover', 'SKILL.md'],
      '---\nname: discover\n---\n'
          'call {{runner}} search, file into {{gridHome}}\n',
    );
    _write(overlay, [
      '.claude',
      'agents',
      'governor.md',
    ], '---\nname: governor\n---\nthe operator\n');
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  ({
    CommandRunner<int> runner,
    _StationDelegate Function() lastDelegate,
    StringBuffer out,
    StringBuffer err,
  })
  harness({List<String>? roots}) {
    final out = StringBuffer();
    final err = StringBuffer();
    _StationDelegate? last;
    final runner = CommandRunner<int>('space', 'test station')
      ..addCommand(
        AssetsCommand(
          delegate: () => last = _StationDelegate(temp.path),
          roots: (gridHome) async => roots ?? [overlay.path],
          sourceRef: (_) => 'testref',
          out: out,
          err: err,
        ),
      );
    return (runner: runner, lastDelegate: () => last!, out: out, err: err);
  }

  File installedSkill(Directory root) =>
      File(p.join(root.path, '.claude', 'skills', 'discover', 'SKILL.md'));

  test(
    'expands the overlay onto the grid home ROOT by default, PATH-PRESERVING — '
    'binding {{runner}} from the CLI verb and {{gridHome}} from the mounted '
    'GridRoot, and stamping each file with the source ref',
    () async {
      final h = harness();

      final code = await h.runner.run(['assets', 'install']);

      expect(code, 0);
      final skill = installedSkill(temp);
      expect(skill.existsSync(), isTrue);
      final body = skill.readAsStringSync();
      expect(body, contains('call space search, file into ${temp.path}'));
      expect(body, contains('testref'));
      expect(hasProvenance(body), isTrue);
      expect(
        File(p.join(temp.path, '.claude', 'agents', 'governor.md')).existsSync(),
        isTrue,
        reason: 'the agent def expands alongside the skills',
      );
      expect(h.out.toString(), contains('--- /dev/null'));
      expect(h.out.toString(), contains('NOTHING was committed'));
      expect(
        h.lastDelegate().disposed,
        isTrue,
        reason: 'the command owns the delegate it asked for',
      );
    },
  );

  test('--root overlays onto an explicit repo root', () async {
    final elsewhere = Directory(p.join(temp.path, 'elsewhere'))
      ..createSync(recursive: true);

    final code = await harness().runner.run([
      'assets',
      'install',
      '--root',
      elsewhere.path,
    ]);

    expect(code, 0);
    expect(installedSkill(elsewhere).existsSync(), isTrue);
    expect(
      installedSkill(temp).existsSync(),
      isFalse,
      reason: 'the default root was not touched',
    );
  });

  test('--source-ref overrides the probed ref in every provenance header', () async {
    final code = await harness().runner.run([
      'assets',
      'install',
      '--source-ref',
      'v1.2.3',
    ]);

    expect(code, 0);
    expect(installedSkill(temp).readAsStringSync(), contains('v1.2.3'));
  });

  test('--no-diff prints no diff body but still names what it installed', () async {
    final h = harness();

    final code = await h.runner.run(['assets', 'install', '--no-diff']);

    expect(code, 0);
    expect(h.out.toString(), isNot(contains('--- /dev/null')));
    expect(h.out.toString(), contains('installed '));
  });

  group('--check — the no-drift enforcement', () {
    test('writes NOTHING and exits non-zero, naming each MISSING file', () async {
      final h = harness();

      final code = await h.runner.run(['assets', 'install', '--check']);

      expect(code, 1);
      expect(h.out.toString(), contains('MISSING '));
      expect(
        installedSkill(temp).existsSync(),
        isFalse,
        reason: '--check is a PLAN — it writes nothing',
      );
    });

    test('a clean install makes --check PASS', () async {
      expect(await harness().runner.run(['assets', 'install']), 0);

      expect(await harness().runner.run(['assets', 'install', '--check']), 0);
    });

    test(
      'editing an installed file makes --check FAIL with a per-file DRIFTED line',
      () async {
        expect(await harness().runner.run(['assets', 'install']), 0);
        final installed = installedSkill(temp);
        installed.writeAsStringSync(
          '${installed.readAsStringSync()}\nhand edit\n',
        );
        final h = harness();

        final code = await h.runner.run(['assets', 'install', '--check']);

        expect(code, 1);
        expect(h.out.toString(), contains('DRIFTED '));
        expect(h.out.toString(), contains('SKILL.md'));
      },
    );
  });

  test(
    'a hand-authored file (no provenance header) is BLOCKED, never clobbered',
    () async {
      final mine = installedSkill(temp)..createSync(recursive: true);
      mine.writeAsStringSync('the operator wrote this');
      final h = harness();

      final code = await h.runner.run(['assets', 'install']);

      expect(code, 1);
      expect(h.out.toString(), contains('BLOCKED '));
      expect(mine.readAsStringSync(), 'the operator wrote this');
    },
  );

  test('an UNBOUND hole exits non-zero and says so on stdout (LOUD)', () async {
    _write(overlay, [
      '.claude',
      'skills',
      'ops',
      'SKILL.md',
    ], '---\nname: ops\n---\nboot {{unbound}}\n');
    final h = harness();

    final code = await h.runner.run(['assets', 'install']);

    expect(code, 1);
    expect(h.out.toString(), contains('REFUSED '));
    expect(h.out.toString(), contains('{{unbound}}'));
    expect(
      File(
        p.join(temp.path, '.claude', 'skills', 'ops', 'SKILL.md'),
      ).existsSync(),
      isFalse,
    );
  });

  test('no overlay in scope is a LOUD non-answer, never a silent no-op', () async {
    final h = harness(roots: const []);

    final code = await h.runner.run(['assets', 'install']);

    expect(code, 1);
    expect(h.err.toString(), contains('no package in ${temp.path} vends'));
  });

  test(
    'a resident-station context with no grid root REFUSES and names the lever',
    () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = CommandRunner<int>('space', 'test station')
        ..addCommand(
          AssetsCommand(
            delegate: () => _RootlessDelegate(temp.path),
            roots: (gridHome) async => [overlay.path],
            sourceRef: (_) => 'testref',
            out: out,
            err: err,
          ),
        );

      final code = await runner.run(['assets', 'install']);

      expect(code, 1);
      expect(err.toString(), contains('--grid-home'));
    },
  );

  test(
    'a LOUD lib refusal (no package config) is reported, never a stack trace',
    () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = CommandRunner<int>('space', 'test station')
        ..addCommand(
          AssetsCommand(
            delegate: () => _StationDelegate(temp.path),
            roots: (gridHome) async =>
                throw StateError('no package config at $gridHome'),
            sourceRef: (_) => 'testref',
            out: out,
            err: err,
          ),
        );

      final code = await runner.run(['assets', 'install']);

      expect(code, 1);
      expect(err.toString(), contains('assets install: no package config'));
    },
  );

  group('it COMMITS NOTHING — by construction', () {
    test('the operator-install source names no git and no process surface', () {
      final dir = Directory(p.join(_packageRoot(), 'lib', 'src', 'assets'));
      final source = [
        File(p.join(dir.path, 'assets_command.dart')).readAsStringSync(),
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
        expect(
          source,
          isNot(contains(forbidden)),
          reason:
              'the operator leg commits nothing and writes no git artifact — '
              'the operator reviews the diff and commits',
        );
      }
    });

    test(
      'the ONE git call the leg can reach is the READ-ONLY source-ref probe — '
      'so the invariant above holds for the code the Command actually runs, not '
      'merely for the two files the grep covers',
      () {
        final source = File(
          p.join(
            _packageRoot(),
            'lib',
            'src',
            'assets',
            'overlay_provenance.dart',
          ),
        ).readAsStringSync();

        final invocations = RegExp(
          r"Process\.runSync\(\s*'git',\s*const \[([^\]]*)\]",
        ).allMatches(source).toList();
        expect(
          invocations,
          hasLength(1),
          reason: 'exactly one git invocation in the whole leg',
        );
        expect(invocations.single.group(1), contains("'rev-parse'"));
        for (final mutating in const [
          "'commit'",
          "'push'",
          "'add'",
          "'checkout'",
          "'reset'",
        ]) {
          expect(
            source,
            isNot(contains(mutating)),
            reason: 'the probe reads a ref; it never mutates a repo',
          );
        }
      },
    );
  });
}
