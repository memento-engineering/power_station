// The vended-asset WRITER: [OverlayMaterializer] writes ONE resolved asset set
// onto a target ROOT — each selected artifact read from its exact declared
// source and written at its exact declared target — rendering each file,
// refusing a half-bound one, stamping what it writes, never clobbering what it
// did not generate, and reporting (never sweeping) a generated file the
// resolution no longer selects. The WIRE half (the provision hook that drives
// this into a live worktree, and the git exclusion it writes there) is covered
// in `track_h_code_extension_test.dart` + `overlay_golden_test.dart`.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_assets/station_asset_registry.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/asset_resolution_fixture.dart';

/// Resolves this package's `extension/` dir the CWD-INDEPENDENT way (the
/// loader's own package-config resolution), so the live-tree test never
/// disagrees with the loader.
///
/// Never a cwd walk: `Directory.current` is process-global and the suites run
/// concurrently, so the sibling suite that chdirs to a foreign dir to prove
/// cwd-independent resolution (`track_d_assets_test`) would race a walk done
/// from inside a test body here.
String _extensionDir() => PackagedAssetLoader().root;

/// The LIVE station registry resolved against this checkout — the real vended
/// pack, selected exactly as a station selects it.
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

void main() {
  late Directory temp;
  late Directory target;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('grid-overlay-');
    target = Directory(p.join(temp.path, 'target'));
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  TestAssetResolutionFixture fixture({
    List<GridAssetDefinition>? assets,
    Map<String, String> bodies = const <String, String>{},
    Iterable<String> extraPackages = const <String>[],
  }) => TestAssetResolutionFixture(
    root: temp,
    assets: assets ?? <GridAssetDefinition>[fixtureSkill('foo')],
    bodies: bodies,
    extraPackages: extraPackages,
  );

  group('OverlayMaterializer — writes the RESOLUTION, never a walk', () {
    test(
      'each selected artifact is read from its declared source and written at '
      'its declared target — skills, a loose settings file, and nothing else',
      () async {
        final f = fixture(
          assets: <GridAssetDefinition>[
            fixtureSkill('foo'),
            fixtureSettings('harness'),
            fixtureRubric('graded'),
          ],
          bodies: const <String, String>{
            'extension/station_overlay/claude/settings.json':
                '{\n  "hooks": {}\n}\n',
          },
        );
        // An UNDECLARED file beside a declared one: a source walk would carry
        // it; the resolution cannot see it.
        f.writeStraySource(
          'extension/station_overlay/claude/skills/foo/NOTES.md',
          fixtureSkillBody('notes'),
        );

        final report = await const OverlayMaterializer().materialize(
          resolution: f.resolution(),
          targetRoot: target.path,
          sourceRef: 'testref',
        );

        expect(report.written.map((file) => file.relativePath), [
          p.join('.claude', 'skills', 'foo', 'SKILL.md'),
          p.join('.agents', 'skills', 'foo', 'SKILL.md'),
          p.join('.claude', 'settings.json'),
        ]);
        expect(
          File(p.join(target.path, '.claude', 'settings.json')).existsSync(),
          isTrue,
          reason: 'a declared loose file under `.claude/` is legal',
        );
        expect(
          File(
            p.join(target.path, '.claude', 'skills', 'foo', 'NOTES.md'),
          ).existsSync(),
          isFalse,
          reason: 'an undeclared source file is installed NOWHERE',
        );
        expect(report.blocked, isEmpty);
        expect(report.refused, isEmpty);
        expect(report.stale, isEmpty);
        expect(report.installedSkillIdsUnder(kClaudeSkillsSubtree), ['foo']);
        expect(
          report.written.first.sourceRoot,
          f.packageRoot,
          reason: 'the vending package root is the recorded source',
        );
      },
    );

    test(
      'subtrees SCOPE the write — the worktree leg takes the skill trees only, '
      'never a loose .claude/settings.json',
      () async {
        final f = fixture(
          assets: <GridAssetDefinition>[
            fixtureSkill('a'),
            fixtureSettings('harness'),
          ],
          bodies: const <String, String>{
            'extension/station_overlay/claude/settings.json':
                '{\n  "hooks": {}\n}\n',
          },
        );

        final report = await const OverlayMaterializer().materialize(
          resolution: f.resolution(),
          targetRoot: target.path,
          sourceRef: 'testref',
          subtrees: const [kClaudeSkillsSubtree],
        );

        expect(report.written.map((file) => file.relativePath), [
          p.join('.claude', 'skills', 'a', 'SKILL.md'),
        ]);
        expect(
          File(p.join(target.path, '.claude', 'settings.json')).existsSync(),
          isFalse,
          reason: 'a scoped caller never reaches repo-owned territory (A23(6))',
        );
      },
    );

    test(
      'a resolution that selects nothing writes nothing (not an error)',
      () async {
        final f = fixture(
          assets: <GridAssetDefinition>[
            fixtureSkill(
              'gated',
              selector: const RequiresPackage('absent_pack'),
            ),
          ],
        );

        final report = await const OverlayMaterializer().materialize(
          resolution: f.resolution(),
          targetRoot: target.path,
          sourceRef: 'testref',
        );

        expect(report.files, isEmpty);
      },
    );

    test('materializeSync — the entry point the provision wire rides, since '
        'ProcessCapability.spawn cannot await — mirrors materialize', () {
      final f = fixture();

      final report = const OverlayMaterializer().materializeSync(
        resolution: f.resolution(),
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
        report.written.map((file) => file.relativePath),
        contains(p.join('.claude', 'skills', 'foo', 'SKILL.md')),
      );
      expect(report.blocked, isEmpty);
      expect(report.refused, isEmpty);
    });

    test('a selected artifact whose SOURCE is missing THROWS — a shrunken '
        'install is never silent', () {
      final f = fixture();
      File(
        p.join(
          f.packageRoot,
          'extension',
          'station_overlay',
          'claude',
          'skills',
          'foo',
          'SKILL.md',
        ),
      ).deleteSync();

      expect(
        () => const OverlayMaterializer().materializeSync(
          resolution: f.resolution(),
          targetRoot: target.path,
          sourceRef: 'testref',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('selected artifact source is missing'),
          ),
        ),
      );
    });
  });

  group('OverlayMaterializer — provenance', () {
    test(
      'every written file carries the stamp, naming the source ref',
      () async {
        final f = fixture();

        await const OverlayMaterializer().materialize(
          resolution: f.resolution(renderArguments: const {'runner': 'space'}),
          targetRoot: target.path,
          sourceRef: 'abc1234',
        );

        final body = File(
          p.join(target.path, '.claude', 'skills', 'foo', 'SKILL.md'),
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
      final f = fixture();
      const m = OverlayMaterializer();
      final first = await m.materialize(
        resolution: f.resolution(),
        targetRoot: target.path,
        sourceRef: 'ref1',
      );
      final onDisk = File(
        p.join(target.path, '.claude', 'skills', 'foo', 'SKILL.md'),
      ).readAsStringSync();

      final second = await m.materialize(
        resolution: f.resolution(),
        targetRoot: target.path,
        sourceRef: 'ref2',
      );

      expect(first.written, hasLength(2));
      expect(second.written, isEmpty);
      expect(second.unchanged, hasLength(2));
      expect(
        File(
          p.join(target.path, '.claude', 'skills', 'foo', 'SKILL.md'),
        ).readAsStringSync(),
        onDisk,
      );
    });

    test(
      'a DRIFTED generated file is regenerated; a HAND-AUTHORED one (no stamp) '
      'is BLOCKED, never clobbered',
      () async {
        final f = fixture(
          assets: <GridAssetDefinition>[fixtureSkill('a'), fixtureSkill('b')],
          bodies: <String, String>{
            'extension/station_overlay/claude/skills/a/SKILL.md':
                fixtureSkillBody('a', 'new body'),
          },
        );
        final drifted = _write(
          target,
          ['.claude', 'skills', 'a', 'SKILL.md'],
          stampProvenance(
            fixtureSkillBody('a', 'OLD body'),
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
          resolution: f.resolution(),
          targetRoot: target.path,
          sourceRef: 'ref2',
          subtrees: const [kClaudeSkillsSubtree],
        );

        expect(report.updated.map((file) => file.relativePath), [
          p.join('.claude', 'skills', 'a', 'SKILL.md'),
        ]);
        expect(report.blocked.map((file) => file.relativePath), [
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
      final f = fixture();

      final report = await const OverlayMaterializer().materialize(
        resolution: f.resolution(),
        targetRoot: target.path,
        sourceRef: 'testref',
        dryRun: true,
      );

      expect(report.dryRun, isTrue);
      expect(report.written, hasLength(2));
      expect(
        File(
          p.join(target.path, '.claude', 'skills', 'foo', 'SKILL.md'),
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
        final f = fixture(assets: <GridAssetDefinition>[fixtureSkill('a')]);
        // The seat's shape: `.claude/skills/a/SKILL.md -> <outside>/SKILL.md`.
        final outside = _write(
          Directory(p.join(temp.path, 'elsewhere')),
          ['skills', 'a', 'SKILL.md'],
          'the REAL file, outside the target root',
        );
        Link(p.join(target.path, '.claude', 'skills', 'a', 'SKILL.md'))
          ..parent.createSync(recursive: true)
          ..createSync(outside.path);

        final report = await const OverlayMaterializer().materialize(
          resolution: f.resolution(),
          targetRoot: target.path,
          sourceRef: 'testref',
          subtrees: const [kClaudeSkillsSubtree],
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
        final f = fixture(assets: <GridAssetDefinition>[fixtureSkill('a')]);
        // The real file lives OUTSIDE the target root, and — the dangerous part
        // — it already carries a stamp, so only the ancestor check can stop the
        // write from following the dir link and mutating it.
        final outside = _write(
          Directory(p.join(temp.path, 'elsewhere')),
          ['skills', 'a', 'SKILL.md'],
          stampProvenance(
            fixtureSkillBody('a', 'OLD body'),
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
        ).createSync(p.join(temp.path, 'elsewhere', 'skills', 'a'));

        final report = await const OverlayMaterializer().materialize(
          resolution: f.resolution(),
          targetRoot: target.path,
          sourceRef: 'testref',
          subtrees: const [kClaudeSkillsSubtree],
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
        final f = fixture(assets: <GridAssetDefinition>[fixtureSkill('a')]);
        Link(p.join(target.path, '.claude', 'skills', 'a', 'SKILL.md'))
          ..parent.createSync(recursive: true)
          ..createSync(p.join(temp.path, 'nowhere', 'SKILL.md'));

        late final OverlayMaterializeReport report;
        expect(
          () async => report = await const OverlayMaterializer().materialize(
            resolution: f.resolution(),
            targetRoot: target.path,
            sourceRef: 'testref',
            subtrees: const [kClaudeSkillsSubtree],
          ),
          returnsNormally,
        );

        await pumpEventQueue();
        expect(report.blocked.single.symlink, isTrue);
      },
    );

    test('a vended file that cannot carry a stamp THROWS — never installed '
        'indistinguishably from a hand-authored one', () {
      const unstampable = GridAssetDefinition(
        assetKey: AssetKey(
          package: kFixturePackage,
          kind: AssetKind.resource,
          id: 'notes',
        ),
        description: 'plain text has no provenance syntax',
        artifacts: <AssetArtifact>[
          AssetArtifact(
            target: AssetDeliveryTarget.claude,
            path: 'extension/station_overlay/claude/notes.txt',
          ),
        ],
      );
      final f = fixture(
        assets: const <GridAssetDefinition>[unstampable],
        bodies: const <String, String>{
          'extension/station_overlay/claude/notes.txt': 'plain text',
        },
      );

      expect(
        () => const OverlayMaterializer().materializeSync(
          resolution: f.resolution(),
          targetRoot: target.path,
          sourceRef: 'testref',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('no provenance syntax'),
          ),
        ),
      );
    });
  });

  group('OverlayMaterializer — STALE targets are named, never swept', () {
    test('a stamped target the resolution no longer selects is reported and '
        'left byte-for-byte alone, in BOTH modes', () async {
      final f = fixture(assets: <GridAssetDefinition>[fixtureSkill('kept')]);
      final withdrawn = stampProvenance(
        fixtureSkillBody('withdrawn'),
        relativePath: '.claude/skills/withdrawn/SKILL.md',
        sourceRef: 'old',
        runner: 'space',
      );
      final orphan = _write(target, [
        '.claude',
        'skills',
        'withdrawn',
        'SKILL.md',
      ], withdrawn);
      // An UNSTAMPED neighbour: somebody else's file, and not this lib's to
      // speak about at all.
      final foreign = _write(target, [
        '.claude',
        'skills',
        'theirs',
        'SKILL.md',
      ], 'hand written');

      final write = await const OverlayMaterializer().materialize(
        resolution: f.resolution(),
        targetRoot: target.path,
        sourceRef: 'testref',
      );
      final check = await const OverlayMaterializer().materialize(
        resolution: f.resolution(),
        targetRoot: target.path,
        sourceRef: 'testref',
        dryRun: true,
      );

      expect(write.stale.map((file) => file.relativePath), [
        p.join('.claude', 'skills', 'withdrawn', 'SKILL.md'),
      ]);
      expect(
        check.stale.map((file) => file.relativePath),
        write.stale.map((file) => file.relativePath),
      );
      expect(orphan.readAsStringSync(), withdrawn);
      expect(foreign.readAsStringSync(), 'hand written');
      expect(
        write.stale.single.checkClassification,
        OverlayCheckClassification.stale,
      );
      expect(
        write.installedSkillIdsUnder(kClaudeSkillsSubtree),
        ['kept'],
        reason: 'a stale skill is not installed by this call',
      );
    });

    test('the stale scan honours the SCOPE — an unscoped install reads both '
        'harness heads, a worktree leg reads only its skill trees', () async {
      final f = fixture(assets: <GridAssetDefinition>[fixtureSkill('kept')]);
      _write(
        target,
        ['.claude', 'settings.json'],
        stampProvenance(
          '{\n  "hooks": {}\n}\n',
          relativePath: '.claude/settings.json',
          sourceRef: 'old',
          runner: 'space',
        ),
      );
      _write(
        target,
        ['.agents', 'skills', 'gone', 'SKILL.md'],
        stampProvenance(
          fixtureSkillBody('gone'),
          relativePath: '.agents/skills/gone/SKILL.md',
          sourceRef: 'old',
          runner: 'space',
        ),
      );

      final unscoped = const OverlayMaterializer().materializeSync(
        resolution: f.resolution(),
        targetRoot: target.path,
        sourceRef: 'testref',
      );
      final scoped = const OverlayMaterializer().materializeSync(
        resolution: f.resolution(),
        targetRoot: target.path,
        sourceRef: 'testref',
        subtrees: kWorktreeOverlaySubtrees,
      );

      expect(unscoped.stale.map((file) => file.relativePath), [
        p.join('.agents', 'skills', 'gone', 'SKILL.md'),
        p.join('.claude', 'settings.json'),
      ]);
      expect(
        scoped.stale.map((file) => file.relativePath),
        [p.join('.agents', 'skills', 'gone', 'SKILL.md')],
        reason: 'the loose settings file is outside the worktree scope',
      );
    });
  });

  group('OverlayMaterializer — render + refuse', () {
    test('declared args are substituted into every written file', () async {
      final f = fixture(
        bodies: <String, String>{
          'extension/station_overlay/claude/skills/foo/SKILL.md':
              fixtureSkillBody('foo', 'run {{runner}} search in {{gridHome}}'),
        },
      );

      await const OverlayMaterializer().materialize(
        resolution: f.resolution(
          renderArguments: const {'runner': 'space', 'gridHome': '/grid/home'},
        ),
        targetRoot: target.path,
        sourceRef: 'testref',
        subtrees: const [kClaudeSkillsSubtree],
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
        final f = fixture(
          bodies: <String, String>{
            'extension/station_overlay/claude/skills/foo/SKILL.md':
                fixtureSkillBody('foo', 'run {{runner}} in {{gridHome}}'),
          },
        );

        final report = await const OverlayMaterializer().materialize(
          resolution: f.resolution(renderArguments: const {'runner': 'space'}),
          targetRoot: target.path,
          sourceRef: 'testref',
          subtrees: const [kClaudeSkillsSubtree],
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
        expect(refused.checkClassification, OverlayCheckClassification.drifted);
        expect(
          report.installedSkillIdsUnder(kClaudeSkillsSubtree),
          isEmpty,
          reason: 'a refused skill must never be named to an agent',
        );
      },
    );
  });

  group("OverlayMaterializeReport — the wire's git fence is LOUD", () {
    test(
      'writtenAssetDirsUnder names the asset dirs the wire must fence',
      () async {
        final f = fixture(
          assets: <GridAssetDefinition>[fixtureSkill('a'), fixtureSkill('b')],
        );

        final report = await const OverlayMaterializer().materialize(
          resolution: f.resolution(),
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
        const loose = GridAssetDefinition(
          assetKey: AssetKey(
            package: kFixturePackage,
            kind: AssetKind.resource,
            id: 'stray',
          ),
          description: 'declared loose under the skills tree',
          artifacts: <AssetArtifact>[
            AssetArtifact(
              target: AssetDeliveryTarget.claude,
              path: 'extension/station_overlay/claude/skills/stray.md',
            ),
          ],
        );
        final f = fixture(
          assets: const <GridAssetDefinition>[loose],
          bodies: <String, String>{
            'extension/station_overlay/claude/skills/stray.md':
                fixtureSkillBody('stray'),
          },
        );

        final report = await const OverlayMaterializer().materialize(
          resolution: f.resolution(),
          targetRoot: target.path,
          sourceRef: 'testref',
        );

        expect(
          () => report.writtenAssetDirsUnder(kClaudeSkillsSubtree),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(contains('stray.md'), contains('malformed overlay')),
            ),
          ),
        );
      },
    );
  });

  group('OverlayMaterializer — the live grid_assets registry', () {
    test(
      'the REAL registry round-trips the vended discover skill at its declared '
      'target: a frontmatter-led SKILL.md with no {{ residue',
      () async {
        final report = await const OverlayMaterializer().materialize(
          resolution: _liveResolution(args: const {'runner': 'space'}),
          targetRoot: target.path,
          sourceRef: 'testref',
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
