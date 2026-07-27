// The vended-asset OVERLAY materialization lib: [OverlayMaterializer] expands
// `station_overlay`-shaped roots onto a target ROOT, PATH-PRESERVING (the
// overlay's own tree IS the target layout — no kind mapping), rendering each
// file, refusing a half-bound one, stamping what it writes, never clobbering
// what it did not generate, and unioning by tree position (the ORDER the roots
// are given in). The WIRE half (the provision hook that drives this into a live
// worktree, and the git exclusion it writes there) is covered in
// `track_h_code_extension_test.dart` + `overlay_golden_test.dart`.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Resolves this package's `extension/` dir the CWD-INDEPENDENT way (the
/// loader's own package-config resolution), so the live-tree test never
/// disagrees with the loader.
///
/// Never a cwd walk: `Directory.current` is process-global and the suites run
/// concurrently, so the sibling suite that chdirs to a foreign dir to prove
/// cwd-independent resolution (`track_d_assets_test`) would race a walk done
/// from inside a test body here.
String _extensionDir() => PackagedAssetLoader().root;

/// Writes [contents] at [segments] under [root] (creating parents).
File _write(Directory root, List<String> segments, String contents) =>
    File(p.join(root.path, p.joinAll(segments)))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);

/// A stampable (frontmatter-led) SKILL.md body — what the overlay actually
/// vends, and the only shape the provenance stamp accepts for a `.md`.
String _skill(String name, [String body = 'body']) =>
    '---\nname: $name\n---\n$body\n';

