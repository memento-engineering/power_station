// The OPERATOR leg — non-prescriptive root discovery, the install onto a repo
// ROOT, the --check drift mode, and the PURE diff renderer under
// `<cli> assets install`.
// Offline: temp dirs, a hand-written package config, no CLI, no git.
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// This package's `extension/` dir, resolved the CWD-INDEPENDENT way (the
/// loader's own package-config resolution). Never a cwd walk: `Directory.current`
/// is process-global and the suites run concurrently, so a sibling suite that
/// chdirs to prove cwd-independence would race a walk done here.
String _extensionDir() => PackagedAssetLoader().root;

/// Writes [contents] at [segments] under [root] (creating parents).
File _write(Directory root, List<String> segments, String contents) =>
    File(p.join(root.path, p.joinAll(segments)))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);

/// A stampable (frontmatter-led) SKILL.md body.
String _skill(String name, [String body = 'body']) =>
    '---\nname: $name\n---\n$body\n';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('grid-install-'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('OverlayInstallService — the operator expand onto a repo ROOT', () {
    test(
      "PATH-PRESERVING: the overlay's own .claude/ tree lands under the root — "
      'skills, the agent def, and the harness settings alike',
      () async {
        final overlay = Directory(p.join(temp.path, 'pack'));
        _write(overlay, [
          '.claude',
          'skills',
          'discover',
          'SKILL.md',
        ], _skill('discover', 'run {{runner}} search'));
        _write(overlay, [
          '.claude',
          'agents',
          'governor.md',
        ], _skill('governor', 'the {{runner}} operator'));

        final report = await const OverlayInstallService().install(
          overlayRoots: [overlay.path],
          targetRoot: temp.path,
          sourceRef: 'testref',
          args: {'runner': 'space'},
        );

        expect(report.written.map((f) => f.relativePath), [
          p.join('.claude', 'agents', 'governor.md'),
          p.join('.claude', 'skills', 'discover', 'SKILL.md'),
        ]);
        expect(
          File(
            p.join(temp.path, '.claude', 'skills', 'discover', 'SKILL.md'),
          ).readAsStringSync(),
          contains('run space search'),
        );
        expect(
          File(
            p.join(temp.path, '.claude', 'agents', 'governor.md'),
          ).readAsStringSync(),
          contains('the space operator'),
        );
        expect(report.exitCode, 0);
      },
    );

    test(
      'a HAND-AUTHORED file (no provenance header) is BLOCKED — never '
      'overwritten — and exits non-zero so the operator resolves it',
      () async {
        final overlay = Directory(p.join(temp.path, 'pack'));
        _write(overlay, [
          '.claude',
          'skills',
          'discover',
          'SKILL.md',
        ], _skill('discover', 'the vended one'));
        _write(Directory(temp.path), [
          '.claude',
          'skills',
          'discover',
          'SKILL.md',
        ], "the operator's own");

        final report = await const OverlayInstallService().install(
          overlayRoots: [overlay.path],
          targetRoot: temp.path,
          sourceRef: 'testref',
        );

        expect(report.written, isEmpty);
        expect(
          report.blocked.single.relativePath,
          p.join('.claude', 'skills', 'discover', 'SKILL.md'),
        );
        expect(
          File(
            p.join(temp.path, '.claude', 'skills', 'discover', 'SKILL.md'),
          ).readAsStringSync(),
          "the operator's own",
          reason: 'never trample what this domain did not generate',
        );
        expect(report.exitCode, 1, reason: 'a shadowed vended file is LOUD');
      },
    );

    test(
      'union by tree position — the FIRST root to offer a path wins',
      () async {
        final first = Directory(p.join(temp.path, 'first'));
        final second = Directory(p.join(temp.path, 'second'));
        _write(first, [
          '.claude',
          'skills',
          'discover',
          'SKILL.md',
        ], _skill('discover', 'from first'));
        _write(second, [
          '.claude',
          'skills',
          'discover',
          'SKILL.md',
        ], _skill('discover', 'from second'));
        _write(second, [
          '.claude',
          'skills',
          'other',
          'SKILL.md',
        ], _skill('other', 'only in second'));

        final report = await const OverlayInstallService().install(
          overlayRoots: [first.path, second.path],
          targetRoot: temp.path,
          sourceRef: 'testref',
        );

        expect(
          File(
            p.join(temp.path, '.claude', 'skills', 'discover', 'SKILL.md'),
          ).readAsStringSync(),
          contains('from first'),
        );
        expect(report.installedSkillIds, ['discover', 'other']);
      },
    );

    test(
      'an UNBOUND hole is REFUSED — never written — and exits non-zero',
      () async {
        final overlay = Directory(p.join(temp.path, 'pack'));
        _write(overlay, [
          '.claude',
          'skills',
          'ops',
          'SKILL.md',
        ], _skill('ops', 'boot {{gridHome}}'));

        final report = await const OverlayInstallService().install(
          overlayRoots: [overlay.path],
          targetRoot: temp.path,
          sourceRef: 'testref',
          args: {'runner': 'space'},
        );

        expect(report.written, isEmpty);
        expect(report.refused.single.holes, ['{{gridHome}}']);
        expect(
          File(
            p.join(temp.path, '.claude', 'skills', 'ops', 'SKILL.md'),
          ).existsSync(),
          isFalse,
        );
        expect(report.exitCode, 1, reason: 'a half-bound asset is LOUD');
      },
    );

    test(
      'installing twice is a clean ROUND-TRIP — the second run writes nothing, '
      'reports everything current, exits 0',
      () async {
        final overlay = Directory(p.join(temp.path, 'pack'));
        _write(overlay, [
          '.claude',
          'skills',
          'discover',
          'SKILL.md',
        ], _skill('discover', 'run {{runner}}'));
        const service = OverlayInstallService();
        const args = {'runner': 'space'};

        final first = await service.install(
          overlayRoots: [overlay.path],
          targetRoot: temp.path,
          sourceRef: 'testref',
          args: args,
        );
        final second = await service.install(
          overlayRoots: [overlay.path],
          targetRoot: temp.path,
          sourceRef: 'testref',
          args: args,
        );

        expect(first.written, hasLength(1));
        expect(second.written, isEmpty);
        expect(second.unchanged, hasLength(1));
        expect(second.exitCode, 0);
      },
    );
  });

  group('--check — the drift enforcement that lets the tree be COMMITTED', () {
    Directory pack() {
      final overlay = Directory(p.join(temp.path, 'pack'));
      _write(overlay, [
        '.claude',
        'skills',
        'discover',
        'SKILL.md',
      ], _skill('discover', 'run {{runner}}'));
      return overlay;
    }

    Future<OverlayInstallReport> run(Directory overlay, {bool check = false}) =>
        const OverlayInstallService().install(
          overlayRoots: [overlay.path],
          targetRoot: temp.path,
          sourceRef: 'testref',
          args: const {'runner': 'space'},
          check: check,
        );

    test(
      'a MISSING file fails the check, and the check writes NOTHING',
      () async {
        final overlay = pack();

        final report = await run(overlay, check: true);

        expect(report.dryRun, isTrue);
        expect(report.written, hasLength(1));
        expect(report.exitCode, 1);
        expect(
          File(
            p.join(temp.path, '.claude', 'skills', 'discover', 'SKILL.md'),
          ).existsSync(),
          isFalse,
          reason: '--check is a PLAN — it writes nothing',
        );
      },
    );

    test('a clean install makes the check PASS', () async {
      final overlay = pack();
      await run(overlay);

      final report = await run(overlay, check: true);

      expect(report.exitCode, 0);
      expect(report.unchanged, hasLength(1));
    });

    test('editing an installed file makes the check FAIL as DRIFTED', () async {
      final overlay = pack();
      await run(overlay);
      final installed = File(
        p.join(temp.path, '.claude', 'skills', 'discover', 'SKILL.md'),
      );
      installed.writeAsStringSync(
        '${installed.readAsStringSync()}\nhand edit\n',
      );

      final report = await run(overlay, check: true);

      expect(report.exitCode, 1);
      expect(report.updated, hasLength(1));
      expect(
        installed.readAsStringSync(),
        contains('hand edit'),
        reason: 'the check reported the drift, it did not repair it',
      );
    });
  });

  group('renderInstallReport — the diff the operator commits', () {
    Future<OverlayInstallReport> report({bool check = false}) async {
      final overlay = Directory(p.join(temp.path, 'pack'));
      _write(overlay, [
        '.claude',
        'skills',
        'discover',
        'SKILL.md',
      ], _skill('discover', 'run {{runner}}'));
      _write(overlay, [
        '.claude',
        'skills',
        'ops',
        'SKILL.md',
      ], _skill('ops', 'boot {{gridHome}}'));
      _write(overlay, [
        '.claude',
        'skills',
        'mine',
        'SKILL.md',
      ], _skill('mine', 'the vended one'));
      _write(Directory(temp.path), [
        '.claude',
        'skills',
        'mine',
        'SKILL.md',
      ], 'the operator wrote this');
      return const OverlayInstallService().install(
        overlayRoots: [overlay.path],
        targetRoot: temp.path,
        sourceRef: 'testref',
        args: {'runner': 'space'},
        check: check,
      );
    }

    test(
      'the DEFAULT shows a new-file diff, names the BLOCKED and REFUSED files, '
      'and says NOTHING was committed',
      () async {
        final text = renderInstallReport(await report());

        expect(text, contains('--- /dev/null'));
        expect(
          text,
          contains(
            '+++ ${p.join(temp.path, '.claude', 'skills', 'discover', 'SKILL.md')}',
          ),
        );
        expect(text, contains('+run space'));
        expect(text, contains('BLOCKED '));
        expect(text, contains(p.join('.claude', 'skills', 'mine', 'SKILL.md')));
        expect(text, contains('REFUSED '));
        expect(text, contains('{{gridHome}}'));
        expect(
          text,
          contains('1 installed, 0 updated, 0 current, 1 blocked, 1 refused'),
        );
        expect(text, contains('NOTHING was committed'));
      },
    );

    test(
      'a --check run prints the same lines in the CONDITIONAL — MISSING, not '
      'installed — and says nothing was WRITTEN',
      () async {
        final text = renderInstallReport(await report(check: true));

        expect(text, contains('MISSING '));
        expect(
          const LineSplitter().convert(text),
          isNot(contains(startsWith('installed '))),
          reason: 'a --check installed NOTHING, so no line may claim it did',
        );
        expect(text, contains('BLOCKED '));
        expect(text, contains('NOTHING was written'));
      },
    );

    test(
      '--no-diff prints no diff body; a BLOCKED and a REFUSAL still do',
      () async {
        final text = renderInstallReport(await report(), diff: false);

        expect(text, isNot(contains('--- /dev/null')));
        expect(text, isNot(contains('+run space')));
        expect(text, contains('installed '));
        expect(text, contains('BLOCKED '));
        expect(text, contains('REFUSED '));
      },
    );
  });

  group('resolveStationOverlayRoots — NON-PRESCRIPTIVE discovery', () {
    test('a grid home with no package config throws LOUD', () async {
      await expectLater(
        resolveStationOverlayRoots(gridHome: temp.path),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('package_config.json'),
          ),
        ),
      );
    });

    test('discovers every package that ships the asset manifest AND a '
        'station_overlay — sorted by package name, no pack hardcoded', () async {
      final alpha = Directory(p.join(temp.path, 'packs', 'alpha_assets'));
      final beta = Directory(p.join(temp.path, 'packs', 'beta_assets'));
      // Both vend the manifest; only alpha ships an overlay.
      _write(alpha, [
        'extension',
        'mcp',
        'config.yaml',
      ], 'name: alpha_assets\n');
      _write(alpha, [
        'extension',
        'station_overlay',
        '.claude',
        'skills',
        'a',
        'SKILL.md',
      ], _skill('a'));
      _write(beta, ['extension', 'mcp', 'config.yaml'], 'name: beta_assets\n');
      _write(
        Directory(temp.path),
        ['.dart_tool', 'package_config.json'],
        '{"configVersion":2,"packages":['
        '{"name":"beta_assets","rootUri":"../packs/beta_assets","packageUri":"lib/"},'
        '{"name":"alpha_assets","rootUri":"../packs/alpha_assets","packageUri":"lib/"}'
        ']}',
      );

      final roots = await resolveStationOverlayRoots(gridHome: temp.path);

      expect(roots, [
        p.join(alpha.path, 'extension', 'station_overlay'),
      ], reason: 'beta vends no overlay, so it contributes no root');
      expect(
        Directory(
          p.join(temp.path, '.dart_tool', 'extension_discovery'),
        ).existsSync(),
        isFalse,
        reason: 'discovery leaves no cache artifact in the operator checkout',
      );
    });
  });

  group("the ROUND-TRIP — grid_assets' REAL vended overlay", () {
    test(
      'install lands every vended skill AND the COMPLETE operator asset set — '
      'the governor agent-def and the harness settings — with no residue',
      () async {
        final report = await const OverlayInstallService().install(
          overlayRoots: [p.join(_extensionDir(), 'station_overlay')],
          targetRoot: temp.path,
          sourceRef: 'testref',
          args: {'runner': 'space', 'gridHome': '/grid/home'},
        );

        expect(
          report.refused,
          isEmpty,
          reason: 'every vended file binds against runner + gridHome',
        );
        expect(report.blocked, isEmpty);
        expect(report.installedSkillIds, vendedSkillIds);
        for (final id in vendedSkillIds) {
          final skill = File(
            p.join(temp.path, '.claude', 'skills', id, 'SKILL.md'),
          );
          expect(skill.existsSync(), isTrue, reason: '$id is installed');
          expect(
            skill.readAsStringSync(),
            isNot(contains('{{')),
            reason: '$id has no template residue',
          );
        }

        final governor = File(
          p.join(temp.path, '.claude', 'agents', 'governor.md'),
        );
        expect(governor.readAsStringSync(), contains('name: governor'));
        expect(hasProvenance(governor.readAsStringSync()), isTrue);

        final settings = File(p.join(temp.path, '.claude', 'settings.json'));
        expect(settings.readAsStringSync(), contains('bd prime --hook-json'));
        expect(
          jsonDecode(settings.readAsStringSync()),
          isA<Map<String, dynamic>>().having(
            (m) => m[r'$generated'],
            r'$generated',
            contains('testref'),
          ),
          reason: 'the stamped settings file is still valid JSON',
        );
      },
    );

    test(
      'assets install materializes the stamped approve verb in both skills',
      () async {
        final report = await const OverlayInstallService().install(
          overlayRoots: [p.join(_extensionDir(), 'station_overlay')],
          targetRoot: temp.path,
          sourceRef: 'testref',
          args: {'runner': 'space', 'gridHome': '/grid/home'},
        );

        expect(report.refused, isEmpty);
        expect(report.blocked, isEmpty);
        for (final id in const ['discover', 'intake-refinement']) {
          final body = File(
            p.join(temp.path, '.claude', 'skills', id, 'SKILL.md'),
          ).readAsStringSync();
          expect(
            body,
            contains('grid.approved'),
            reason: '$id teaches approval',
          );
          expect(body, isNot(contains('--defer')), reason: '$id retired defer');
          expect(
            body,
            contains('space approve --actor'),
            reason: '$id installs the approve verb, not a hand-added label',
          );
          expect(
            body,
            contains('grid.approved_at'),
            reason: '$id installs the stamp keys',
          );
          expect(body, isNot(contains('--add-label ${'grid'}.approved')));
        }
      },
    );

    test(
      'assets install materializes the intake-refinement refiner corpus onto '
      'a target root — the filing exit check renders with the station verb',
      () async {
        final report = await const OverlayInstallService().install(
          overlayRoots: [p.join(_extensionDir(), 'station_overlay')],
          targetRoot: temp.path,
          sourceRef: 'testref',
          args: {'runner': 'space', 'gridHome': '/grid/home'},
        );

        expect(report.refused, isEmpty);
        expect(report.blocked, isEmpty);
        final installed = File(
          p.join(
            temp.path,
            '.claude',
            'skills',
            'intake-refinement',
            'SKILL.md',
          ),
        );
        expect(
          installed.existsSync(),
          isTrue,
          reason: 'the refiner corpus lands on the operator root',
        );
        final body = installed.readAsStringSync();
        expect(hasProvenance(body), isTrue);
        expect(body, isNot(contains('{{')));
        expect(body, contains('space filing --json "<bead>"'));
        expect(body, contains('space search --json "<token>"'));
        expect(body, contains('space link <blocked bead> --blocked-by'));
        expect(body, isNot(contains('mountEligibilityFindings')));
      },
    );
  });
}
