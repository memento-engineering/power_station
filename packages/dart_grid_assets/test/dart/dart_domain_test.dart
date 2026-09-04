// The grid.dart domain config prototype (SCRATCH-pub-capability-and-repo-split)
// — the FIRST "domains serialize their own information" instance, so these
// tests pin the PRECEDENT: the versioned envelope codec (fail-closed), the pure
// context-application (pubspec_overrides.yaml derivation), the UI-drivable
// service layer, and the thin exported Command. Offline: temp dirs only; no
// live bd/pub/network; the_grid only READS work-bead metadata (A37).
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_grid_assets/dart_grid_assets.dart';
import 'package:test/test.dart';

/// A work-bead metadata map carrying a grid.dart envelope with [links].
Map<String, dynamic> _metadataWith(
  List<PubLink> links, {
  String version = kDartAssetsVersion,
}) => {
  'validation_plan': 'dart test', // neighbors survive untouched (merge model)
  kDartDomainKey: {
    'assets_version': version,
    'payload': {'pub': PubLinkConfig(links: links).toJson()},
  },
};

const _genesisLink = PubLink(
  package: 'genesis_tree',
  devPath: '../genesis/packages/tree',
  hosted: '^0.1.3',
);

void main() {
  group('the grid.dart envelope codec (versioned, fail-closed — over the '
      'shared domain-envelope machinery)', () {
    test('round-trips through the envelope shape (no packs_version — that is '
        'the TOML gc-packs-protocol field, not a Dart-asset one)', () {
      const config = DartDomainConfig(
        pub: PubLinkConfig(links: [_genesisLink]),
      );
      final metadata = <String, dynamic>{kDartDomainKey: config.toEnvelope()};
      final result = decodeDartEnvelope(metadata);
      expect(result, isA<DomainEnvelopeDecoded<DartDomainConfig>>());
      expect(
        (result as DomainEnvelopeDecoded<DartDomainConfig>).config,
        config,
      );
      final envelope = metadata[kDartDomainKey] as Map<String, Object?>;
      // The envelope is stamped with THIS pack's version…
      expect(envelope['assets_version'], kDartAssetsVersion);
      // …and carries NO packs_version (gc packs protocol = TOML packs only).
      expect(envelope.containsKey('packs_version'), isFalse);
    });

    test('no grid.dart key → Absent (the common case, not an error)', () {
      expect(
        decodeDartEnvelope({'gc.some_key': 'x'}),
        isA<DomainEnvelopeAbsent<DartDomainConfig>>(),
      );
    });

    test('an envelope written by an INCOMPATIBLE pack is refused whole '
        '(fail-closed — never a partial parse of a newer shape)', () {
      final result = decodeDartEnvelope(
        _metadataWith([_genesisLink], version: '0.1.0'),
      );
      expect(result, isA<DomainEnvelopeIncompatible<DartDomainConfig>>());
      expect(
        (result as DomainEnvelopeIncompatible<DartDomainConfig>).version,
        '0.1.0',
      );
    });

    test('pre-1.0 minor is BREAKING; 1.x major gates compatibility (the '
        'SHARED gate, pub_semver-parsed)', () {
      bool compat(String theirs) =>
          envelopeVersionCompatible(ours: kDartAssetsVersion, theirs: theirs);
      expect(compat(kDartAssetsVersion), isTrue);
      expect(
        compat('0.0.9'),
        isTrue,
        reason: 'same 0.0 minor — patch is compatible (additive-only rule)',
      );
      expect(
        compat('0.1.0'),
        isFalse,
        reason: 'pre-1.0 minor bump is breaking (pub semantics)',
      );
      expect(compat('1.0.0'), isFalse);
      expect(
        compat('garbage'),
        isFalse,
        reason: 'unparseable → incompatible (fail-closed)',
      );
      expect(
        compat('0.-1.0'),
        isFalse,
        reason: 'negative components are not semver — fail-closed',
      );
      expect(
        compat('1.-1.0'),
        isFalse,
        reason: 'a negative component must never slip a major gate',
      );
      // The from-1.0 half of the rule (major-gated).
      expect(
        envelopeVersionCompatible(ours: '1.2.0', theirs: '1.9.3'),
        isTrue,
        reason: 'post-1.0: same major is compatible',
      );
      expect(
        envelopeVersionCompatible(ours: '1.2.0', theirs: '2.0.0'),
        isFalse,
      );
    });

    test('malformed envelopes are refused with a reason (never applied)', () {
      expect(
        decodeDartEnvelope({kDartDomainKey: 'not-an-object'}),
        isA<DomainEnvelopeMalformed<DartDomainConfig>>(),
      );
      expect(
        decodeDartEnvelope({
          kDartDomainKey: {'payload': <String, Object?>{}},
        }),
        isA<DomainEnvelopeMalformed<DartDomainConfig>>(),
        reason: 'missing assets_version',
      );
      expect(
        decodeDartEnvelope({
          kDartDomainKey: {'assets_version': kDartAssetsVersion},
        }),
        isA<DomainEnvelopeMalformed<DartDomainConfig>>(),
        reason: 'missing payload',
      );
      expect(
        decodeDartEnvelope({
          kDartDomainKey: {
            'assets_version': kDartAssetsVersion,
            'payload': {
              'pub': {
                'links': [
                  {'dev_path': '/x'}, // no package name
                ],
              },
            },
          },
        }),
        isA<DomainEnvelopeMalformed<DartDomainConfig>>(),
        reason: 'a link without a package is malformed, not skipped',
      );
      expect(
        decodeDartEnvelope({
          kDartDomainKey: {
            'assets_version': kDartAssetsVersion,
            'payload': {
              'pub': {
                'links': [123], // a non-object entry
              },
            },
          },
        }),
        isA<DomainEnvelopeMalformed<DartDomainConfig>>(),
        reason:
            'a non-object link entry is malformed (explicitly, not via an '
            'implicit cast error)',
      );
      expect(
        decodeDartEnvelope({
          kDartDomainKey: {
            'assets_version': kDartAssetsVersion,
            'payload': {
              'pub': {
                'links': [
                  {'package': 'bad: name #!', 'dev_path': '/x'},
                ],
              },
            },
          },
        }),
        isA<DomainEnvelopeMalformed<DartDomainConfig>>(),
        reason:
            'a YAML-hostile "package name" is refused at DECODE, so it can '
            'never reach the overrides emitter',
      );
    });
  });

  group('pubspecOverridesFor — the pure context application', () {
    const config = PubLinkConfig(links: [_genesisLink]);

    test('stable → null for a link with NO git pin (its pubspec.yaml pin '
        'stands — ADR-0003 D5)', () {
      expect(pubspecOverridesFor(config, PubLinkContext.stable), isNull);
    });

    test('stable → emits a git override for a git-pinned link '
        '(git: {url, ref, path: packages/<pkg>}) — ADR-0003 D2', () {
      const pinned = PubLinkConfig(
        links: [
          PubLink(
            package: 'genesis_tree',
            gitUrl: 'git@github.com:memento-engineering/genesis.git',
            gitRef: 'genesis_tree-v0.1.3',
          ),
        ],
      );
      final yaml = pubspecOverridesFor(pinned, PubLinkContext.stable)!;
      expect(yaml, startsWith('# Generated by the grid.dart domain'));
      expect(yaml, contains('dependency_overrides:'));
      expect(yaml, contains('genesis_tree:'));
      expect(yaml, contains('    git:'));
      expect(
        yaml,
        contains("url: 'git@github.com:memento-engineering/genesis.git'"),
      );
      expect(yaml, contains("ref: 'genesis_tree-v0.1.3'"));
      expect(yaml, contains("path: 'packages/genesis_tree'"));
    });

    test('stable → REFUSES a PARTIAL git pin LOUDLY: url without ref (never a '
        'silent path fallback) — ADR-0003 D2', () {
      const partial = PubLinkConfig(
        links: [
          PubLink(
            package: 'genesis_tree',
            devPath: '../genesis/packages/tree',
            gitUrl: 'git@github.com:memento-engineering/genesis.git',
          ),
        ],
      );
      expect(
        () => pubspecOverridesFor(partial, PubLinkContext.stable),
        throwsA(isA<StateError>()),
      );
    });

    test('stable → REFUSES a PARTIAL git pin LOUDLY: ref without url', () {
      const partial = PubLinkConfig(
        links: [
          PubLink(package: 'genesis_tree', gitRef: 'genesis_tree-v0.1.3'),
        ],
      );
      expect(
        () => pubspecOverridesFor(partial, PubLinkContext.stable),
        throwsA(isA<StateError>()),
      );
    });

    test('stable → a NEITHER-git link contributes no override; git-pinned '
        'links emit sorted by package', () {
      const mixed = PubLinkConfig(
        links: [
          PubLink(package: 'zeta', gitUrl: 'git@h:z.git', gitRef: 'zeta-v1'),
          PubLink(package: 'hosted_only', hosted: '^1.0.0'),
          PubLink(package: 'alpha', gitUrl: 'git@h:a.git', gitRef: 'alpha-v1'),
        ],
      );
      final yaml = pubspecOverridesFor(mixed, PubLinkContext.stable)!;
      expect(
        yaml,
        isNot(contains('hosted_only')),
        reason: 'a link with no git pin emits no override (D5)',
      );
      expect(
        yaml.indexOf('alpha:'),
        lessThan(yaml.indexOf('zeta:')),
        reason: 'git links emit sorted by package',
      );
    });

    test('dev → the declared (relative) path as-is (single-quoted scalar)', () {
      final yaml = pubspecOverridesFor(config, PubLinkContext.dev);
      expect(yaml, contains('genesis_tree:'));
      expect(yaml, contains("path: '../genesis/packages/tree'"));
      expect(yaml, startsWith('# Generated by the grid.dart domain'));
    });

    test('worktree ABSOLUTIZES a relative path against devRoot (normalized) — '
        'the genesis_tree deep-worktree fix', () {
      final yaml = pubspecOverridesFor(
        config,
        PubLinkContext.worktree,
        devRoot: '/work/umbrella/the_grid',
      );
      expect(
        yaml,
        contains("path: '/work/umbrella/genesis/packages/tree'"),
        reason:
            'the ../ collapses through normalize — an absolute path '
            'resolves from ANY worktree depth',
      );
    });

    test('worktree with an ABSOLUTE declaration passes through untouched', () {
      const abs = PubLinkConfig(
        links: [
          PubLink(
            package: 'genesis_tree',
            devPath: '/abs/genesis/packages/tree',
          ),
        ],
      );
      final yaml = pubspecOverridesFor(abs, PubLinkContext.worktree);
      expect(yaml, contains("path: '/abs/genesis/packages/tree'"));
    });

    test('worktree + relative + NO devRoot throws (fail-closed — a broken '
        'override is worse than none)', () {
      expect(
        () => pubspecOverridesFor(config, PubLinkContext.worktree),
        throwsA(isA<StateError>()),
      );
    });

    test('worktree + relative + a RELATIVE devRoot throws too (absolutizing '
        'against a relative root yields a still-broken override)', () {
      expect(
        () => pubspecOverridesFor(
          config,
          PubLinkContext.worktree,
          devRoot: 'the_grid', // relative — would emit a relative "override"
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('YAML-hostile paths survive via single-quoting (spaces, colon-space, '
        'hash, embedded quote)', () {
      const hostile = PubLinkConfig(
        links: [
          PubLink(
            package: 'genesis_tree',
            devPath: "/home/dev/My Documents: a #dir/it's here",
          ),
        ],
      );
      final yaml = pubspecOverridesFor(hostile, PubLinkContext.dev)!;
      expect(
        yaml,
        contains("path: '/home/dev/My Documents: a #dir/it''s here'"),
        reason: 'single-quoted scalar; embedded quote doubled per YAML spec',
      );
    });

    test('no dev links → null in every non-stable context too', () {
      const pinsOnly = PubLinkConfig(
        links: [PubLink(package: 'genesis_tree', hosted: '^0.1.3')],
      );
      expect(pubspecOverridesFor(pinsOnly, PubLinkContext.dev), isNull);
      expect(
        pubspecOverridesFor(const PubLinkConfig(), PubLinkContext.dev),
        isNull,
      );
    });

    test('deterministic: links emit sorted by package', () {
      const two = PubLinkConfig(
        links: [
          PubLink(package: 'zeta', devPath: '/z'),
          PubLink(package: 'alpha', devPath: '/a'),
        ],
      );
      final yaml = pubspecOverridesFor(two, PubLinkContext.dev)!;
      expect(yaml.indexOf('alpha:'), lessThan(yaml.indexOf('zeta:')));
    });

    test('exact hosted versions are validated, sorted, and quoted', () {
      expect(pubspecOverridesForExactVersions(const {}), isNull);
      expect(
        pubspecOverridesForExactVersions(const {
          'grid_trajectory': '0.2.0-rc.3',
          'beads_dart': '0.2.0-rc.7',
        }),
        '# Generated by release declared-floors validation. Do not hand-edit.\n'
        'dependency_overrides:\n'
        "  beads_dart: '0.2.0-rc.7'\n"
        "  grid_trajectory: '0.2.0-rc.3'\n",
      );
      expect(
        () => pubspecOverridesForExactVersions(const {
          'grid_trajectory': '^0.2.0-rc.3',
        }),
        throwsFormatException,
      );
    });
  });

  group('DartLinkService — the UI-drivable lib layer (temp dirs)', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('grid-dart-link-');
    });

    tearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });

    File overridesFile() => File('${temp.path}/$kPubspecOverridesFile');

    test('applies a dev link: writes pubspec_overrides.yaml at the workspace '
        'root', () async {
      final outcome = await const DartLinkService().apply(
        metadata: _metadataWith(const [_genesisLink]),
        context: PubLinkContext.dev,
        workspaceDir: temp.path,
      );
      expect(outcome, isA<LinkApplied>());
      expect((outcome as LinkApplied).packages, ['genesis_tree']);
      expect(overridesFile().existsSync(), isTrue);
      expect(
        overridesFile().readAsStringSync(),
        contains("path: '../genesis/packages/tree'"),
      );
    });

    test('stable clears a previously GENERATED overrides file', () async {
      const service = DartLinkService();
      await service.apply(
        metadata: _metadataWith(const [_genesisLink]),
        context: PubLinkContext.dev,
        workspaceDir: temp.path,
      );
      expect(overridesFile().existsSync(), isTrue);

      final outcome = await service.apply(
        metadata: _metadataWith(const [_genesisLink]),
        context: PubLinkContext.stable,
        workspaceDir: temp.path,
      );
      expect(outcome, isA<LinkCleared>());
      expect((outcome as LinkCleared).removed, isTrue);
      expect(overridesFile().existsSync(), isFalse);
    });

    test('NEVER deletes a hand-authored pubspec_overrides.yaml (only the '
        'generated marker is removable)', () async {
      overridesFile().writeAsStringSync(
        'dependency_overrides:\n  mine:\n    path: ../mine\n',
      );
      final outcome = await const DartLinkService().apply(
        metadata: _metadataWith(const [_genesisLink]),
        context: PubLinkContext.stable,
        workspaceDir: temp.path,
      );
      expect((outcome as LinkCleared).removed, isFalse);
      expect(
        overridesFile().existsSync(),
        isTrue,
        reason: 'a file this domain did not generate is left alone',
      );
    });

    test('no grid.dart config → touches nothing', () async {
      final outcome = await const DartLinkService().apply(
        metadata: const {'gc.other': 'x'},
        context: PubLinkContext.dev,
        workspaceDir: temp.path,
      );
      expect(outcome, isA<LinkNoConfig>());
      expect(overridesFile().existsSync(), isFalse);
    });

    test('an incompatible envelope is REFUSED and touches nothing '
        '(fail-closed)', () async {
      final outcome = await const DartLinkService().apply(
        metadata: _metadataWith(const [_genesisLink], version: '9.9.9'),
        context: PubLinkContext.dev,
        workspaceDir: temp.path,
      );
      expect(outcome, isA<LinkRefused>());
      expect((outcome as LinkRefused).reason, contains('9.9.9'));
      expect(overridesFile().existsSync(), isFalse);
    });

    test('worktree + relative + no devRoot is REFUSED (not thrown, not '
        'written)', () async {
      final outcome = await const DartLinkService().apply(
        metadata: _metadataWith(const [_genesisLink]),
        context: PubLinkContext.worktree,
        workspaceDir: temp.path,
      );
      expect(outcome, isA<LinkRefused>());
      expect(overridesFile().existsSync(), isFalse);
    });

    test('the genesis_tree scenario end-to-end: a worktree apply yields the '
        'absolute-path override pub needs at any depth', () async {
      // The station's root checkout + a deep per-bead "worktree" under it.
      final devRoot = Directory('${temp.path}/the_grid')..createSync();
      final worktree = Directory(
        '${temp.path}/the_grid/.grid/worktrees/tg/tg-abc',
      )..createSync(recursive: true);

      final outcome = await const DartLinkService().apply(
        metadata: _metadataWith(const [_genesisLink]),
        context: PubLinkContext.worktree,
        workspaceDir: worktree.path,
        devRoot: devRoot.path,
      );
      expect(outcome, isA<LinkApplied>());
      final yaml = File(
        '${worktree.path}/$kPubspecOverridesFile',
      ).readAsStringSync();
      expect(
        yaml,
        contains("path: '${temp.path}/genesis/packages/tree'"),
        reason:
            'the ../genesis declaration absolutized against the dev '
            'root — resolvable from the deep worktree',
      );
    });

    test('a RELATIVE devRoot is REFUSED by the service (fail-closed, not a '
        'silently relative override)', () async {
      final outcome = await const DartLinkService().apply(
        metadata: _metadataWith(const [_genesisLink]),
        context: PubLinkContext.worktree,
        workspaceDir: temp.path,
        devRoot: 'the_grid',
      );
      expect(outcome, isA<LinkRefused>());
      expect(overridesFile().existsSync(), isFalse);
    });
  });

  group('DartLinkService.applySync — the synchronous counterpart (the '
      'ProcessCapability.spawn edge, which cannot await)', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('grid-dart-link-sync-');
    });

    tearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });

    File overridesFile() => File('${temp.path}/$kPubspecOverridesFile');

    test('applies a dev link exactly like apply() — writes '
        'pubspec_overrides.yaml at the workspace root', () {
      final outcome = const DartLinkService().applySync(
        metadata: _metadataWith(const [_genesisLink]),
        context: PubLinkContext.dev,
        workspaceDir: temp.path,
      );
      expect(outcome, isA<LinkApplied>());
      expect((outcome as LinkApplied).packages, ['genesis_tree']);
      expect(overridesFile().existsSync(), isTrue);
      expect(
        overridesFile().readAsStringSync(),
        contains("path: '../genesis/packages/tree'"),
      );
    });

    test('no envelope / empty links → no file; a stale GENERATED file is '
        'cleared', () {
      const service = DartLinkService();
      service.applySync(
        metadata: _metadataWith(const [_genesisLink]),
        context: PubLinkContext.dev,
        workspaceDir: temp.path,
      );
      expect(overridesFile().existsSync(), isTrue);

      // An envelope declaring NO dev-carrying links (empty list) → clears the
      // stale file (pubspecOverridesFor: dev.isEmpty ⇒ null ⇒ _clearSync).
      final outcome = service.applySync(
        metadata: _metadataWith(const []),
        context: PubLinkContext.worktree,
        workspaceDir: temp.path,
      );
      expect(outcome, isA<LinkCleared>());
      expect((outcome as LinkCleared).removed, isTrue);
      expect(overridesFile().existsSync(), isFalse);
    });

    test('no grid.dart on the bead at all touches nothing (does not probe a '
        'pre-existing file) — byte-identical to apply()', () {
      overridesFile().writeAsStringSync('# pre-existing, untouched\n');
      final outcome = const DartLinkService().applySync(
        metadata: const {'gc.other': 'x'},
        context: PubLinkContext.worktree,
        workspaceDir: temp.path,
      );
      expect(outcome, isA<LinkNoConfig>());
      expect(overridesFile().readAsStringSync(), '# pre-existing, untouched\n');
    });

    test('NEVER deletes a hand-authored pubspec_overrides.yaml', () {
      overridesFile().writeAsStringSync(
        'dependency_overrides:\n  mine:\n    path: ../mine\n',
      );
      final outcome = const DartLinkService().applySync(
        metadata: _metadataWith(const []),
        context: PubLinkContext.worktree,
        workspaceDir: temp.path,
      );
      expect((outcome as LinkCleared).removed, isFalse);
      expect(overridesFile().existsSync(), isTrue);
    });

    test('a breaking assets_version is refused WHOLE — never a half-applied '
        'file', () {
      final outcome = const DartLinkService().applySync(
        metadata: _metadataWith(const [_genesisLink], version: '9.9.9'),
        context: PubLinkContext.worktree,
        workspaceDir: temp.path,
        devRoot: temp.path,
      );
      expect(outcome, isA<LinkRefused>());
      expect((outcome as LinkRefused).reason, contains('9.9.9'));
      expect(overridesFile().existsSync(), isFalse);
    });

    test('the worktree scenario end-to-end: absolutizes a relative dev path '
        'against devRoot', () {
      final devRoot = Directory('${temp.path}/power_station')..createSync();
      final worktree = Directory(
        '${temp.path}/power_station/.grid/worktrees/tg/tg-abc',
      )..createSync(recursive: true);

      final outcome = const DartLinkService().applySync(
        metadata: _metadataWith(const [_genesisLink]),
        context: PubLinkContext.worktree,
        workspaceDir: worktree.path,
        devRoot: devRoot.path,
      );
      expect(outcome, isA<LinkApplied>());
      final yaml = File(
        '${worktree.path}/$kPubspecOverridesFile',
      ).readAsStringSync();
      expect(yaml, contains("path: '${temp.path}/genesis/packages/tree'"));
    });
  });

  group('DartCommand / dart link — the THIN exported Command', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('grid-dart-cmd-');
    });

    tearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });

    test('link is a subcommand of the dart umbrella (Pub subordinate to '
        'Dart)', () {
      final cmd = DartCommand();
      expect(cmd.name, 'dart');
      expect(cmd.subcommands.keys, contains('link'));
    });

    test(
      'parses flags and delegates to the service end-to-end (offline)',
      () async {
        final metadataFile = File('${temp.path}/bead-metadata.json')
          ..writeAsStringSync(jsonEncode(_metadataWith(const [_genesisLink])));

        final runner = CommandRunnerish();
        final code = await runner.run([
          'dart',
          'link',
          '--metadata',
          metadataFile.path,
          '--context',
          'dev',
          '--dir',
          temp.path,
        ]);
        expect(code, 0);
        expect(
          File('${temp.path}/$kPubspecOverridesFile').existsSync(),
          isTrue,
        );
      },
    );

    test('a refused envelope exits 1 (fail-closed surfaces)', () async {
      final metadataFile = File('${temp.path}/bead-metadata.json')
        ..writeAsStringSync(
          jsonEncode(_metadataWith(const [_genesisLink], version: '9.9.9')),
        );
      final code = await CommandRunnerish().run([
        'dart',
        'link',
        '--metadata',
        metadataFile.path,
        '--context',
        'dev',
        '--dir',
        temp.path,
      ]);
      expect(code, 1);
    });

    test('a missing metadata file exits 64 (usage)', () async {
      final code = await CommandRunnerish().run([
        'dart',
        'link',
        '--metadata',
        '${temp.path}/nope.json',
        '--context',
        'dev',
        '--dir',
        temp.path,
      ]);
      expect(code, 64);
    });
  });
}

/// A minimal runner hosting [DartCommand] exactly the way a station app would
/// (`..addCommand(DartCommand())` — the assembles-the-Commands-it-wants model).
class CommandRunnerish {
  Future<int> run(List<String> args) async {
    final runner = CommandRunner<int>('t', 'test station')
      ..addCommand(DartCommand());
    return await runner.run(args) ?? 0;
  }
}
