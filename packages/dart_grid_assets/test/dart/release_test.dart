// The DART-domain RELEASE service + exported Command — the deterministic half
// of the coupled `release` skill+command (ADR-0001). Pins the version
// discipline, tag convention, scrub gate, publish order, and the two IO edges
// (dry-run PROCESS + pub.dev FETCH), the latter via injected Fakes (Fakes, not
// mocks) so the whole surface tests offline.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_grid_assets/dart_grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A Fake [ProcessRunner]: records the last argv and returns canned output.
class _FakeProcess {
  _FakeProcess(ProcessResult result) : _results = [result];
  _FakeProcess.queue(List<ProcessResult> results) : _results = [...results];

  final List<ProcessResult> _results;
  final calls =
      <
        ({String executable, List<String> arguments, String? workingDirectory})
      >[];

  /// The generated `pubspec_overrides.yaml` as it stood at each call — the
  /// throwaway dir is deleted before the test can read it back.
  final overrideSnapshots = <String?>[];

  String? get executable => calls.isEmpty ? null : calls.last.executable;
  List<String>? get arguments => calls.isEmpty ? null : calls.last.arguments;
  String? get workingDirectory =>
      calls.isEmpty ? null : calls.last.workingDirectory;

  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    calls.add((
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
    ));
    final override = workingDirectory == null
        ? null
        : File(p.join(workingDirectory, 'pubspec_overrides.yaml'));
    overrideSnapshots.add(
      override != null && override.existsSync()
          ? override.readAsStringSync()
          : null,
    );
    if (_results.isEmpty) {
      throw StateError(
        'unexpected process call: $executable ${arguments.join(' ')}',
      );
    }
    return _results.removeAt(0);
  }
}

/// A Fake [HttpGetter]: records the requested URL and returns a canned fetch.
class _FakeHttp {
  _FakeHttp(this.fetch);
  final HttpFetch fetch;
  Uri? requested;
  Future<HttpFetch> call(Uri url) async {
    requested = url;
    return fetch;
  }
}

/// Writes a two-member pub workspace: a candidate that uses a symbol from its
/// sibling, declaring [floor] as the sibling's constraint. File setup only —
/// it never runs dart and never touches the network.
({Directory root, Directory candidate}) _writeUnitFloorWorkspace(String floor) {
  final root = Directory.systemTemp.createTempSync('declared-floor-unit-');
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
    'name: declared_floor_unit_workspace\n'
    'publish_to: none\n'
    'environment:\n'
    '  sdk: ^3.11.0\n'
    'workspace:\n'
    '  - packages/candidate\n'
    '  - packages/grid_trajectory\n',
  );
  final sibling = Directory(p.join(root.path, 'packages', 'grid_trajectory'))
    ..createSync(recursive: true);
  File(p.join(sibling.path, 'pubspec.yaml')).writeAsStringSync(
    'name: grid_trajectory\n'
    'version: 0.2.0-rc.4\n'
    'resolution: workspace\n'
    'environment:\n'
    '  sdk: ^3.11.0\n',
  );
  final candidate = Directory(p.join(root.path, 'packages', 'candidate'))
    ..createSync(recursive: true);
  File(p.join(candidate.path, 'pubspec.yaml')).writeAsStringSync(
    'name: declared_floor_unit_candidate\n'
    'version: 0.1.0\n'
    'publish_to: none\n'
    'resolution: workspace\n'
    'environment:\n'
    '  sdk: ^3.11.0\n'
    'dependencies:\n'
    '  grid_trajectory: $floor\n',
  );
  final lib = Directory(p.join(candidate.path, 'lib'))
    ..createSync(recursive: true);
  File(
    p.join(lib.path, 'candidate.dart'),
  ).writeAsStringSync('Object? classify() => StepFailureClass.noResult;\n');
  return (root: root, candidate: candidate);
}

