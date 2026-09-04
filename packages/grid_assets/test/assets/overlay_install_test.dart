// The OPERATOR leg — one resolution written onto a repo ROOT, the five-way
// `--check` classification, and the PURE diff renderer under
// `<cli> assets install`. Offline: temp dirs, declared fixtures, no CLI, no git.
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_assets/station_asset_registry.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/asset_resolution_fixture.dart';

/// This package's `extension/` dir, resolved the CWD-INDEPENDENT way (the
/// loader's own package-config resolution). Never a cwd walk: `Directory.current`
/// is process-global and the suites run concurrently, so a sibling suite that
/// chdirs to prove cwd-independence would race a walk done here.
String _extensionDir() => PackagedAssetLoader().root;

/// The LIVE station registry resolved against this checkout.
GridAssetResolution _liveResolution({Map<String, String> args = const {}}) {
  final packageRoot = p.dirname(_extensionDir());
  return resolveGridAssets(
    registry: GeneratedGridAssetRegistrant.registry,
    snapshot: SubstationFactsSnapshot(<SubstationKey, SubstationFacts>{
      kFixtureSubstation: SubstationFacts(
        root: packageRoot,
        dartPackages: const <String>['grid_assets', 'grid_sdk'],
        packageRoots: <String, String>{'grid_assets': packageRoot},
      ),
    }),
    substation: kFixtureSubstation,
    renderArguments: args,
  );
}

/// Writes [contents] at [segments] under [root] (creating parents).
File _write(Directory root, List<String> segments, String contents) =>
    File(p.join(root.path, p.joinAll(segments)))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);

/// Every file under [root], root-relative and sorted — what actually landed.
List<String> _tree(Directory root) =>
    root
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .map((file) => p.relative(file.path, from: root.path))
        .toList()
      ..sort();

