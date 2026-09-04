// The `assets install` Command — the THIN CLI adapter over the operator-install
// lib: parses argv, resolves the grid home from the injected resident-station
// context, OBSERVES that root once through the injected facts repository,
// resolves the station registry against it, renders the diff, commits nothing.
// Everything behavioral is the lib's (overlay_install_test.dart); this suite
// pins the adapter contract a composing station (`space assets install`) relies
// on. Offline: fake delegate, fake facts repository, injected source ref (so no
// git subprocess), captured sinks.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_assets/station_asset_registry.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:grid_sdk/grid_sdk.dart' show GridAssetDefinition;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/asset_resolution_fixture.dart';

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
  late Directory fixtureRoot;
  late TestAssetResolutionFixture fixture;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('grid-assets-cmd-');
    fixtureRoot = Directory(p.join(temp.path, 'fixture'))..createSync();
    fixture = TestAssetResolutionFixture(
      root: fixtureRoot,
      assets: <GridAssetDefinition>[fixtureSkill('discover')],
      bodies: <String, String>{
        'extension/station_overlay/claude/skills/discover/SKILL.md':
            fixtureSkillBody(
              'discover',
              'call {{runner}} search, file into {{gridHome}}',
            ),
        'extension/station_overlay/agents/skills/discover/SKILL.md':
            fixtureSkillBody(
              'discover',
              'call {{runner}} search, file into {{gridHome}}',
            ),
      },
    );
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  ({
    CommandRunner<int> runner,
    _StationDelegate Function() lastDelegate,
    FakeSubstationFactsRepository Function() lastRepository,
    List<String> observedRoots,
    StringBuffer out,
    StringBuffer err,
  })
  harness({
    String? runnerInvocation,
    String? delegateRoot,
    List<GridAssetDefinition>? assets,
    GridAssetRosterOverride? rosterOverride,
  }) {
    final out = StringBuffer();
    final err = StringBuffer();
    final observedRoots = <String>[];
    _StationDelegate? lastDelegate;
    FakeSubstationFactsRepository? lastRepository;
    final registry = assets == null
        ? fixture.registry
        : sdk.GridAssetRegistry(<sdk.GridAssetPackDefinition>[
            sdk.GridAssetPackDefinition(
              package: kFixturePackage,
              assets: assets,
            ),
          ]);
    final runner = CommandRunner<int>('space', 'test station')
      ..addCommand(
        AssetsCommand(
          delegate: () =>
              lastDelegate = _StationDelegate(delegateRoot ?? temp.path),
          registry: registry,
          rosterOverride: rosterOverride,
          runnerInvocation: runnerInvocation,
          // The OBSERVATION seam: the Command owns and disposes whatever this
          // returns, and it observes the root it resolved.
          factsRepository: ({required roots, required registry}) {
            observedRoots.addAll(roots.values);
            return lastRepository = FakeSubstationFactsRepository(
              SubstationFactsSnapshot(<SubstationKey, SubstationFacts>{
                kGridHomeSubstation: SubstationFacts(
                  root: roots[kGridHomeSubstation]!,
                  dartPackages: const <String>[kFixturePackage, 'grid_sdk'],
                  packageRoots: <String, String>{
                    kFixturePackage: fixture.packageRoot,
                  },
                ),
              }),
            );
          },
          sourceRef: (_) => 'testref',
          out: out,
          err: err,
        ),
      );
    return (
      runner: runner,
      lastDelegate: () => lastDelegate!,
      lastRepository: () => lastRepository!,
      observedRoots: observedRoots,
      out: out,
      err: err,
    );
  }

  File installedSkill(Directory root) =>
      File(p.join(root.path, '.claude', 'skills', 'discover', 'SKILL.md'));

  test(
    'writes the selected assets onto the grid home ROOT by default — binding '
    '{{runner}} from the CLI verb and {{gridHome}} from the mounted GridRoot, '
    'and stamping each file with the source ref',
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
        File(
          p.join(temp.path, '.agents', 'skills', 'discover', 'SKILL.md'),
        ).existsSync(),
        isTrue,
        reason: 'the agents leg is written alongside the claude one',
      );
      expect(h.out.toString(), contains('--- /dev/null'));
      expect(h.out.toString(), contains('NOTHING was committed'));
      expect(
        h.lastDelegate().disposed,
        isTrue,
        reason: 'the command owns the delegate it asked for',
      );
      expect(
        h.lastRepository().disposed,
        isTrue,
        reason: 'and the fact observer it constructed',
      );
      expect(
        h.lastRepository().refreshes,
        1,
        reason: 'the roots are observed ONCE, outside any build',
      );
      expect(h.observedRoots, [p.normalize(temp.path)]);
    },
  );

  test(
    'runnerInvocation overrides the CLI executable name for JIT stations',
    () async {
      final h = harness(runnerInvocation: 'dart run lunar:lunar');

      final code = await h.runner.run(['assets', 'install']);

      expect(code, 0);
      expect(
        installedSkill(temp).readAsStringSync(),
        contains('call dart run lunar:lunar search, file into ${temp.path}'),
      );
    },
  );

  test('--root writes onto an explicit repo root', () async {
    final elsewhere = Directory(p.join(temp.path, 'elsewhere'))
      ..createSync(recursive: true);

    final h = harness();
    final code = await h.runner.run([
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
    expect(
      h.observedRoots,
      [p.normalize(elsewhere.path)],
      reason: 'the facts are observed at the root actually being written',
    );
  });

  test(
    '--source-ref overrides the probed ref in every provenance header',
    () async {
      final code = await harness().runner.run([
        'assets',
        'install',
        '--source-ref',
        'v1.2.3',
      ]);

      expect(code, 0);
      expect(installedSkill(temp).readAsStringSync(), contains('v1.2.3'));
    },
  );

  test(
    '--no-diff prints no diff body but still names what it installed',
    () async {
      final h = harness();

      final code = await h.runner.run(['assets', 'install', '--no-diff']);

      expect(code, 0);
      expect(h.out.toString(), isNot(contains('--- /dev/null')));
      expect(h.out.toString(), contains('installed '));
    },
  );

  group('--check — the no-drift enforcement', () {
    test(
      'writes NOTHING and exits non-zero, naming each MISSING file',
      () async {
        final h = harness();

        final code = await h.runner.run(['assets', 'install', '--check']);

        expect(code, 1);
        expect(h.out.toString(), contains('MISSING '));
        expect(
          installedSkill(temp).existsSync(),
          isFalse,
          reason: '--check is a PLAN — it writes nothing',
        );
      },
    );

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
    final h = harness(
      assets: <GridAssetDefinition>[
        fixtureSkill('discover'),
        fixtureSkill('ops'),
      ],
    );
    _write(Directory(fixture.packageRoot), [
      'extension',
      'station_overlay',
      'claude',
      'skills',
      'ops',
      'SKILL.md',
    ], fixtureSkillBody('ops', 'boot {{unbound}}'));
    _write(Directory(fixture.packageRoot), [
      'extension',
      'station_overlay',
      'agents',
      'skills',
      'ops',
      'SKILL.md',
    ], fixtureSkillBody('ops', 'boot {{unbound}}'));

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

  test(
    'a registry that selects nothing installable is a LOUD non-answer, never a '
    'silent no-op',
    () async {
      final h = harness(assets: <GridAssetDefinition>[fixtureRubric('graded')]);

      final code = await h.runner.run(['assets', 'install']);

      expect(code, 1);
      expect(
        h.err.toString(),
        contains('selects no installable asset for ${temp.path}'),
      );
      expect(
        h.lastRepository().disposed,
        isTrue,
        reason: 'the refusal still disposes what it constructed',
      );
    },
  );

  test('a roster exclusion withholds an asset from the install', () async {
    final h = harness(
      rosterOverride: GridAssetRosterOverride(
        exclude: const [
          sdk.AssetKey(
            package: kFixturePackage,
            kind: sdk.AssetKind.skill,
            id: 'discover',
          ),
        ],
      ),
    );

    final code = await h.runner.run(['assets', 'install']);

    expect(code, 1, reason: 'nothing remains to install');
    expect(installedSkill(temp).existsSync(), isFalse);
  });

  test('grid-home override is trimmed and normalized before install', () async {
    final h = harness();

    expect(
      await h.runner.run([
        'assets',
        'install',
        '--grid-home',
        '  ${temp.path}/nested/..  ',
      ]),
      0,
    );
    expect(
      installedSkill(temp).readAsStringSync(),
      contains('file into ${p.normalize(temp.path)}'),
    );
  });

  test('absent grid-home still resolves by mounted tree position', () async {
    final authored = p.join(temp.path, 'authored', '..');
    final h = harness(delegateRoot: authored);

    expect(await h.runner.run(['assets', 'install']), 0);
    expect(h.observedRoots, [p.normalize(authored)]);
  });

  test(
    'a relative grid home is a LOUD usage refusal with the stamping reason',
    () async {
      final h = harness(delegateRoot: 'relative/grid');

      await expectLater(
        h.runner.run(['assets', 'install']),
        throwsA(
          isA<UsageException>()
              .having((error) => error.message, 'message', contains('ABSOLUTE'))
              .having(
                (error) => error.message,
                'reason',
                contains('baked into the committed manual'),
              ),
        ),
      );
      expect(h.lastDelegate().disposed, isTrue);
    },
  );

  test(
    'a resident-station context with no grid root REFUSES and names the lever',
    () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = CommandRunner<int>('space', 'test station')
        ..addCommand(
          AssetsCommand(
            delegate: () => _RootlessDelegate(temp.path),
            registry: fixture.registry,
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
    'a LOUD lib refusal (a selected source that is missing) is reported, never '
    'a stack trace',
    () async {
      final h = harness();
      File(
        p.join(
          fixture.packageRoot,
          'extension',
          'station_overlay',
          'claude',
          'skills',
          'discover',
          'SKILL.md',
        ),
      ).deleteSync();

      final code = await h.runner.run(['assets', 'install']);

      expect(code, 1);
      expect(
        h.err.toString(),
        contains('assets install: selected artifact source is missing'),
      );
      expect(h.lastDelegate().disposed, isTrue);
      expect(h.lastRepository().disposed, isTrue);
    },
  );

  test('AssetsCommand defaults to the generated registry when omitted', () async {
    // The compatibility seam: a station that composed this Command before the
    // registry parameter existed keeps installing the SAME set, because
    // omission resolves to the one generated object — never a second registry
    // built here.
    final observed = <sdk.GridAssetRegistry>[];
    final out = StringBuffer();
    final err = StringBuffer();

    SubstationFactsRepository observe({
      required Map<SubstationKey, String> roots,
      required sdk.GridAssetRegistry registry,
    }) {
      observed.add(registry);
      return FakeSubstationFactsRepository(
        SubstationFactsSnapshot(<SubstationKey, SubstationFacts>{
          kGridHomeSubstation: SubstationFacts(
            root: roots[kGridHomeSubstation]!,
            dartPackages: const <String>['grid_assets', 'grid_sdk'],
            packageRoots: <String, String>{'grid_assets': _packageRoot()},
          ),
        }),
      );
    }

    final umbrella = CommandRunner<int>('space', 'test station')
      ..addCommand(
        // NO `registry:` argument at all — the pre-bead call shape.
        AssetsCommand(
          delegate: () => _StationDelegate(temp.path),
          factsRepository: observe,
          sourceRef: (_) => 'testref',
          out: out,
          err: err,
        ),
      );

    final code = await umbrella.run(['assets', 'install', '--no-diff']);

    expect(code, 0, reason: err.toString());
    expect(observed, hasLength(1));
    expect(
      identical(observed.single, GeneratedGridAssetRegistrant.registry),
      isTrue,
      reason: 'the umbrella resolves the omitted registry to the generated one',
    );

    // The same identity through the subcommand's OWN construction seam, which a
    // station may compose directly.
    final direct = CommandRunner<int>('space', 'test station')
      ..addCommand(
        AssetsInstallCommand(
          delegate: () => _StationDelegate(temp.path),
          factsRepository: observe,
          sourceRef: (_) => 'testref',
          out: out,
          err: err,
        ),
      );

    expect(
      await direct.run(['install', '--no-diff']),
      0,
      reason: err.toString(),
    );
    expect(observed, hasLength(2));
    expect(
      identical(observed.last, GeneratedGridAssetRegistrant.registry),
      isTrue,
    );
  });

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
              'the operator reads the diff and commits',
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
