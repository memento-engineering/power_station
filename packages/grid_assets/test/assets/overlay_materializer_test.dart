// The vended-asset OVERLAY materialization lib (bead `pow-kzx` — ADR-0001's
// missing delivery leg): [OverlayMaterializer] expands `station_overlay`-shaped
// roots onto a target `.claude/`-shaped dir — non-destructively, rendering each
// file, refusing a half-bound one, throwing on a malformed tree, unioning by
// tree position (the ORDER the roots are given in). The WIRE half (the provision
// hook that drives this into a live worktree, and the git exclusion it writes
// there) is covered in `track_h_code_extension_test.dart`.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Resolves this package's `extension/` dir with the same cwd walk the other
/// asset suites use, so the live-tree test never disagrees with the loader.
String _extensionDir() {
  final candidates = <String>[
    'extension',
    p.join('packages', 'grid_assets', 'extension'),
  ];
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    for (final rel in candidates) {
      final probe = Directory(p.join(dir.path, rel));
      if (probe.existsSync() &&
          Directory(p.join(probe.path, 'rubrics')).existsSync()) {
        return probe.path;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail(
    'could not locate packages/grid_assets/extension from '
    '${Directory.current.path}',
  );
}

/// Writes [contents] at [segments] under [root] (creating parents).
File _write(Directory root, List<String> segments, String contents) =>
    File(p.join(root.path, p.joinAll(segments)))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('grid-overlay-'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('OverlayMaterializer — fresh expand', () {
    test(
      'mirrors skills/ and agents/ onto the target, kind-prefixed, including a '
      'nested multi-file asset dir',
      () async {
        final overlay = Directory(p.join(temp.path, 'overlay'));
        _write(overlay, ['skills', 'foo', 'SKILL.md'], 'foo skill');
        _write(overlay, [
          'skills',
          'foo',
          'references',
          'notes.md',
        ], 'foo notes');
        _write(overlay, ['agents', 'bar', 'AGENT.md'], 'bar agent');
        final target = p.join(temp.path, 'target');

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlay.path],
          targetRoot: target,
        );

        expect(
          File(p.join(target, 'skills', 'foo', 'SKILL.md')).readAsStringSync(),
          'foo skill',
        );
        expect(
          File(
            p.join(target, 'skills', 'foo', 'references', 'notes.md'),
          ).readAsStringSync(),
          'foo notes',
        );
        expect(
          File(p.join(target, 'agents', 'bar', 'AGENT.md')).readAsStringSync(),
          'bar agent',
        );
        expect(
          report.written.map((f) => f.relativePath),
          unorderedEquals([
            p.join('skills', 'foo', 'SKILL.md'),
            p.join('skills', 'foo', 'references', 'notes.md'),
            p.join('agents', 'bar', 'AGENT.md'),
          ]),
        );
        expect(report.skipped, isEmpty);
        expect(report.refused, isEmpty);
        expect(report.installedSkillIds, ['foo']);
        expect(
          report.writtenEntryDirs,
          unorderedEquals([p.join('agents', 'bar'), p.join('skills', 'foo')]),
        );
      },
    );

    test(
      'an overlay root with neither skills/ nor agents/ contributes nothing (an '
      'empty overlay is not an error)',
      () async {
        final overlay = Directory(p.join(temp.path, 'empty'))
          ..createSync(recursive: true);
        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlay.path],
          targetRoot: p.join(temp.path, 'target'),
        );
        expect(report.files, isEmpty);
      },
    );

    test('an empty overlayRoots list contributes nothing (not an error)', () async {
      final report = await const OverlayMaterializer().materialize(
        overlayRoots: const [],
        targetRoot: p.join(temp.path, 'target'),
      );
      expect(report.files, isEmpty);
    });

    test(
      'materializeSync — the entry point the provision wire rides, since '
      'ProcessCapability.spawn cannot await — mirrors materialize',
      () {
        final overlay = Directory(p.join(temp.path, 'sync'));
        _write(overlay, ['skills', 'foo', 'SKILL.md'], 'sync body');
        final target = p.join(temp.path, 'target-sync');

        final report = const OverlayMaterializer().materializeSync(
          overlayRoots: [overlay.path],
          targetRoot: target,
        );

        expect(
          File(p.join(target, 'skills', 'foo', 'SKILL.md')).readAsStringSync(),
          'sync body',
        );
        expect(
          report.written.single.relativePath,
          p.join('skills', 'foo', 'SKILL.md'),
        );
        expect(report.skipped, isEmpty);
        expect(report.refused, isEmpty);
      },
    );
  });

  group('OverlayMaterializer — non-destructive (skip-existing)', () {
    test(
      "a pre-existing target file is NEVER overwritten — the operator's bytes "
      'survive (positive control: the overlay offers DIFFERENT bytes at the '
      'same path)',
      () async {
        final overlay = Directory(p.join(temp.path, 'overlay'));
        _write(overlay, ['skills', 'foo', 'SKILL.md'], 'vended body');
        final target = Directory(p.join(temp.path, 'target'));
        final existing = _write(target, [
          'skills',
          'foo',
          'SKILL.md',
        ], 'OPERATOR — keep me');

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlay.path],
          targetRoot: target.path,
        );

        expect(existing.readAsStringSync(), 'OPERATOR — keep me');
        expect(report.written, isEmpty);
        expect(
          report.skipped.single.relativePath,
          p.join('skills', 'foo', 'SKILL.md'),
        );
        // Present at the target — an operator's own copy is still installed…
        expect(report.installedSkillIds, ['foo']);
        // …but this call wrote nothing, so there is nothing new to git-exclude.
        expect(report.writtenEntryDirs, isEmpty);
      },
    );
  });

  group('OverlayMaterializer — render + refuse', () {
    test('declared args are substituted into every copied file', () async {
      final overlay = Directory(p.join(temp.path, 'overlay'));
      _write(overlay, [
        'skills',
        'foo',
        'SKILL.md',
      ], 'run {{runner}} search in {{gridHome}}');
      final target = p.join(temp.path, 'target');

      await const OverlayMaterializer().materialize(
        overlayRoots: [overlay.path],
        targetRoot: target,
        args: const {'runner': 'space', 'gridHome': '/grid/home'},
      );

      expect(
        File(p.join(target, 'skills', 'foo', 'SKILL.md')).readAsStringSync(),
        'run space search in /grid/home',
      );
    });

    test(
      'a file left with an UNBOUND hole is REFUSED — never written (a half-bound '
      'skill would read as literal text to the agent)',
      () async {
        final overlay = Directory(p.join(temp.path, 'overlay'));
        _write(overlay, [
          'skills',
          'foo',
          'SKILL.md',
        ], 'run {{runner}} in {{gridHome}}');
        final target = p.join(temp.path, 'target');

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlay.path],
          targetRoot: target,
          args: const {'runner': 'space'},
        );

        expect(
          File(p.join(target, 'skills', 'foo', 'SKILL.md')).existsSync(),
          isFalse,
          reason: 'a half-bound asset is installed NOWHERE',
        );
        expect(report.written, isEmpty);
        final refused = report.refused.single;
        expect(refused.relativePath, p.join('skills', 'foo', 'SKILL.md'));
        expect(refused.holes, ['{{gridHome}}']);
        expect(refused.reason, contains('{{gridHome}}'));
        expect(
          report.installedSkillIds,
          isEmpty,
          reason: 'a refused skill must never be named to an agent',
        );
      },
    );
  });

  group('OverlayMaterializer — the format is enforced LOUD', () {
    test(
      'a file loose directly under a kind dir (no asset dir) THROWS — a '
      'malformed vended tree is a packaging bug, never a silent half-install',
      () {
        final overlay = Directory(p.join(temp.path, 'malformed'));
        _write(overlay, ['skills', 'stray.md'], 'no asset dir');

        expect(
          () => const OverlayMaterializer().materializeSync(
            overlayRoots: [overlay.path],
            targetRoot: p.join(temp.path, 'target'),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(contains('stray.md'), contains('malformed overlay')),
            ),
          ),
        );
      },
    );
  });

  group('OverlayMaterializer — union by tree position', () {
    test('two roots with distinct skills both land — a true union', () async {
      final a = Directory(p.join(temp.path, 'a'));
      _write(a, ['skills', 'alpha', 'SKILL.md'], 'alpha');
      final b = Directory(p.join(temp.path, 'b'));
      _write(b, ['skills', 'beta', 'SKILL.md'], 'beta');
      final target = p.join(temp.path, 'target');

      final report = await const OverlayMaterializer().materialize(
        overlayRoots: [a.path, b.path],
        targetRoot: target,
      );

      expect(
        File(p.join(target, 'skills', 'alpha', 'SKILL.md')).readAsStringSync(),
        'alpha',
      );
      expect(
        File(p.join(target, 'skills', 'beta', 'SKILL.md')).readAsStringSync(),
        'beta',
      );
      expect(report.written, hasLength(2));
      expect(report.installedSkillIds, ['alpha', 'beta']);
    });

    test(
      'two roots offering the SAME path — the EARLIER tree position wins (the '
      'same skip-existing mechanism as the non-destructive case)',
      () async {
        final a = Directory(p.join(temp.path, 'a'));
        _write(a, ['skills', 'discover', 'SKILL.md'], 'root A wins');
        final b = Directory(p.join(temp.path, 'b'));
        _write(b, ['skills', 'discover', 'SKILL.md'], 'root B loses');
        final target = p.join(temp.path, 'target');

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [a.path, b.path],
          targetRoot: target,
        );

        expect(
          File(
            p.join(target, 'skills', 'discover', 'SKILL.md'),
          ).readAsStringSync(),
          'root A wins',
        );
        expect(report.written.single.sourceRoot, a.path);
        expect(report.skipped, hasLength(1));
      },
    );
  });

  group('OverlayMaterializer — the live grid_assets station_overlay', () {
    test(
      'the REAL extension/station_overlay round-trips the vended discover skill: '
      'a non-empty, frontmatter-led SKILL.md with no {{ residue',
      () async {
        final overlayRoot = p.join(_extensionDir(), 'station_overlay');
        final target = p.join(temp.path, 'live');

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlayRoot],
          targetRoot: target,
          args: const {'runner': 'space', 'gridHome': '/grid/home'},
        );

        final installed = File(
          p.join(target, 'skills', 'discover', 'SKILL.md'),
        );
        expect(installed.existsSync(), isTrue);
        final body = installed.readAsStringSync();
        expect(body, startsWith('---\n'));
        expect(body, contains('space search --json'));
        expect(body, contains('/grid/home'));
        expect(body, isNot(contains('{{')));
        expect(report.installedSkillIds, contains('discover'));
        expect(report.refused, isEmpty);
      },
    );

    test(
      'the source has NO CLI and NO git dependency (UI-drivable — pow-a74 is the '
      'only CLI seam, and the wire owns git exclusion)',
      () {
        final packageRoot = p.dirname(_extensionDir());
        final source = File(
          p.join(
            packageRoot,
            'lib',
            'src',
            'assets',
            'overlay_materializer.dart',
          ),
        ).readAsStringSync();
        expect(source, isNot(contains('package:args')));
        expect(source, isNot(contains('CommandRunner')));
        expect(source, isNot(contains('GitRunner')));
      },
    );
  });
}