void main() {
  late Directory temp;
  late Directory fixtureRoot;
  late Directory checkout;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('grid-install-');
    fixtureRoot = Directory(p.join(temp.path, 'fixture'))..createSync();
    checkout = Directory(p.join(temp.path, 'checkout'))..createSync();
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  TestAssetResolutionFixture fixture({
    List<GridAssetDefinition>? assets,
    Map<String, String> bodies = const <String, String>{},
    Iterable<String> extraPackages = const <String>[],
  }) => TestAssetResolutionFixture(
    root: fixtureRoot,
    assets:
        assets ??
        <GridAssetDefinition>[fixtureSkill('discover'), fixtureSkill('mine')],
    bodies: bodies,
    extraPackages: extraPackages,
  );

  group('OverlayInstallService — the operator write onto a repo ROOT', () {
    test('each selected artifact lands at its declared target under the root — '
        'skills and the loose harness settings alike', () async {
      final f = fixture(
        assets: <GridAssetDefinition>[
          fixtureSkill('discover'),
          fixtureSettings('harness'),
        ],
        bodies: <String, String>{
          'extension/station_overlay/claude/skills/discover/SKILL.md':
              fixtureSkillBody('discover', 'run {{runner}} search'),
          'extension/station_overlay/claude/settings.json':
              '{\n  "runner": "{{runner}}"\n}\n',
        },
      );

      final report = await const OverlayInstallService().install(
        resolution: f.resolution(renderArguments: const {'runner': 'space'}),
        targetRoot: checkout.path,
        sourceRef: 'testref',
      );

      expect(report.written.map((file) => file.relativePath), [
        p.join('.claude', 'skills', 'discover', 'SKILL.md'),
        p.join('.agents', 'skills', 'discover', 'SKILL.md'),
        p.join('.claude', 'settings.json'),
      ]);
      expect(
        File(
          p.join(checkout.path, '.claude', 'skills', 'discover', 'SKILL.md'),
        ).readAsStringSync(),
        contains('run space search'),
      );
      expect(
        File(
          p.join(checkout.path, '.claude', 'settings.json'),
        ).readAsStringSync(),
        contains('"runner": "space"'),
      );
      expect(report.exitCode, 0);
    });

    test(
      'a HAND-AUTHORED file (no provenance header) is BLOCKED — never '
      'overwritten — and exits non-zero so the operator resolves it',
      () async {
        final f = fixture(
          assets: <GridAssetDefinition>[fixtureSkill('discover')],
        );
        _write(checkout, [
          '.claude',
          'skills',
          'discover',
          'SKILL.md',
        ], "the operator's own");

        final report = await const OverlayInstallService().install(
          resolution: f.resolution(),
          targetRoot: checkout.path,
          sourceRef: 'testref',
        );

        expect(
          report.blocked.single.relativePath,
          p.join('.claude', 'skills', 'discover', 'SKILL.md'),
        );
        expect(
          File(
            p.join(checkout.path, '.claude', 'skills', 'discover', 'SKILL.md'),
          ).readAsStringSync(),
          "the operator's own",
          reason: 'never trample what this domain did not generate',
        );
        expect(report.exitCode, 1, reason: 'a shadowed vended file is LOUD');
      },
    );

    test(
      'an UNBOUND hole is REFUSED — never written — and exits non-zero',
      () async {
        final f = fixture(
          assets: <GridAssetDefinition>[fixtureSkill('ops')],
          bodies: <String, String>{
            'extension/station_overlay/claude/skills/ops/SKILL.md':
                fixtureSkillBody('ops', 'boot {{gridHome}}'),
          },
        );

        final report = await const OverlayInstallService().install(
          resolution: f.resolution(renderArguments: const {'runner': 'space'}),
          targetRoot: checkout.path,
          sourceRef: 'testref',
        );

        expect(report.refused.single.holes, ['{{gridHome}}']);
        expect(
          File(
            p.join(checkout.path, '.claude', 'skills', 'ops', 'SKILL.md'),
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
        final f = fixture(
          assets: <GridAssetDefinition>[fixtureSkill('discover')],
        );
        const service = OverlayInstallService();

        final first = await service.install(
          resolution: f.resolution(),
          targetRoot: checkout.path,
          sourceRef: 'testref',
        );
        final second = await service.install(
          resolution: f.resolution(),
          targetRoot: checkout.path,
          sourceRef: 'testref',
        );

        expect(first.written, hasLength(2));
        expect(second.written, isEmpty);
        expect(second.unchanged, hasLength(2));
        expect(second.exitCode, 0);
      },
    );

    test(
      'checkout and worktree writers consume one identical resolution',
      () async {
        final worktree = Directory(p.join(temp.path, 'worktree'))..createSync();
        final f = fixture(
          assets: <GridAssetDefinition>[
            fixtureSkill('discover'),
            fixtureSkill('gated', selector: const RequiresPackage('grid_sdk')),
          ],
          extraPackages: const <String>['grid_sdk'],
        );
        // ONE value, handed to both writers — that is the whole claim.
        final resolution = f.resolution(
          renderArguments: const {'runner': 'space'},
        );

        final installed = await const OverlayInstallService().install(
          resolution: resolution,
          targetRoot: checkout.path,
          sourceRef: 'testref',
        );
        final materialized = const OverlayMaterializer().materializeSync(
          resolution: resolution,
          targetRoot: worktree.path,
          sourceRef: 'testref',
        );

        expect(
          installed.materialized.files.map((file) => file.relativePath),
          materialized.files.map((file) => file.relativePath),
          reason: 'the same resolution yields the same outcome paths',
        );
        expect(
          _tree(checkout),
          _tree(worktree),
          reason: 'and the same files on disk',
        );
        expect(_tree(checkout), [
          p.join('.agents', 'skills', 'discover', 'SKILL.md'),
          p.join('.agents', 'skills', 'gated', 'SKILL.md'),
          p.join('.claude', 'skills', 'discover', 'SKILL.md'),
          p.join('.claude', 'skills', 'gated', 'SKILL.md'),
        ]);
        // A stray beside a declared SOURCE reaches neither writer.
        expect(
          _tree(checkout).where((path) => path.contains('NOTES')),
          isEmpty,
        );
      },
    );
  });

  group('--check — the drift enforcement that lets the tree be COMMITTED', () {
    test('--check classifies IN SYNC, DRIFTED, HAND-EDITED, MISSING, and STALE '
        'without writing', () async {
      final f = fixture(
        assets: <GridAssetDefinition>[
          fixtureSkill('current'),
          fixtureSkill('drifted'),
          fixtureSkill('mine'),
          fixtureSkill('absent'),
        ],
      );
      const service = OverlayInstallService();
      const scoped = <String>[kClaudeSkillsSubtree];

      String stamped(String id, String body) => stampProvenance(
        fixtureSkillBody(id, body),
        relativePath: '.claude/skills/$id/SKILL.md',
        sourceRef: 'testref',
        runner: 'space',
      );

      // IN SYNC: generated here and identical.
      final current = _write(checkout, [
        '.claude',
        'skills',
        'current',
        'SKILL.md',
      ], stamped('current', 'body'));
      // DRIFTED: generated here, body changed.
      final drifted = _write(checkout, [
        '.claude',
        'skills',
        'drifted',
        'SKILL.md',
      ], stamped('drifted', 'HAND CHANGED'));
      // HAND-EDITED: never generated here.
      final mine = _write(checkout, [
        '.claude',
        'skills',
        'mine',
        'SKILL.md',
      ], 'the operator wrote this');
      // STALE: generated here, no longer selected.
      final withdrawn = _write(checkout, [
        '.claude',
        'skills',
        'withdrawn',
        'SKILL.md',
      ], stamped('withdrawn', 'body'));
      // …and `absent` is MISSING: selected, not on disk.
      final before = {
        for (final file in [current, drifted, mine, withdrawn])
          file.path: file.readAsStringSync(),
      };

      final report = await service.install(
        resolution: f.resolution(),
        targetRoot: checkout.path,
        sourceRef: 'testref',
        check: true,
      );

      expect(
        {
          for (final file in report.materialized.files.where(
            (file) => file.relativePath.startsWith('.claude'),
          )) //
            file.relativePath: file.checkClassification,
        },
        {
          p.join('.claude', 'skills', 'current', 'SKILL.md'):
              OverlayCheckClassification.inSync,
          p.join('.claude', 'skills', 'drifted', 'SKILL.md'):
              OverlayCheckClassification.drifted,
          p.join('.claude', 'skills', 'mine', 'SKILL.md'):
              OverlayCheckClassification.handEdited,
          p.join('.claude', 'skills', 'absent', 'SKILL.md'):
              OverlayCheckClassification.missing,
          p.join('.claude', 'skills', 'withdrawn', 'SKILL.md'):
              OverlayCheckClassification.stale,
        },
      );
      final text = renderInstallReport(report, diff: false);
      for (final label in const [
        'IN SYNC',
        'DRIFTED',
        'HAND-EDITED',
        'MISSING',
        'STALE',
      ]) {
        expect(text, contains('$label '), reason: '$label is NAMED');
      }
      expect(
        const LineSplitter().convert(text),
        isNot(contains(startsWith('installed '))),
        reason: 'a --check installed NOTHING, so no line may claim it did',
      );
      expect(text, contains('NOTHING was written'));
      expect(report.exitCode, 1);
      // Byte-for-byte: a check writes nothing and repairs nothing.
      for (final entry in before.entries) {
        expect(File(entry.key).readAsStringSync(), entry.value);
      }
      expect(
        File(
          p.join(checkout.path, '.claude', 'skills', 'absent', 'SKILL.md'),
        ).existsSync(),
        isFalse,
      );

      // The exit matrix: only an ALL-in-sync tree passes.
      final clean = TestAssetResolutionFixture(
        root: Directory(p.join(temp.path, 'clean-fixture'))..createSync(),
        assets: <GridAssetDefinition>[fixtureSkill('current')],
      );
      final cleanRoot = Directory(p.join(temp.path, 'clean'))..createSync();
      expect(
        (await service.install(
          resolution: clean.resolution(),
          targetRoot: cleanRoot.path,
          sourceRef: 'testref',
          check: true,
        )).exitCode,
        1,
        reason: 'a MISSING file fails the check',
      );
      await service.install(
        resolution: clean.resolution(),
        targetRoot: cleanRoot.path,
        sourceRef: 'testref',
      );
      final passing = await service.install(
        resolution: clean.resolution(),
        targetRoot: cleanRoot.path,
        sourceRef: 'testref',
        check: true,
      );
      expect(passing.exitCode, 0);
      expect(passing.unchanged, hasLength(2));
      expect(scoped, isNotEmpty);
    });

    test(
      'excluded, hand-edited, and stale paths remain non-destructive',
      () async {
        final f = fixture(
          assets: <GridAssetDefinition>[
            fixtureSkill('kept'),
            fixtureSkill('dropped'),
          ],
        );
        const service = OverlayInstallService();
        const dropped = AssetKey(
          package: kFixturePackage,
          kind: AssetKind.skill,
          id: 'dropped',
        );

        // Install everything, then EXCLUDE one asset: its installed files become
        // stale, and the operator's own file is untouched throughout.
        await service.install(
          resolution: f.resolution(),
          targetRoot: checkout.path,
          sourceRef: 'testref',
        );
        final handEdited = _write(checkout, [
          '.claude',
          'skills',
          'theirs',
          'SKILL.md',
        ], 'the operator wrote this');
        final staleFile = File(
          p.join(checkout.path, '.claude', 'skills', 'dropped', 'SKILL.md'),
        );
        final staleBytes = staleFile.readAsStringSync();

        final narrowed = f.resolution(
          rosterOverride: GridAssetRosterOverride(exclude: const [dropped]),
        );
        final checked = await service.install(
          resolution: narrowed,
          targetRoot: checkout.path,
          sourceRef: 'testref',
          check: true,
        );
        final installed = await service.install(
          resolution: narrowed,
          targetRoot: checkout.path,
          sourceRef: 'testref',
        );

        // The excluded asset reaches NEITHER mode as something to write.
        expect(
          narrowed.relativePaths.where((path) => path.contains('dropped')),
          isEmpty,
        );
        for (final report in [checked, installed]) {
          expect(report.stale.map((file) => file.relativePath), [
            p.join('.agents', 'skills', 'dropped', 'SKILL.md'),
            p.join('.claude', 'skills', 'dropped', 'SKILL.md'),
          ]);
          expect(report.exitCode, 1, reason: 'stale is LOUD in both modes');
        }
        expect(
          staleFile.readAsStringSync(),
          staleBytes,
          reason:
              'a stale generated file is reported, never deleted or rewritten',
        );
        expect(
          handEdited.readAsStringSync(),
          'the operator wrote this',
          reason: 'a hand-authored file is never touched in either mode',
        );
        final text = renderInstallReport(installed, diff: false);
        expect(
          text,
          contains(
            'STALE ${p.join(checkout.path, '.claude', 'skills', 'dropped', 'SKILL.md')}',
          ),
        );
        expect(text, contains('left untouched'));
      },
    );
  });

  group('renderInstallReport — the diff the operator commits', () {
    Future<OverlayInstallReport> report({bool check = false}) async {
      final f = fixture(
        assets: <GridAssetDefinition>[
          fixtureSkill('discover'),
          fixtureSkill('ops'),
          fixtureSkill('mine'),
        ],
        bodies: <String, String>{
          'extension/station_overlay/claude/skills/discover/SKILL.md':
              fixtureSkillBody('discover', 'run {{runner}}'),
          'extension/station_overlay/agents/skills/discover/SKILL.md':
              fixtureSkillBody('discover', 'run {{runner}}'),
          'extension/station_overlay/claude/skills/ops/SKILL.md':
              fixtureSkillBody('ops', 'boot {{gridHome}}'),
          'extension/station_overlay/agents/skills/ops/SKILL.md':
              fixtureSkillBody('ops', 'boot {{gridHome}}'),
        },
      );
      _write(checkout, [
        '.claude',
        'skills',
        'mine',
        'SKILL.md',
      ], 'the operator wrote this');
      return const OverlayInstallService().install(
        resolution: f.resolution(renderArguments: const {'runner': 'space'}),
        targetRoot: checkout.path,
        sourceRef: 'testref',
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
            '+++ ${p.join(checkout.path, '.claude', 'skills', 'discover', 'SKILL.md')}',
          ),
        );
        expect(text, contains('+run space'));
        expect(text, contains('BLOCKED '));
        expect(text, contains(p.join('.claude', 'skills', 'mine', 'SKILL.md')));
        expect(text, contains('REFUSED '));
        expect(text, contains('{{gridHome}}'));
        expect(
          text,
          contains(
            '3 installed, 0 updated, 0 current, 1 blocked, 2 refused, 0 stale',
          ),
        );
        expect(text, contains('NOTHING was committed'));
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

  group("the ROUND-TRIP — grid_assets' REAL vended assets", () {
    test(
      'install lands every vended skill AND the COMPLETE operator asset set — '
      'the governor agent-def and the harness settings — with no residue',
      () async {
        final report = await const OverlayInstallService().install(
          resolution: _liveResolution(
            args: const {'runner': 'space', 'gridHome': '/grid/home'},
          ),
          targetRoot: checkout.path,
          sourceRef: 'testref',
        );

        expect(
          report.refused,
          isEmpty,
          reason: 'every vended file binds against runner + gridHome',
        );
        expect(report.blocked, isEmpty);
        expect(report.stale, isEmpty);
        expect(report.installedSkillIds, vendedSkillIds);
        for (final id in vendedSkillIds) {
          final skill = File(
            p.join(checkout.path, '.claude', 'skills', id, 'SKILL.md'),
          );
          expect(skill.existsSync(), isTrue, reason: '$id is installed');
          expect(
            skill.readAsStringSync(),
            isNot(contains('{{')),
            reason: '$id has no template residue',
          );
        }

        final governor = File(
          p.join(checkout.path, '.claude', 'agents', 'governor.md'),
        );
        expect(governor.readAsStringSync(), contains('name: governor'));
        expect(hasProvenance(governor.readAsStringSync()), isTrue);

        final settings = File(
          p.join(checkout.path, '.claude', 'settings.json'),
        );
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
          resolution: _liveResolution(
            args: const {'runner': 'space', 'gridHome': '/grid/home'},
          ),
          targetRoot: checkout.path,
          sourceRef: 'testref',
        );

        expect(report.refused, isEmpty);
        expect(report.blocked, isEmpty);
        for (final id in const ['discover', 'intake-refinement']) {
          final body = File(
            p.join(checkout.path, '.claude', 'skills', id, 'SKILL.md'),
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
          resolution: _liveResolution(
            args: const {'runner': 'space', 'gridHome': '/grid/home'},
          ),
          targetRoot: checkout.path,
          sourceRef: 'testref',
        );

        expect(report.refused, isEmpty);
        expect(report.blocked, isEmpty);
        final installed = File(
          p.join(
            checkout.path,
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
