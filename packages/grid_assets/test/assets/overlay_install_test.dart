// The OPERATOR leg — non-prescriptive root discovery, the non-destructive
// install, and the PURE diff renderer under `<cli> install`.
// Offline: temp dirs, a hand-written package config, no CLI, no git.
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

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('grid-install-'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('OverlayInstallService — the operator expand', () {
    test('expands skills AND agents onto the target, rendering the args',
        () async {
      final overlay = Directory(p.join(temp.path, 'pack'));
      _write(
          overlay, ['skills', 'discover', 'SKILL.md'], 'run {{runner}} search');
      _write(overlay, ['agents', 'governor', 'AGENT.md'], 'the {{runner}} operator');
      final target = p.join(temp.path, '.claude');

      final report = await const OverlayInstallService().install(
        overlayRoots: [overlay.path],
        targetRoot: target,
        args: {'runner': 'space'},
      );

      expect(report.written.map((f) => f.relativePath), [
        p.join('skills', 'discover', 'SKILL.md'),
        p.join('agents', 'governor', 'AGENT.md'),
      ]);
      expect(
        File(p.join(target, 'skills', 'discover', 'SKILL.md'))
            .readAsStringSync(),
        'run space search',
      );
      expect(
        File(p.join(target, 'agents', 'governor', 'AGENT.md'))
            .readAsStringSync(),
        'the space operator',
      );
      expect(report.exitCode, 0);
    });

    test(
        'NON-DESTRUCTIVE — a pre-existing target file is never overwritten, '
        'and is reported skipped', () async {
      final overlay = Directory(p.join(temp.path, 'pack'));
      _write(overlay, ['skills', 'discover', 'SKILL.md'], 'the vended one');
      final target = Directory(p.join(temp.path, '.claude'));
      _write(target, ['skills', 'discover', 'SKILL.md'], "the operator's own");

      final report = await const OverlayInstallService()
          .install(overlayRoots: [overlay.path], targetRoot: target.path);

      expect(report.written, isEmpty);
      expect(
        report.skipped.single.relativePath,
        p.join('skills', 'discover', 'SKILL.md'),
      );
      expect(
        File(p.join(target.path, 'skills', 'discover', 'SKILL.md'))
            .readAsStringSync(),
        "the operator's own",
        reason: 'never trample what this domain did not write',
      );
      expect(report.exitCode, 0, reason: 'a skip is not a failure');
    });

    test('union by tree position — the FIRST root to offer a path wins',
        () async {
      final first = Directory(p.join(temp.path, 'first'));
      final second = Directory(p.join(temp.path, 'second'));
      _write(first, ['skills', 'discover', 'SKILL.md'], 'from first');
      _write(second, ['skills', 'discover', 'SKILL.md'], 'from second');
      _write(second, ['skills', 'other', 'SKILL.md'], 'only in second');
      final target = p.join(temp.path, '.claude');

      final report = await const OverlayInstallService().install(
        overlayRoots: [first.path, second.path],
        targetRoot: target,
      );

      expect(
        File(p.join(target, 'skills', 'discover', 'SKILL.md'))
            .readAsStringSync(),
        'from first',
      );
      expect(report.installedSkillIds, ['discover', 'other']);
    });

    test('an UNBOUND hole is REFUSED — never written — and exits non-zero',
        () async {
      final overlay = Directory(p.join(temp.path, 'pack'));
      _write(overlay, ['skills', 'ops', 'SKILL.md'], 'boot {{gridHome}}');
      final target = p.join(temp.path, '.claude');

      final report = await const OverlayInstallService().install(
        overlayRoots: [overlay.path],
        targetRoot: target,
        args: {'runner': 'space'},
      );

      expect(report.written, isEmpty);
      expect(report.refused.single.holes, ['{{gridHome}}']);
      expect(
        File(p.join(target, 'skills', 'ops', 'SKILL.md')).existsSync(),
        isFalse,
      );
      expect(report.exitCode, 1, reason: 'a half-bound asset is LOUD');
    });

    test(
        'installing twice is a clean ROUND-TRIP — the second run writes '
        'nothing, skips everything, exits 0', () async {
      final overlay = Directory(p.join(temp.path, 'pack'));
      _write(overlay, ['skills', 'discover', 'SKILL.md'], 'run {{runner}}');
      final target = p.join(temp.path, '.claude');
      const service = OverlayInstallService();
      const args = {'runner': 'space'};

      final first = await service.install(
          overlayRoots: [overlay.path], targetRoot: target, args: args);
      final second = await service.install(
          overlayRoots: [overlay.path], targetRoot: target, args: args);

      expect(first.written, hasLength(1));
      expect(second.written, isEmpty);
      expect(second.skipped, hasLength(1));
      expect(second.exitCode, 0);
      expect(
        File(p.join(target, 'skills', 'discover', 'SKILL.md'))
            .readAsStringSync(),
        'run space',
      );
    });
  });

  group('renderInstallReport — the diff the operator commits', () {
    Future<OverlayInstallReport> report() async {
      final overlay = Directory(p.join(temp.path, 'pack'));
      _write(overlay, ['skills', 'discover', 'SKILL.md'], 'run {{runner}}');
      _write(overlay, ['skills', 'ops', 'SKILL.md'], 'boot {{gridHome}}');
      final target = Directory(p.join(temp.path, '.claude'));
      _write(target, ['skills', 'mine', 'SKILL.md'], 'the operator wrote this');
      _write(overlay, ['skills', 'mine', 'SKILL.md'], 'the vended one');
      return const OverlayInstallService().install(
        overlayRoots: [overlay.path],
        targetRoot: target.path,
        args: {'runner': 'space'},
      );
    }

    test(
        'the DEFAULT shows a new-file diff, names the pre-existing skips, and '
        'says NOTHING was committed', () async {
      final text = renderInstallReport(await report());

      expect(text, contains('--- /dev/null'));
      expect(
        text,
        contains(
          '+++ ${p.join(temp.path, '.claude', 'skills', 'discover', 'SKILL.md')}',
        ),
      );
      expect(text, contains('+run space'));
      expect(text, contains('skipped (already present — never overwritten): '));
      expect(text, contains(p.join('skills', 'mine', 'SKILL.md')));
      expect(text, contains('REFUSED '));
      expect(text, contains('{{gridHome}}'));
      expect(text, contains('1 written, 1 skipped, 1 refused'));
      expect(text, contains('NOTHING was committed'));
    });

    test(
        '--no-diff prints no diff body and IGNORES pre-existing files — their '
        'paths never appear; a REFUSAL still does', () async {
      final text = renderInstallReport(await report(), diff: false);

      expect(text, isNot(contains('--- /dev/null')));
      expect(text, isNot(contains('+run space')));
      expect(text, isNot(contains(p.join('skills', 'mine', 'SKILL.md'))));
      expect(text, contains('installed '));
      expect(text, contains('REFUSED '));
      expect(text, contains('NOTHING was committed'));
    });
  });

  group('resolveStationOverlayRoots — NON-PRESCRIPTIVE discovery', () {
    test('a grid home with no package config throws LOUD', () async {
      await expectLater(
        resolveStationOverlayRoots(gridHome: temp.path),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('package_config.json'),
        )),
      );
    });

    test(
        'discovers every package that ships the asset manifest AND a '
        'station_overlay — sorted by package name, no pack hardcoded', () async {
      final alpha = Directory(p.join(temp.path, 'packs', 'alpha_assets'));
      final beta = Directory(p.join(temp.path, 'packs', 'beta_assets'));
      // Both vend the manifest; only alpha ships an overlay.
      _write(alpha, ['extension', 'mcp', 'config.yaml'], 'name: alpha_assets\n');
      _write(
          alpha, ['extension', 'station_overlay', 'skills', 'a', 'SKILL.md'], 'a');
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

      expect(roots, [p.join(alpha.path, 'extension', 'station_overlay')],
          reason: 'beta vends no overlay, so it contributes no root');
      expect(
        Directory(p.join(temp.path, '.dart_tool', 'extension_discovery'))
            .existsSync(),
        isFalse,
        reason: 'discovery leaves no cache artifact in the operator checkout',
      );
    });
  });

  group("the ROUND-TRIP — grid_assets' REAL vended overlay", () {
    test('install lands every vended skill with NO template residue', () async {
      final target = p.join(temp.path, '.claude');

      final report = await const OverlayInstallService().install(
        overlayRoots: [p.join(_extensionDir(), 'station_overlay')],
        targetRoot: target,
        args: {'runner': 'space', 'gridHome': '/grid/home'},
      );

      expect(report.refused, isEmpty,
          reason: 'every vended file binds against runner + gridHome');
      expect(report.installedSkillIds, kVendedSkills);
      for (final id in kVendedSkills) {
        final skill = File(p.join(target, 'skills', id, 'SKILL.md'));
        expect(skill.existsSync(), isTrue, reason: '$id is installed');
        expect(skill.readAsStringSync(), isNot(contains('{{')),
            reason: '$id has no template residue');
      }
    });
  });
}