void main() {
  late Directory temp;
  late Directory overlay;
  late Directory target;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('grid-overlay-');
    overlay = Directory(p.join(temp.path, 'overlay'));
    target = Directory(p.join(temp.path, 'target'));
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('OverlayMaterializer — fresh expand (PATH-PRESERVING)', () {
    test(
      "the overlay's own tree IS the target layout — a file at <overlay>/<rel> "
      'lands at <root>/<rel>, with no kind mapping, including a nested '
      'multi-file asset dir and a LOOSE file outside any asset dir',
      () async {
        _write(overlay, [
          '.claude',
          'skills',
          'foo',
          'SKILL.md',
        ], _skill('foo'));
        _write(overlay, [
          '.claude',
          'skills',
          'foo',
          'references',
          'notes.md',
        ], _skill('notes'));
        _write(overlay, [
          '.claude',
          'agents',
          'governor.md',
        ], _skill('governor'));
        _write(overlay, ['.claude', 'settings.json'], '{\n  "hooks": {}\n}\n');

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlay.path],
          targetRoot: target.path,
          sourceRef: 'testref',
        );

        expect(
          report.written.map((f) => f.relativePath),
          unorderedEquals([
            p.join('.claude', 'skills', 'foo', 'SKILL.md'),
            p.join('.claude', 'skills', 'foo', 'references', 'notes.md'),
            p.join('.claude', 'agents', 'governor.md'),
            p.join('.claude', 'settings.json'),
          ]),
        );
        // A loose file under `.claude/` is LEGAL now — the format is the target's
        // own layout, and `settings.json` genuinely lives there.
        expect(
          File(p.join(target.path, '.claude', 'settings.json')).existsSync(),
          isTrue,
        );
        expect(
          File(
            p.join(target.path, '.claude', 'agents', 'governor.md'),
          ).readAsStringSync(),
          contains('name: governor'),
        );
        expect(report.blocked, isEmpty);
        expect(report.refused, isEmpty);
        expect(report.installedSkillIdsUnder(kClaudeSkillsSubtree), ['foo']);
      },
    );

    test(
      'subtrees SCOPE the expansion — the worktree leg takes the skills tree '
      'only, never a loose .claude/settings.json',
      () async {
        _write(overlay, ['.claude', 'skills', 'a', 'SKILL.md'], _skill('a'));
        _write(overlay, ['.claude', 'settings.json'], '{\n  "hooks": {}\n}\n');

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlay.path],
          targetRoot: target.path,
          sourceRef: 'testref',
          subtrees: const [kClaudeSkillsSubtree],
        );

        expect(report.written.map((f) => f.relativePath), [
          p.join('.claude', 'skills', 'a', 'SKILL.md'),
        ]);
        expect(
          File(p.join(target.path, '.claude', 'settings.json')).existsSync(),
          isFalse,
          reason: 'a scoped caller never reaches repo-owned territory (A23(6))',
        );
      },
    );

    test('an overlay root with nothing in scope contributes nothing (an empty '
        'overlay is not an error)', () async {
      final empty = Directory(p.join(temp.path, 'empty'))
        ..createSync(recursive: true);
      final report = await const OverlayMaterializer().materialize(
        overlayRoots: [empty.path],
        targetRoot: target.path,
        sourceRef: 'testref',
        subtrees: const [kClaudeSkillsSubtree],
      );
      expect(report.files, isEmpty);
    });

    test(
      'an empty overlayRoots list contributes nothing (not an error)',
      () async {
        final report = await const OverlayMaterializer().materialize(
          overlayRoots: const [],
          targetRoot: target.path,
          sourceRef: 'testref',
        );
        expect(report.files, isEmpty);
      },
    );

    test('materializeSync — the entry point the provision wire rides, since '
        'ProcessCapability.spawn cannot await — mirrors materialize', () {
      _write(overlay, ['.claude', 'skills', 'foo', 'SKILL.md'], _skill('foo'));

      final report = const OverlayMaterializer().materializeSync(
        overlayRoots: [overlay.path],
        targetRoot: target.path,
        sourceRef: 'testref',
      );

      expect(
        File(
          p.join(target.path, '.claude', 'skills', 'foo', 'SKILL.md'),
        ).readAsStringSync(),
        contains('name: foo'),
      );
      expect(
        report.written.single.relativePath,
        p.join('.claude', 'skills', 'foo', 'SKILL.md'),
      );
      expect(report.blocked, isEmpty);
      expect(report.refused, isEmpty);
    });
  });

  group('OverlayMaterializer — provenance', () {
    test(
      'every written file carries the stamp, naming the source ref',
      () async {
        _write(overlay, ['.claude', 'skills', 'a', 'SKILL.md'], _skill('a'));

        await const OverlayMaterializer().materialize(
          overlayRoots: [overlay.path],
          targetRoot: target.path,
          sourceRef: 'abc1234',
          args: const {'runner': 'space'},
        );

        final body = File(
          p.join(target.path, '.claude', 'skills', 'a', 'SKILL.md'),
        ).readAsStringSync();
        expect(hasProvenance(body), isTrue);
        expect(body, contains('abc1234'));
        expect(body, contains('`space assets install`'));
        expect(
          body,
          startsWith('---\n'),
          reason: 'the frontmatter still opens on line 1',
        );
      },
    );

    test('a re-materialize is IDEMPOTENT: an unchanged generated file is left '
        'byte-for-byte alone, even under a DIFFERENT source ref (a stale ref is '
        'not drift — re-stamping would churn the tree for nothing)', () async {
      _write(overlay, ['.claude', 'skills', 'a', 'SKILL.md'], _skill('a'));
      const m = OverlayMaterializer();
      final first = await m.materialize(
        overlayRoots: [overlay.path],
        targetRoot: target.path,
        sourceRef: 'ref1',
      );
      final onDisk = File(
        p.join(target.path, '.claude', 'skills', 'a', 'SKILL.md'),
      ).readAsStringSync();

      final second = await m.materialize(
        overlayRoots: [overlay.path],
        targetRoot: target.path,
        sourceRef: 'ref2',
      );

      expect(first.written, hasLength(1));
      expect(second.written, isEmpty);
      expect(second.unchanged, hasLength(1));
      expect(
        File(
          p.join(target.path, '.claude', 'skills', 'a', 'SKILL.md'),
        ).readAsStringSync(),
        onDisk,
      );
    });

    test(
      'a DRIFTED generated file is regenerated; a HAND-AUTHORED one (no stamp) '
      'is BLOCKED, never clobbered',
      () async {
        _write(overlay, [
          '.claude',
          'skills',
          'a',
          'SKILL.md',
        ], _skill('a', 'new body'));
        _write(overlay, ['.claude', 'skills', 'b', 'SKILL.md'], _skill('b'));
        final drifted = _write(
          target,
          ['.claude', 'skills', 'a', 'SKILL.md'],
          stampProvenance(
            _skill('a', 'OLD body'),
            relativePath: '.claude/skills/a/SKILL.md',
            sourceRef: 'old',
            runner: 'space',
          ),
        );
        final mine = _write(target, [
          '.claude',
          'skills',
          'b',
          'SKILL.md',
        ], 'I wrote this');

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlay.path],
          targetRoot: target.path,
          sourceRef: 'ref2',
        );

        expect(report.updated.map((f) => f.relativePath), [
          p.join('.claude', 'skills', 'a', 'SKILL.md'),
        ]);
        expect(report.blocked.map((f) => f.relativePath), [
          p.join('.claude', 'skills', 'b', 'SKILL.md'),
        ]);
        expect(drifted.readAsStringSync(), contains('new body'));
        expect(mine.readAsStringSync(), 'I wrote this');
        expect(
          report.installedSkillIdsUnder(kClaudeSkillsSubtree),
          ['a'],
          reason:
              'a BLOCKED skill is not installed from the vended source, so a '
              'brief must never name it',
        );
      },
    );

    test('a dryRun writes NOTHING — every outcome is what WOULD happen (the '
        '--check drift mode)', () async {
      _write(overlay, ['.claude', 'skills', 'a', 'SKILL.md'], _skill('a'));

      final report = await const OverlayMaterializer().materialize(
        overlayRoots: [overlay.path],
        targetRoot: target.path,
        sourceRef: 'testref',
        dryRun: true,
      );

      expect(report.dryRun, isTrue);
      expect(report.written, hasLength(1));
      expect(
        File(
          p.join(target.path, '.claude', 'skills', 'a', 'SKILL.md'),
        ).existsSync(),
        isFalse,
        reason: 'a --check is a PLAN',
      );
    });

    test(
      'a SYMLINK at the target is BLOCKED, never followed — writing through one '
      'would mutate a file OUTSIDE the target root (and this is exactly how an '
      'operator seat hand-wires its assets today)',
      () async {
        _write(overlay, ['.claude', 'skills', 'a', 'SKILL.md'], _skill('a'));
        // The seat's shape: `.claude/skills/a/SKILL.md -> <outside>/SKILL.md`.
        final outside = _write(
          Directory(p.join(temp.path, 'extension')),
          ['skills', 'a', 'SKILL.md'],
          'the REAL file, outside the target root',
        );
        Link(p.join(target.path, '.claude', 'skills', 'a', 'SKILL.md'))
          ..parent.createSync(recursive: true)
          ..createSync(outside.path);

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlay.path],
          targetRoot: target.path,
          sourceRef: 'testref',
        );

        expect(report.blocked.single.symlink, isTrue);
        expect(report.blocked.single.reason, contains('SYMLINK'));
        expect(report.written, isEmpty);
        expect(
          outside.readAsStringSync(),
          'the REAL file, outside the target root',
          reason: 'the lib writes NOTHING outside the target root',
        );
      },
    );

    test(
      'a symlinked ANCESTOR DIR is BLOCKED too — the file under it is not itself '
      'a link, but a write would still land outside the target root. This is '
      "the operator seat's REAL shape (`.claude/skills/x -> "
      '../../extension/skills/x`)',
      () async {
        _write(overlay, ['.claude', 'skills', 'a', 'SKILL.md'], _skill('a'));
        // The real file lives OUTSIDE the target root, and — the dangerous part
        // — it already carries a stamp, so only the ancestor check can stop the
        // write from following the dir link and mutating it.
        final outside = _write(
          Directory(p.join(temp.path, 'extension')),
          ['skills', 'a', 'SKILL.md'],
          stampProvenance(
            _skill('a', 'OLD body'),
            relativePath: '.claude/skills/a/SKILL.md',
            sourceRef: 'old',
            runner: 'space',
          ),
        );
        Directory(
          p.join(target.path, '.claude', 'skills'),
        ).createSync(recursive: true);
        Link(
          p.join(target.path, '.claude', 'skills', 'a'),
        ).createSync(p.join(temp.path, 'extension', 'skills', 'a'));

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlay.path],
          targetRoot: target.path,
          sourceRef: 'testref',
        );

        expect(report.blocked.single.symlink, isTrue);
        expect(report.written, isEmpty);
        expect(report.updated, isEmpty);
        expect(
          outside.readAsStringSync(),
          contains('OLD body'),
          reason:
              'a stamped file behind a symlinked DIR is still outside the '
              'target root — the lib writes nothing there',
        );
      },
    );

    test(
      'a DANGLING symlink is BLOCKED too, not a crash — existsSync() is false '
      'through a broken link, so a naive write would follow it and throw',
      () async {
        _write(overlay, ['.claude', 'skills', 'a', 'SKILL.md'], _skill('a'));
        Link(p.join(target.path, '.claude', 'skills', 'a', 'SKILL.md'))
          ..parent.createSync(recursive: true)
          ..createSync(p.join(temp.path, 'nowhere', 'SKILL.md'));

        late final OverlayMaterializeReport report;
        expect(
          () async => report = await const OverlayMaterializer().materialize(
            overlayRoots: [overlay.path],
            targetRoot: target.path,
            sourceRef: 'testref',
          ),
          returnsNormally,
        );

        await pumpEventQueue();
        expect(report.blocked.single.symlink, isTrue);
      },
    );

    test('a vended file that cannot carry a stamp THROWS — never installed '
        'indistinguishably from a hand-authored one', () {
      _write(overlay, ['.claude', 'notes.txt'], 'plain text');

      expect(
        () => const OverlayMaterializer().materializeSync(
          overlayRoots: [overlay.path],
          targetRoot: target.path,
          sourceRef: 'testref',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no provenance syntax'),
          ),
        ),
      );
    });
  });

  group('OverlayMaterializer — render + refuse', () {
    test('declared args are substituted into every copied file', () async {
      _write(overlay, [
        '.claude',
        'skills',
        'foo',
        'SKILL.md',
      ], _skill('foo', 'run {{runner}} search in {{gridHome}}'));

      await const OverlayMaterializer().materialize(
        overlayRoots: [overlay.path],
        targetRoot: target.path,
        sourceRef: 'testref',
        args: const {'runner': 'space', 'gridHome': '/grid/home'},
      );

      expect(
        File(
          p.join(target.path, '.claude', 'skills', 'foo', 'SKILL.md'),
        ).readAsStringSync(),
        contains('run space search in /grid/home'),
      );
    });

    test(
      'a file left with an UNBOUND hole is REFUSED — never written (a half-bound '
      'skill would read as literal text to the agent)',
      () async {
        _write(overlay, [
          '.claude',
          'skills',
          'foo',
          'SKILL.md',
        ], _skill('foo', 'run {{runner}} in {{gridHome}}'));

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlay.path],
          targetRoot: target.path,
          sourceRef: 'testref',
          args: const {'runner': 'space'},
        );

        expect(
          File(
            p.join(target.path, '.claude', 'skills', 'foo', 'SKILL.md'),
          ).existsSync(),
          isFalse,
          reason: 'a half-bound asset is installed NOWHERE',
        );
        expect(report.written, isEmpty);
        final refused = report.refused.single;
        expect(
          refused.relativePath,
          p.join('.claude', 'skills', 'foo', 'SKILL.md'),
        );
        expect(refused.holes, ['{{gridHome}}']);
        expect(refused.reason, contains('{{gridHome}}'));
        expect(
          report.installedSkillIdsUnder(kClaudeSkillsSubtree),
          isEmpty,
          reason: 'a refused skill must never be named to an agent',
        );
      },
    );
  });

  group('OverlayMaterializeReport — the wire\'s git fence is LOUD', () {
    test(
      'writtenAssetDirsUnder names the asset dirs the wire must fence',
      () async {
        _write(overlay, ['.claude', 'skills', 'a', 'SKILL.md'], _skill('a'));
        _write(overlay, ['.claude', 'skills', 'b', 'SKILL.md'], _skill('b'));

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlay.path],
          targetRoot: target.path,
          sourceRef: 'testref',
        );

        expect(report.writtenAssetDirsUnder(kClaudeSkillsSubtree), [
          p.join('.claude', 'skills', 'a'),
          p.join('.claude', 'skills', 'b'),
        ]);
      },
    );

    test(
      'a file loose directly under the SCOPED subtree THROWS — the wire cannot '
      'git-fence it per-asset-dir without ignoring repo-owned territory '
      '(A23(6)/A23(7), re-homed from the walk to the caller it protects)',
      () async {
        _write(overlay, ['.claude', 'skills', 'stray.md'], _skill('stray'));

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlay.path],
          targetRoot: target.path,
          sourceRef: 'testref',
        );

        expect(
          () => report.writtenAssetDirsUnder(kClaudeSkillsSubtree),
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
      _write(a, ['.claude', 'skills', 'alpha', 'SKILL.md'], _skill('alpha'));
      final b = Directory(p.join(temp.path, 'b'));
      _write(b, ['.claude', 'skills', 'beta', 'SKILL.md'], _skill('beta'));

      final report = await const OverlayMaterializer().materialize(
        overlayRoots: [a.path, b.path],
        targetRoot: target.path,
        sourceRef: 'testref',
      );

      expect(report.written, hasLength(2));
      expect(report.installedSkillIdsUnder(kClaudeSkillsSubtree), [
        'alpha',
        'beta',
      ]);
    });

    test(
      'two roots offering the SAME path — the EARLIER tree position wins, and '
      'the loser is not even considered',
      () async {
        final a = Directory(p.join(temp.path, 'a'));
        _write(a, [
          '.claude',
          'skills',
          'discover',
          'SKILL.md',
        ], _skill('discover', 'root A wins'));
        final b = Directory(p.join(temp.path, 'b'));
        _write(b, [
          '.claude',
          'skills',
          'discover',
          'SKILL.md',
        ], _skill('discover', 'root B loses'));

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [a.path, b.path],
          targetRoot: target.path,
          sourceRef: 'testref',
        );

        expect(
          File(
            p.join(target.path, '.claude', 'skills', 'discover', 'SKILL.md'),
          ).readAsStringSync(),
          contains('root A wins'),
        );
        expect(report.written.single.sourceRoot, a.path);
      },
    );
  });

  group('OverlayMaterializer — the live grid_assets station_overlay', () {
    test(
      'the REAL extension/station_overlay round-trips the vended discover skill '
      'at its ROOT-RELATIVE path: a frontmatter-led SKILL.md with no {{ residue',
      () async {
        final overlayRoot = p.join(_extensionDir(), 'station_overlay');

        final report = await const OverlayMaterializer().materialize(
          overlayRoots: [overlayRoot],
          targetRoot: target.path,
          sourceRef: 'testref',
          args: const {'runner': 'space'},
        );

        final installed = File(
          p.join(target.path, '.claude', 'skills', 'discover', 'SKILL.md'),
        );
        expect(installed.existsSync(), isTrue);
        final body = installed.readAsStringSync();
        expect(body, isNot(contains('--ephemeral')));
        expect(body, isNot(contains('--persistent')));
        expect(body, contains('type=link'));
        expect(body, contains('grid.link.from=<blocked bead id>'));
        expect(body, contains('grid.link.to=<blocker bead id>'));
        expect(body, contains('grid.link.type=blocks'));
        expect(body, contains('StationJoinBridge._applyCrossLinks'));
        expect(body, contains('applyBlockGuard'));
        expect(
          body,
          isNot(
            contains('bd dep add <id> external:<project>:<capability> stores'),
          ),
        );
        expect(body, contains('search --json "<new bead id>"'));
        expect(body, contains('Never use `bd show`'));
        expect(body, startsWith('---\n'));
        expect(body, contains('space search --json'));
        expect(body, isNot(contains('{{')));
        expect(
          report.installedSkillIdsUnder(kClaudeSkillsSubtree),
          contains('discover'),
        );
        expect(report.refused, isEmpty);
        expect(report.blocked, isEmpty);
      },
    );

    test(
      'the source has NO CLI and NO git dependency (UI-drivable — the Command is '
      'the only CLI seam, and the wire owns git exclusion)',
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
        expect(source, isNot(contains('Process.')));
      },
    );
  });
}
