// The DART-domain RELEASE service + exported Command — the deterministic half
// of the coupled `release` skill+command (ADR-0001). Pins the version
// discipline, tag convention, scrub gate, publish order, and the two IO edges
// (dry-run PROCESS + pub.dev FETCH), the latter via injected Fakes (Fakes, not
// mocks) so the whole surface tests offline.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_grid_assets/dart_grid_assets.dart';
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

  group('scrub — the internal-ref gate (line-level A2UI exemption)', () {
    const service = ReleaseService();

    test(
      'scrubContent flags ADR/register/bare-A<n>/spike; exempts an A2UI line',
      () {
        const content =
            'clean line\n'
            'see ADR-5 for the design\n'
            'the register says so\n'
            'this predates A42\n'
            'a spike we ran\n'
            'the A2UI wire (A17 here is exempt because the line names A2UI)\n';
        final hits = service.scrubContent(content);
        expect(hits.map((h) => h.match).toList(), [
          'ADR-5',
          'register',
          'A42',
          'spike',
        ]);
        expect(hits.map((h) => h.line).toList(), [2, 3, 4, 5]);
        expect(
          hits.any((h) => h.text.contains('A2UI')),
          isFalse,
          reason: 'the A2UI line is exempt WHOLE, even carrying A17',
        );
      },
    );

    test('scrubDir scans README/CHANGELOG/lib; a clean pkg is clean', () async {
      final temp = await Directory.systemTemp.createTemp('release-scrub-');
      addTearDown(() => temp.delete(recursive: true));
      File('${temp.path}/README.md').writeAsStringSync('# ok\nno refs here\n');
      File(
        '${temp.path}/CHANGELOG.md',
      ).writeAsStringSync('## 0.1.0\nsee ADR-1\n');
      Directory('${temp.path}/lib').createSync();
      File(
        '${temp.path}/lib/a.dart',
      ).writeAsStringSync('/// a spike note\nclass A {}\n');
      final result = service.scrubDir(temp.path);
      expect(result.clean, isFalse);
      expect(result.filesScanned, 3);
      expect(result.hits.map((h) => h.file).toSet(), {
        'CHANGELOG.md',
        'lib/a.dart',
      });

      final clean = await Directory.systemTemp.createTemp('release-clean-');
      addTearDown(() => clean.delete(recursive: true));
      File(
        '${clean.path}/README.md',
      ).writeAsStringSync('# genesis_tree\nA keyed-reconcile engine.\n');
      expect(service.scrubDir(clean.path).clean, isTrue);
    });
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
  });

  group(
    'poll — the pub.dev latest-version probe over an injected fetch seam',
    () {
      test(
        'wanted == latest reports isPublished; the URL is the pub.dev API',
        () async {
          final fake = _FakeHttp(
            const HttpFetch(
              statusCode: 200,
              body: '{"name":"genesis_tree","latest":{"version":"0.1.5"}}',
            ),
          );
          final result = await ReleaseService(
            httpGet: fake.call,
          ).poll(package: 'genesis_tree', version: '0.1.5');
          expect(result.isPublished, isTrue);
          expect(result.latest, '0.1.5');
          expect(
            fake.requested.toString(),
            'https://pub.dev/api/packages/genesis_tree',
          );
        },
      );

      test('an older latest is not-yet-published', () async {
        final fake = _FakeHttp(
          const HttpFetch(
            statusCode: 200,
            body: '{"latest":{"version":"0.1.4"}}',
          ),
        );
        final result = await ReleaseService(
          httpGet: fake.call,
        ).poll(package: 'genesis_tree', version: '0.1.5');
        expect(result.isPublished, isFalse);
        expect(result.latest, '0.1.4');
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
    },
  );

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
          body: '{"latest":{"version":"0.1.5"}}',
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
      expect(json['isPublished'], true);
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