void main() {
  group('planVersion — the pre-1.0 version discipline (publishing.md)', () {
    const service = ReleaseService();

    test(
      'docs/additive/fix all bump PATCH; none flags a breaking CHANGELOG',
      () {
        for (final change in [
          ReleaseChange.docs,
          ReleaseChange.additive,
          ReleaseChange.fix,
        ]) {
          final plan = service.planVersion(current: '0.1.4', change: change);
          expect(plan.next.toString(), '0.1.5', reason: '$change -> patch');
          expect(plan.requiresBreakingChangelog, isFalse);
        }
      },
    );

    test(
      'pre-1.0 breaking bumps MINOR (escaping ^0.1.0) + flags the CHANGELOG',
      () {
        final plan = service.planVersion(
          current: '0.1.4',
          change: ReleaseChange.breaking,
        );
        expect(plan.next.toString(), '0.2.0');
        expect(plan.requiresBreakingChangelog, isTrue);
      },
    );

    test('from 1.0 a breaking change bumps MAJOR', () {
      final plan = service.planVersion(
        current: '1.2.3',
        change: ReleaseChange.breaking,
      );
      expect(plan.next.toString(), '2.0.0');
    });

    test(
      'rc plans the next breaking stable base as rc.1, then increments rc.N',
      () {
        final first = service.planVersion(
          current: '0.1.4',
          change: ReleaseChange.rc,
        );
        expect(first.next.toString(), '0.2.0-rc.1');
        expect(first.requiresBreakingChangelog, isTrue);

        final second = service.planVersion(
          current: '0.2.0-rc.1',
          change: ReleaseChange.rc,
        );
        expect(second.next.toString(), '0.2.0-rc.2');
      },
    );

    test(
      'a non-semver current is a LOUD ArgumentError (never a guessed bump)',
      () {
        expect(
          () => service.planVersion(
            current: 'not-a-version',
            change: ReleaseChange.fix,
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('toJson carries the structured contract the skill parses', () {
      final json = service
          .planVersion(current: '0.1.4', change: ReleaseChange.breaking)
          .toJson();
      expect(json, {
        'current': '0.1.4',
        'next': '0.2.0',
        'change': 'breaking',
        'requiresBreakingChangelog': true,
      });
    });
  });

  group('tagFor — the per-package tag convention', () {
    test(
      'composes <pub-name>-v<version> (publishing.md: genesis_tree-v0.1.5)',
      () {
        expect(
          const ReleaseService().tagFor(
            package: 'genesis_tree',
            version: '0.1.5',
          ),
          'genesis_tree-v0.1.5',
        );
        expect(
          const ReleaseService().tagFor(
            package: 'grid_engine',
            version: '0.3.0-rc.1',
          ),
          'grid_engine-v0.3.0-rc.1',
        );
      },
    );
  });

  group('private tags and consumer validation', () {
    test(
      'createGitTag cuts a git tag through the injected process seam',
      () async {
        final fake = _FakeProcess(ProcessResult(0, 0, '', ''));
        final result = await ReleaseService(
          runProcess: fake.call,
        ).createGitTag(repoDir: '/repo', tag: 'grid_engine-v0.3.0-rc.1');
        expect(result.created, isTrue);
        expect(fake.executable, 'git');
        expect(fake.arguments, ['tag', 'grid_engine-v0.3.0-rc.1']);
        expect(fake.workingDirectory, '/repo');
      },
    );

    test(
      'validateConsumers pins rc refs and reports per-consumer results',
      () async {
        final pass = await Directory.systemTemp.createTemp('release-pass-');
        final fail = await Directory.systemTemp.createTemp('release-fail-');
        addTearDown(() => pass.delete(recursive: true));
        addTearDown(() => fail.delete(recursive: true));
        final fake = _FakeProcess.queue([
          ProcessResult(0, 0, 'analyze ok', ''),
          ProcessResult(1, 0, 'test ok', ''),
          ProcessResult(2, 1, '', 'analyze failed'),
        ]);
        final report = await ReleaseService(runProcess: fake.call)
            .validateConsumers(
              rcTag: 'grid_engine-v0.3.0-rc.1',
              consumers: [
                ReleaseConsumer(
                  name: 'space_station',
                  directory: pass.path,
                  links: const [
                    PubLink(
                      package: 'grid_engine',
                      gitUrl: 'git@github.com:memento-engineering/the_grid.git',
                    ),
                  ],
                ),
                ReleaseConsumer(
                  name: 'power_station',
                  directory: fail.path,
                  links: const [
                    PubLink(
                      package: 'grid_engine',
                      gitUrl: 'git@github.com:memento-engineering/the_grid.git',
                    ),
                  ],
                ),
              ],
            );

        expect(report.rcTag, 'grid_engine-v0.3.0-rc.1');
        expect(report.allPassed, isFalse);
        expect(report.results.map((result) => result.passed), [true, false]);
        expect(report.results.last.testExitCode, isNull);
        expect(
          File('${pass.path}/pubspec_overrides.yaml').readAsStringSync(),
          contains("ref: 'grid_engine-v0.3.0-rc.1'"),
        );
        expect(fake.calls, hasLength(3));
        expect(fake.calls[0].arguments, ['analyze']);
        expect(fake.calls[0].workingDirectory, pass.path);
        expect(fake.calls[1].arguments, ['test']);
        expect(fake.calls[1].workingDirectory, pass.path);
        expect(fake.calls[2].arguments, ['analyze']);
        expect(fake.calls[2].workingDirectory, fail.path);
      },
    );

    test(
      'promoteTag refuses before git unless every consumer passed',
      () async {
        final fake = _FakeProcess(ProcessResult(0, 0, '', ''));
        final failed = ConsumerValidationReport(
          rcTag: 'grid_engine-v0.3.0-rc.1',
          results: const [
            ConsumerValidationResult(
              name: 'space_station',
              directory: '/space',
              overridePath: '/space/pubspec_overrides.yaml',
              analyzeExitCode: 1,
              testExitCode: null,
              stdout: '',
              stderr: 'failed',
            ),
          ],
        );
        expect(
          () => ReleaseService(runProcess: fake.call).promoteTag(
            repoDir: '/repo',
            stableTag: 'grid_engine-v0.3.0',
            validation: failed,
          ),
          throwsA(isA<StateError>()),
        );
        expect(fake.calls, isEmpty);
      },
    );

    test('promoteTag cuts the stable tag after all consumers pass', () async {
      final fake = _FakeProcess(ProcessResult(0, 0, '', ''));
      final passed = ConsumerValidationReport(
        rcTag: 'grid_engine-v0.3.0-rc.1',
        results: const [
          ConsumerValidationResult(
            name: 'space_station',
            directory: '/space',
            overridePath: '/space/pubspec_overrides.yaml',
            analyzeExitCode: 0,
            testExitCode: 0,
            stdout: '',
            stderr: '',
          ),
        ],
      );
      final result = await ReleaseService(runProcess: fake.call).promoteTag(
        repoDir: '/repo',
        stableTag: 'grid_engine-v0.3.0',
        validation: passed,
      );
      expect(result.created, isTrue);
      expect(fake.executable, 'git');
      expect(fake.arguments, ['tag', 'grid_engine-v0.3.0']);
      expect(fake.workingDirectory, '/repo');
    });
  });

  group('validateDeclaredFloors — the producer-side floors leg', () {
    test(
      'exact-pins siblings, analyzes a copy, reports, and cleans up',
      () async {
        final fixture = _writeUnitFloorWorkspace('^0.2.0-rc.3');
        addTearDown(() => fixture.root.delete(recursive: true));
        final fake = _FakeProcess.queue([
          ProcessResult(1, 0, 'pub get ok', ''),
          ProcessResult(2, 1, '', "There's no constant named 'noResult'."),
        ]);
        final result = await ReleaseService(
          runProcess: fake.call,
        ).validateDeclaredFloors(packageDir: fixture.candidate.path);

        expect(fake.calls.map((call) => call.arguments), [
          ['pub', 'get'],
          ['analyze'],
        ]);
        expect(
          fake.calls.first.workingDirectory,
          isNot(fixture.candidate.path),
        );
        expect(
          fake.overrideSnapshots.first,
          contains("grid_trajectory: '0.2.0-rc.3'"),
        );
        expect(result.passed, isFalse);
        expect(result.pins.single.toJson(), {
          'package': 'grid_trajectory',
          'declaredConstraint': '^0.2.0-rc.3',
          'floor': '0.2.0-rc.3',
        });
        expect(result.message, contains('noResult'));
        expect(result.message, contains('grid_trajectory@0.2.0-rc.3'));
        expect(
          Directory(fake.calls.first.workingDirectory!).existsSync(),
          isFalse,
        );
      },
    );

    test('the copy resolves STANDALONE, never through the workspace', () async {
      final fixture = _writeUnitFloorWorkspace('^0.2.0-rc.3');
      addTearDown(() => fixture.root.delete(recursive: true));
      String? copiedPubspec;
      final result = await ReleaseService(
        runProcess: (executable, arguments, {workingDirectory}) async {
          copiedPubspec ??= File(
            p.join(workingDirectory!, 'pubspec.yaml'),
          ).readAsStringSync();
          return ProcessResult(0, 0, '', '');
        },
      ).validateDeclaredFloors(packageDir: fixture.candidate.path);

      expect(copiedPubspec, isNot(contains('resolution: workspace')));
      expect(copiedPubspec, contains('grid_trajectory: ^0.2.0-rc.3'));
      expect(result.passed, isTrue);
      expect(result.message, contains('declared-floor validation passed'));
    });

    test('skips analyze when pub get fails', () async {
      final fixture = _writeUnitFloorWorkspace('^0.2.0-rc.3');
      addTearDown(() => fixture.root.delete(recursive: true));
      final fake = _FakeProcess(ProcessResult(1, 1, '', 'resolution failed'));
      final result = await ReleaseService(
        runProcess: fake.call,
      ).validateDeclaredFloors(packageDir: fixture.candidate.path);

      expect(fake.calls, hasLength(1));
      expect(fake.calls.single.arguments, ['pub', 'get']);
      expect(result.analyzeExitCode, isNull);
      expect(result.passed, isFalse);
      expect(result.message, contains('resolution failed'));
    });

    test('a sibling with no inclusive floor is a LOUD refusal', () async {
      final fixture = _writeUnitFloorWorkspace('any');
      addTearDown(() => fixture.root.delete(recursive: true));
      final fake = _FakeProcess.queue(const []);
      await expectLater(
        ReleaseService(
          runProcess: fake.call,
        ).validateDeclaredFloors(packageDir: fixture.candidate.path),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('grid_trajectory'), contains('inclusive')),
          ),
        ),
      );
      expect(fake.calls, isEmpty);
    });
  });

  group('scrub — the internal-ref gate (line-level A2UI exemption)', () {
    const service = ReleaseService();

    test('scrubContent ignores generic register APIs and prose', () {
      const content =
          'registerServiceExtension(name, callback);\n'
          'developer.registerExtension(method, handler);\n'
          '_registerExtension();\n'
          'bool _persistentRegistered = true;\n'
          'extensions are registered through ExtensionContext\n';
      expect(service.scrubContent(content), isEmpty);
    });

    test('scrubContent permits vocabulary in public Dart source', () {
      const content =
          '/// The COMPUTE asset domain (ADR-0011 D2/D3, M6 Track D).\n'
          '  /// PinDiff posture, ADR-0000 A9.\n'
          '// Implementation rationale: ADR-0002 D3/D4.\n'
          "throw FormatException('See ADR-0000 A13');\n"
          "const prompt = 'The register cites inherited amendment A37.';\n"
          "const beadType = 'spike';\n";
      expect(
        service.scrubContent(content, file: 'lib/src/example.dart'),
        isEmpty,
      );
    });

    test('scrubContent rejects planted working-document vocabulary', () {
      const content =
          'handoff: revisit ADR-0011 D2/D3 before release\n'
          'scratch note: reconcile A37 with the implementation\n'
          'the register says so\n'
          'Decision Register entry\n'
          'decision-register reference\n'
          'a spike we ran\n';
      final hits = service.scrubContent(content, file: 'HANDOFF.md');
      expect(hits.map((hit) => hit.match).toList(), [
        'ADR-0',
        'A37',
        'the register',
        'Decision Register',
        'decision-register',
        'spike',
      ]);
      expect(hits.map((hit) => hit.line).toList(), [1, 2, 3, 4, 5, 6]);
      expect(hits.every((hit) => hit.file == 'HANDOFF.md'), isTrue);
    });

    test('scrubDir reports the current grid_assets package clean', () {
      final result = service.scrubDir('../grid_assets');
      expect(result.clean, isTrue, reason: result.hits.join('\n'));
      expect(result.filesScanned, greaterThan(0));
      expect(result.hits, isEmpty);
    });

    test('scrubContent permits standalone Dartdoc and preserves A2UI', () {
      const content =
          '/// The COMPUTE asset domain (ADR-0011 D2/D3).\n'
          '  /// PinDiff posture, ADR-0000 A9 and inherited A37.\n'
          'the A2UI wire (A17 is exempt because the line names A2UI)\n';
      expect(service.scrubContent(content), isEmpty);
    });

    test(
      'scrubDir accepts register APIs and rejects a decision-register leak',
      () async {
        final clean = await Directory.systemTemp.createTemp('release-clean-');
        addTearDown(() => clean.delete(recursive: true));
        File(
          '${clean.path}/README.md',
        ).writeAsStringSync('# Extensions\nExtensions are registered.\n');
        File(
          '${clean.path}/CHANGELOG.md',
        ).writeAsStringSync('## 0.1.0\nRegister VM service support.\n');
        Directory('${clean.path}/lib').createSync();
        File('${clean.path}/lib/binding.dart').writeAsStringSync(
          'void _registerExtension() => developer.registerExtension();\n',
        );
        final cleanResult = service.scrubDir(clean.path);
        expect(cleanResult.clean, isTrue);
        expect(cleanResult.filesScanned, 3);
        expect(cleanResult.hits, isEmpty);

        final leaking = await Directory.systemTemp.createTemp('release-leak-');
        addTearDown(() => leaking.delete(recursive: true));
        File(
          '${leaking.path}/README.md',
        ).writeAsStringSync('# Package\nSee the decision register.\n');
        final leakingResult = service.scrubDir(leaking.path);
        expect(leakingResult.clean, isFalse);
        expect(leakingResult.filesScanned, 1);
        expect(leakingResult.hits, hasLength(1));
        expect(leakingResult.hits.single.match, 'decision register');
      },
    );
  });

  group('publishOrder — the dependency-first topological sort', () {
    const service = ReleaseService();

    test('deps publish before dependents, ties broken alphabetically', () {
      final order = service.publishOrder({
        'genesis_consent': ['genesis_dialogue'],
        'genesis_dialogue': ['genesis_perception'],
        'genesis_perception': ['genesis_tree'],
        'genesis_tree': <String>[],
      });
      expect(order.order, [
        'genesis_tree',
        'genesis_perception',
        'genesis_dialogue',
        'genesis_consent',
      ]);
    });

    test('an external (out-of-set) dep is ignored', () {
      final order = service.publishOrder({
        'a': ['meta'], // external — not a node
        'b': ['a'],
      });
      expect(order.order, ['a', 'b']);
    });

    test('a cycle is a LOUD StateError (never a partial order)', () {
      expect(
        () => service.publishOrder({
          'a': ['b'],
          'b': ['a'],
        }),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('dryRun — the --dry-run gate over an injected process seam', () {
    test(
      'exit 0 + "0 warnings" is clean; the argv is the pub dry-run',
      () async {
        final fake = _FakeProcess(
          ProcessResult(0, 0, 'Package has 0 warnings.', ''),
        );
        final result = await ReleaseService(
          runProcess: fake.call,
        ).dryRun(packageDir: '/pkg', package: 'genesis_tree');
        expect(result.clean, isTrue);
        expect(result.warningCount, 0);
        expect(fake.executable, 'dart');
        expect(fake.arguments, ['pub', 'publish', '--dry-run']);
        expect(fake.workingDirectory, '/pkg');
      },
    );

    test('warnings make it unclean and are collected as * bullets', () async {
      final fake = _FakeProcess(
        ProcessResult(
          0,
          65,
          'Package validation found the following potential issues:\n'
              '* Line 3: something\n* Line 9: another\n'
              'Package has 2 warnings.',
          '',
        ),
      );
      final result = await ReleaseService(
        runProcess: fake.call,
      ).dryRun(packageDir: '/pkg');
      expect(result.clean, isFalse);
      expect(result.warningCount, 2);
      expect(result.warnings, ['* Line 3: something', '* Line 9: another']);
    });

    test('a hidden overlay source directory makes the gate unclean', () async {
      final temp = Directory.systemTemp.createTempSync('release_overlay_');
      addTearDown(() => temp.deleteSync(recursive: true));
      Directory(
        '${temp.path}/extension/station_overlay/.claude/skills',
      ).createSync(recursive: true);
      final result = await ReleaseService(
        runProcess: _FakeProcess(
          ProcessResult(0, 0, 'Package has 0 warnings.', ''),
        ).call,
      ).dryRun(packageDir: temp.path);
      expect(result.clean, isFalse);
      expect(result.warningCount, 1);
      expect(result.warnings.single, contains('.claude'));

      Directory(
        '${temp.path}/extension/station_overlay/.claude',
      ).renameSync('${temp.path}/extension/station_overlay/claude');
      final visible = await ReleaseService(
        runProcess: _FakeProcess(
          ProcessResult(0, 0, 'Package has 0 warnings.', ''),
        ).call,
      ).dryRun(packageDir: temp.path);
      expect(visible.clean, isTrue);
    });
  });

  group('poll — the pub.dev versions probe over an injected fetch seam', () {
    test(
      'a listed prerelease is published even when latest remains stable',
      () async {
        final fake = _FakeHttp(
          const HttpFetch(
            statusCode: 200,
            body:
                '{"name":"beads_dart","latest":{"version":"0.1.1"},'
                '"versions":[{"version":"0.1.0"},{"version":"0.1.1"},'
                '{"version":"0.2.0-rc.1"}]}',
          ),
        );
        final result = await ReleaseService(
          httpGet: fake.call,
        ).poll(package: 'beads_dart', version: '0.2.0-rc.1');
        expect(result.isPublished, isTrue);
        expect(result.latest, '0.1.1');
        expect(
          fake.requested.toString(),
          'https://pub.dev/api/packages/beads_dart',
        );
      },
    );

    test('a listed stable version is published', () async {
      final fake = _FakeHttp(
        const HttpFetch(
          statusCode: 200,
          body:
              '{"latest":{"version":"0.1.5"},'
              '"versions":[{"version":"0.1.4"},{"version":"0.1.5"}]}',
        ),
      );
      final result = await ReleaseService(
        httpGet: fake.call,
      ).poll(package: 'genesis_tree', version: '0.1.5');
      expect(result.isPublished, isTrue);
      expect(result.latest, '0.1.5');
    });

    test('unlisted stable and prerelease versions are unpublished', () async {
      for (final wanted in ['0.1.6', '0.2.0-rc.1']) {
        final result = await ReleaseService(
          httpGet: _FakeHttp(
            const HttpFetch(
              statusCode: 200,
              body:
                  '{"latest":{"version":"0.1.5"},'
                  '"versions":[{"version":"0.1.4"},'
                  '{"version":"0.1.5"}]}',
            ),
          ).call,
        ).poll(package: 'genesis_tree', version: wanted);
        expect(result.isPublished, isFalse, reason: wanted);
        expect(result.latest, '0.1.5', reason: wanted);
      }
    });

    test(
      'a 404 (unpublished package) yields a null latest, never a crash',
      () async {
        final fake = _FakeHttp(
          const HttpFetch(statusCode: 404, body: 'not found'),
        );
        final result = await ReleaseService(
          httpGet: fake.call,
        ).poll(package: 'nope', version: '0.1.0');
        expect(result.latest, isNull);
        expect(result.isPublished, isFalse);
      },
    );
  });

  group('DartCommand / dart release — the THIN exported Command', () {
    test(
      'release is a subcommand of the dart umbrella, with the eight ops',
      () {
        final release = DartCommand().subcommands['release']!;
        expect(
          release.subcommands.keys,
          containsAll([
            'plan',
            'tag',
            'validate-consumers',
            'promote',
            'scrub',
            'order',
            'dry-run',
            'poll',
          ]),
        );
      },
    );

    test('release plan --json emits the version plan + tag', () async {
      final buf = StringBuffer();
      final runner = CommandRunner<int>('t', 'test')
        ..addCommand(ReleaseCommand(out: buf));
      final code = await runner.run([
        'release',
        'plan',
        '--package',
        'genesis_tree',
        '--current',
        '0.1.4',
        '--change',
        'breaking',
        '--json',
      ]);
      expect(code, 0);
      final json = jsonDecode(buf.toString().trim()) as Map<String, dynamic>;
      expect(json['next'], '0.2.0');
      expect(json['tag'], 'genesis_tree-v0.2.0');
      expect(json['requiresBreakingChangelog'], true);
    });

    test('release plan --change rc --json emits an rc tag', () async {
      final buf = StringBuffer();
      final runner = CommandRunner<int>('t', 'test')
        ..addCommand(ReleaseCommand(out: buf));
      final code = await runner.run([
        'release',
        'plan',
        '--package',
        'grid_engine',
        '--current',
        '0.1.4',
        '--change',
        'rc',
        '--json',
      ]);
      expect(code, 0);
      final json = jsonDecode(buf.toString().trim()) as Map<String, dynamic>;
      expect(json['next'], '0.2.0-rc.1');
      expect(json['tag'], 'grid_engine-v0.2.0-rc.1');
      expect(json['requiresBreakingChangelog'], true);
    });

    test('release tag --json emits the private tag result', () async {
      final fake = _FakeProcess(ProcessResult(0, 0, '', ''));
      final buf = StringBuffer();
      final runner = CommandRunner<int>('t', 'test')
        ..addCommand(
          ReleaseCommand(
            service: ReleaseService(runProcess: fake.call),
            out: buf,
          ),
        );
      final code = await runner.run([
        'release',
        'tag',
        '--repo-dir',
        '/repo',
        '--tag',
        'grid_engine-v0.3.0-rc.1',
        '--json',
      ]);
      expect(code, 0);
      final json = jsonDecode(buf.toString().trim()) as Map<String, dynamic>;
      expect(json['created'], true);
      expect(json['tag'], 'grid_engine-v0.3.0-rc.1');
      expect(fake.arguments, ['tag', 'grid_engine-v0.3.0-rc.1']);
    });

    test(
      'release validate-consumers --json emits per-consumer results',
      () async {
        final temp = await Directory.systemTemp.createTemp('release-consumer-');
        addTearDown(() => temp.delete(recursive: true));
        final manifest = File('${temp.path}/consumers.json')
          ..writeAsStringSync(
            jsonEncode({
              'consumers': [
                {
                  'name': 'space_station',
                  'directory': temp.path,
                  'links': [
                    {
                      'package': 'grid_engine',
                      'git_url':
                          'git@github.com:memento-engineering/the_grid.git',
                    },
                  ],
                },
              ],
            }),
          );
        final fake = _FakeProcess.queue([
          ProcessResult(0, 0, 'analyze ok', ''),
          ProcessResult(1, 0, 'test ok', ''),
        ]);
        final buf = StringBuffer();
        final runner = CommandRunner<int>('t', 'test')
          ..addCommand(
            ReleaseCommand(
              service: ReleaseService(runProcess: fake.call),
              out: buf,
            ),
          );
        final code = await runner.run([
          'release',
          'validate-consumers',
          '--rc-tag',
          'grid_engine-v0.3.0-rc.1',
          '--manifest',
          manifest.path,
          '--json',
        ]);
        expect(code, 0);
        final json = jsonDecode(buf.toString().trim()) as Map<String, dynamic>;
        expect(json['allPassed'], true);
        expect(json['results'], hasLength(1));
        expect((json['results'] as List).single['name'], 'space_station');
        expect(
          File('${temp.path}/pubspec_overrides.yaml').readAsStringSync(),
          contains("ref: 'grid_engine-v0.3.0-rc.1'"),
        );
      },
    );

    test(
      'release promote refuses failed validation before running git',
      () async {
        final temp = await Directory.systemTemp.createTemp('release-promote-');
        addTearDown(() => temp.delete(recursive: true));
        final validation = File('${temp.path}/validation.json')
          ..writeAsStringSync(
            jsonEncode(
              ConsumerValidationReport(
                rcTag: 'grid_engine-v0.3.0-rc.1',
                results: const [
                  ConsumerValidationResult(
                    name: 'space_station',
                    directory: '/space',
                    overridePath: '/space/pubspec_overrides.yaml',
                    analyzeExitCode: 1,
                    testExitCode: null,
                    stdout: '',
                    stderr: 'failed',
                  ),
                ],
              ).toJson(),
            ),
          );
        final fake = _FakeProcess(ProcessResult(0, 0, '', ''));
        final runner = CommandRunner<int>('t', 'test')
          ..addCommand(
            ReleaseCommand(
              service: ReleaseService(runProcess: fake.call),
              out: StringBuffer(),
              err: StringBuffer(),
            ),
          );
        final code = await runner.run([
          'release',
          'promote',
          '--repo-dir',
          '/repo',
          '--stable-tag',
          'grid_engine-v0.3.0',
          '--validation',
          validation.path,
          '--json',
        ]);
        expect(code, 1);
        expect(fake.calls, isEmpty);
      },
    );

    test('release order --json emits the resolved sequence', () async {
      final temp = await Directory.systemTemp.createTemp('release-order-');
      addTearDown(() => temp.delete(recursive: true));
      final manifest = File('${temp.path}/deps.json')
        ..writeAsStringSync(
          '{"genesis_perception":["genesis_tree"],"genesis_tree":[]}',
        );
      final buf = StringBuffer();
      final runner = CommandRunner<int>('t', 'test')
        ..addCommand(ReleaseCommand(out: buf));
      final code = await runner.run([
        'release',
        'order',
        '--manifest',
        manifest.path,
        '--json',
      ]);
      expect(code, 0);
      final json = jsonDecode(buf.toString().trim()) as Map<String, dynamic>;
      expect(json['order'], ['genesis_tree', 'genesis_perception']);
    });

    test('release dry-run --json renders the injected gate verdict', () async {
      final temp = await Directory.systemTemp.createTemp('release-dry-');
      addTearDown(() => temp.delete(recursive: true));
      final fake = _FakeProcess(
        ProcessResult(0, 0, 'Package has 0 warnings.', ''),
      );
      final buf = StringBuffer();
      final runner = CommandRunner<int>('t', 'test')
        ..addCommand(
          ReleaseCommand(
            service: ReleaseService(runProcess: fake.call),
            out: buf,
          ),
        );
      final code = await runner.run([
        'release',
        'dry-run',
        '--dir',
        temp.path,
        '--json',
      ]);
      expect(code, 0);
      final json = jsonDecode(buf.toString().trim()) as Map<String, dynamic>;
      expect(json['clean'], true);
    });

    test('release poll --json renders the injected pub.dev verdict', () async {
      final fake = _FakeHttp(
        const HttpFetch(
          statusCode: 200,
          body:
              '{"latest":{"version":"0.1.5"},'
              '"versions":[{"version":"0.1.5"}]}',
        ),
      );
      final buf = StringBuffer();
      final runner = CommandRunner<int>('t', 'test')
        ..addCommand(
          ReleaseCommand(
            service: ReleaseService(httpGet: fake.call),
            out: buf,
          ),
        );
      final code = await runner.run([
        'release',
        'poll',
        '--package',
        'genesis_tree',
        '--version',
        '0.1.5',
        '--json',
      ]);
      expect(code, 0);
      final json = jsonDecode(buf.toString().trim()) as Map<String, dynamic>;
      expect(json, {
        'package': 'genesis_tree',
        'wanted': '0.1.5',
        'latest': '0.1.5',
        'isPublished': true,
      });
    });

    test('scrub --dir on a missing dir exits 64 (usage)', () async {
      final runner = CommandRunner<int>('t', 'test')
        ..addCommand(ReleaseCommand(out: StringBuffer(), err: StringBuffer()));
      final code = await runner.run([
        'release',
        'scrub',
        '--dir',
        '/no/such/dir',
        '--json',
      ]);
      expect(code, 64);
    });
  });
}
