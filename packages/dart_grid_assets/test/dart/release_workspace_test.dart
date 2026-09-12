// The WORKSPACE RELEASE WAVE — `ReleaseService.publishWorkspace` and the thin
// `dart release publish` Command over it. One command computes the changed
// package set against pub.dev, runs every existing gate, validates the
// consumers a direct stable wave owes, and cuts+pushes one tag per package in
// dependency order, polling propagation between them.
//
// Every seam is a recording Fake (Fakes, not mocks): the process runner, the
// pub.dev fetch, and the between-poll wait. The suite never runs git, never
// touches the network, and never sleeps.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_grid_assets/dart_grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

/// The release commit the fake `git rev-parse HEAD` reports.
const _releaseSha = '4d1f0ab9c2e5478136aa07bd5c9e21f0a83b6d47';

/// A Fake [ProcessRunner]: answers from a script keyed on argv, records every
/// call and the generated `pubspec_overrides.yaml` as it stood at that moment
/// (the throwaway dirs are deleted before a test could read them back).
class _FakeProcess {
  _FakeProcess({
    required this.timeline,
    ProcessResult Function(String, List<String>, String?)? script,
  }) : _script = script ?? _defaultScript;

  final List<String> timeline;
  final ProcessResult Function(String, List<String>, String?) _script;
  final calls =
      <
        ({String executable, List<String> arguments, String? workingDirectory})
      >[];
  final overrideSnapshots = <String?>[];

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
    timeline.add('$executable ${arguments.join(' ')}');
    final override = workingDirectory == null
        ? null
        : File(p.join(workingDirectory, 'pubspec_overrides.yaml'));
    overrideSnapshots.add(
      override != null && override.existsSync()
          ? override.readAsStringSync()
          : null,
    );
    return _script(executable, arguments, workingDirectory);
  }
}

/// The all-green process script: every gate, every git step succeeds.
ProcessResult _defaultScript(
  String executable,
  List<String> arguments,
  String? workingDirectory,
) {
  if (executable == 'git' && arguments.first == 'rev-parse') {
    return ProcessResult(0, 0, '$_releaseSha\n', '');
  }
  if (executable == 'git' && arguments.first == 'branch') {
    return ProcessResult(0, 0, '  origin/main\n  origin/release-wave\n', '');
  }
  if (executable == 'dart' && arguments.join(' ') == 'pub publish --dry-run') {
    return ProcessResult(0, 0, 'Package has 0 warnings.', '');
  }
  return ProcessResult(0, 0, 'ok', '');
}

/// A Fake [HttpGetter] over the pub.dev package API: answers from a responder
/// keyed on (package, how many times that package has been polled already), so
/// a test can script "unpublished, then published" propagation.
class _FakePubDev {
  _FakePubDev({required this.timeline, required this.responder});

  final List<String> timeline;
  final HttpFetch Function(String package, int attempt) responder;
  final calls = <String>[];

  Future<HttpFetch> call(Uri url) async {
    final package = url.pathSegments.last;
    final attempt = calls.where((call) => call == package).length;
    calls.add(package);
    timeline.add('poll $package');
    return responder(package, attempt);
  }
}

/// A Fake [ReleaseWait]: records the requested pauses and returns instantly.
class _FakeWait {
  final waited = <Duration>[];
  Future<void> call(Duration duration) async => waited.add(duration);
}

HttpFetch _listing(List<String> versions) => HttpFetch(
  statusCode: 200,
  body: jsonEncode({
    'latest': {'version': versions.last},
    'versions': [
      for (final version in versions) {'version': version},
    ],
  }),
);

const _unpublished = HttpFetch(statusCode: 404, body: 'not found');

/// The all-green stable (`--change fix`) pub.dev script: `wave_base` and
/// `wave_middle` each bump a patch off a published predecessor, `wave_leaf` is
/// a first release, `wave_settled` is already published, and every package
/// propagates on its second post-push poll at the latest.
HttpFetch _fixResponder(String package, int attempt) => switch (package) {
  'wave_base' =>
    attempt < 2
        ? _listing(const ['0.1.3', '0.1.4'])
        : _listing(const ['0.1.3', '0.1.4', '0.1.5']),
  'wave_middle' =>
    attempt == 0
        ? _listing(const ['0.2.3'])
        : _listing(const ['0.2.3', '0.2.4']),
  'wave_leaf' => attempt == 0 ? _unpublished : _listing(const ['0.3.2']),
  'wave_settled' => _listing(const ['0.1.0']),
  _ => throw StateError('unexpected pub.dev poll for $package'),
};

/// The all-green DEV-rung pub.dev script: both predecessors are stable, so a
/// breaking move enters the ladder at `dev.1`.
HttpFetch _devResponder(String package, int attempt) => switch (package) {
  'wave_base' =>
    attempt == 0
        ? _listing(const ['0.1.4'])
        : _listing(const ['0.1.4', '0.2.0-dev.1']),
  'wave_middle' =>
    attempt == 0
        ? _listing(const ['0.2.3'])
        : _listing(const ['0.2.3', '0.3.0-dev.1']),
  'wave_leaf' => attempt == 0 ? _unpublished : _listing(const ['0.1.0-dev.1']),
  'wave_settled' => _listing(const ['0.1.0']),
  _ => throw StateError('unexpected pub.dev poll for $package'),
};

/// A MIXED-rung pub.dev script: `wave_base` has already walked to `beta` off
/// its own `dev.2`, while `wave_middle` is still entering at `dev.1`.
HttpFetch _mixedRungResponder(String package, int attempt) => switch (package) {
  'wave_base' =>
    attempt == 0
        ? _listing(const ['0.1.4', '0.2.0-dev.2'])
        : _listing(const ['0.1.4', '0.2.0-dev.2', '0.2.0-beta.1']),
  'wave_middle' =>
    attempt == 0
        ? _listing(const ['0.2.3'])
        : _listing(const ['0.2.3', '0.3.0-dev.1']),
  'wave_leaf' => _listing(const ['0.3.2']),
  'wave_settled' => _listing(const ['0.1.0']),
  _ => throw StateError('unexpected pub.dev poll for $package'),
};

/// An RC pub.dev script — the rung only a declared human intent admits.
HttpFetch _rcResponder(String package, int attempt) => switch (package) {
  'wave_base' =>
    attempt == 0
        ? _listing(const ['0.1.4'])
        : _listing(const ['0.1.4', '0.2.0-rc.1']),
  'wave_middle' =>
    attempt == 0
        ? _listing(const ['0.2.3'])
        : _listing(const ['0.2.3', '0.3.0-rc.1']),
  'wave_leaf' => attempt == 0 ? _unpublished : _listing(const ['0.1.0-rc.1']),
  'wave_settled' => _listing(const ['0.1.0']),
  _ => throw StateError('unexpected pub.dev poll for $package'),
};

void _writeMember(
  Directory root,
  String dir,
  String name,
  String version, {
  Map<String, String> dependencies = const {},
  bool publishable = true,
}) {
  final member = Directory(p.join(root.path, dir))..createSync(recursive: true);
  final buffer = StringBuffer()
    ..writeln('name: $name')
    ..writeln('version: $version')
    ..writeln('resolution: workspace');
  if (!publishable) buffer.writeln('publish_to: none');
  buffer
    ..writeln('environment:')
    ..writeln('  sdk: ^3.11.0');
  if (dependencies.isNotEmpty) {
    buffer.writeln('dependencies:');
    for (final entry in dependencies.entries) {
      buffer.writeln('  ${entry.key}: ${entry.value}');
    }
  }
  File(p.join(member.path, 'pubspec.yaml')).writeAsStringSync('$buffer');
  File(
    p.join(member.path, 'README.md'),
  ).writeAsStringSync('# $name\n\nA release-wave fixture package.\n');
  File(
    p.join(member.path, 'CHANGELOG.md'),
  ).writeAsStringSync('# Changelog\n\n## $version\n\n- Fixture entry.\n');
  Directory(p.join(member.path, 'lib')).createSync();
  File(
    p.join(member.path, 'lib', '$name.dart'),
  ).writeAsStringSync("/// A fixture library.\nconst $name = '$version';\n");
}

/// A five-member pub workspace + one downstream consumer checkout. The
/// dependency chain (leaf -> middle -> base) is deliberately NOT the
/// alphabetical order, so a dependency-first result cannot be a sorted one.
({Directory root, Directory consumer}) _writeWaveWorkspace({
  String base = '0.1.5',
  String middle = '0.2.4',
  String leaf = '0.3.2',
}) {
  final root = Directory.systemTemp.createTempSync('release-wave-');
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
    'name: release_wave_workspace\n'
    'publish_to: none\n'
    'environment:\n'
    '  sdk: ^3.11.0\n'
    'workspace:\n'
    '  - packages/base\n'
    '  - packages/middle\n'
    '  - packages/leaf\n'
    '  - packages/settled\n'
    '  - packages/private\n',
  );
  _writeMember(root, 'packages/base', 'wave_base', base);
  _writeMember(
    root,
    'packages/middle',
    'wave_middle',
    middle,
    dependencies: const {'wave_base': '^0.1.4', 'path': '^1.9.0'},
  );
  _writeMember(
    root,
    'packages/leaf',
    'wave_leaf',
    leaf,
    dependencies: const {'wave_middle': '^0.2.3'},
  );
  _writeMember(root, 'packages/settled', 'wave_settled', '0.1.0');
  _writeMember(
    root,
    'packages/private',
    'wave_private',
    '0.9.0',
    publishable: false,
  );
  final consumer = Directory(p.join(root.path, 'consumer'))..createSync();
  return (root: root, consumer: consumer);
}

/// Narrows a generated fixture workspace to `packages/leaf` alone — the member
/// pub.dev answers 404 for. With one member there is exactly one discovery
/// lookup, so a refusal on the FIRST-RELEASE branch is observable as a
/// single-entry poll log with nothing after it.
void _restrictWorkspaceToWaveLeaf(Directory root) {
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
    'name: release_wave_workspace\n'
    'publish_to: none\n'
    'environment:\n'
    '  sdk: ^3.11.0\n'
    'workspace:\n'
    '  - packages/leaf\n',
  );
}

ReleaseConsumer _consumerAt(Directory directory) => ReleaseConsumer(
  name: 'space_station',
  directory: directory.path,
  links: const [
    PubLink(
      package: 'wave_base',
      gitUrl: 'git@github.com:memento-engineering/power_station.git',
    ),
  ],
);

Matcher _stoppedAt(
  String stage, {
  required String? package,
  Object message = anything,
}) => isA<ReleaseWaveFailure>()
    .having((failure) => failure.stage.wireName, 'stage', stage)
    .having((failure) => failure.package, 'package', package)
    .having((failure) => failure.message, 'message', message);

/// The wave harness: a fixture workspace plus the three recording seams.
({
  Directory root,
  Directory consumer,
  List<String> timeline,
  _FakeProcess process,
  _FakePubDev pubDev,
  _FakeWait wait,
  ReleaseService service,
})
_harness({
  ProcessResult Function(String, List<String>, String?)? script,
  HttpFetch Function(String, int) responder = _fixResponder,
  String base = '0.1.5',
  String middle = '0.2.4',
  String leaf = '0.3.2',
}) {
  final fixture = _writeWaveWorkspace(base: base, middle: middle, leaf: leaf);
  addTearDown(() => fixture.root.delete(recursive: true));
  final timeline = <String>[];
  final process = _FakeProcess(timeline: timeline, script: script);
  final pubDev = _FakePubDev(timeline: timeline, responder: responder);
  final wait = _FakeWait();
  return (
    root: fixture.root,
    consumer: fixture.consumer,
    timeline: timeline,
    process: process,
    pubDev: pubDev,
    wait: wait,
    service: ReleaseService(
      runProcess: process.call,
      httpGet: pubDev.call,
      wait: wait.call,
    ),
  );
}

/// A Fake [ReleaseService] that records the Command's one delegation and
/// answers with a canned plan or a canned structured failure — the probe that
/// proves the Command holds no wave logic of its own.
class _RecordingReleaseService extends ReleaseService {
  _RecordingReleaseService({this.plan, this.failure});

  final ReleaseWavePlan? plan;
  final ReleaseWaveFailure? failure;
  final calls =
      <
        ({
          String workspaceRoot,
          ReleaseChange change,
          ReleaseRung? rung,
          bool promotionIntent,
          List<ReleaseConsumer> consumers,
          bool dryRunOnly,
        })
      >[];

  @override
  Future<ReleaseWavePlan> publishWorkspace({
    required String workspaceRoot,
    required ReleaseChange change,
    ReleaseRung? rung,
    bool promotionIntent = false,
    List<ReleaseConsumer> consumers = const [],
    bool dryRunOnly = false,
    Duration pollInterval = const Duration(seconds: 5),
    int maxPollAttempts = 120,
  }) async {
    calls.add((
      workspaceRoot: workspaceRoot,
      change: change,
      rung: rung,
      promotionIntent: promotionIntent,
      consumers: consumers,
      dryRunOnly: dryRunOnly,
    ));
    final refusal = failure;
    if (refusal != null) throw refusal;
    return plan!;
  }
}

void main() {
  group(
    'changed-package set excludes published versions and orders dependencies',
    () {
      test(
        'only unpublished members ride the wave, dependency-first',
        () async {
          final harness = _harness();
          final plan = await harness.service.publishWorkspace(
            workspaceRoot: harness.root.path,
            change: ReleaseChange.fix,
            consumers: [_consumerAt(harness.consumer)],
            pollInterval: const Duration(milliseconds: 1),
          );

          // leaf -> middle -> base, so the dependency-first order is the
          // REVERSE of the alphabetical one a sort would have produced.
          expect(plan.packages.map((package) => package.package), [
            'wave_base',
            'wave_middle',
            'wave_leaf',
          ]);
          expect(
            plan.packages.map(
              (package) => package.publishedPredecessor?.toString(),
            ),
            ['0.1.4', '0.2.3', null],
            reason: 'wave_leaf is a first release (pub.dev answered 404)',
          );
          expect(plan.packages.map((package) => package.localVersion), [
            Version.parse('0.1.5'),
            Version.parse('0.2.4'),
            Version.parse('0.3.2'),
          ]);
          expect(plan.packages.map((package) => package.tag), [
            'wave_base-v0.1.5',
            'wave_middle-v0.2.4',
            'wave_leaf-v0.3.2',
          ]);
          expect(plan.packages.map((package) => package.directory), [
            p.join('packages', 'base'),
            p.join('packages', 'middle'),
            p.join('packages', 'leaf'),
          ]);
          expect(
            plan.packages.map((package) => package.dependencies),
            [
              <String>[],
              <String>['wave_base'],
              <String>['wave_middle'],
            ],
            reason: 'an out-of-wave dep (path) is not an edge',
          );
          expect(plan.change, ReleaseChange.fix);
          expect(
            plan.packages.map((package) => package.rung),
            everyElement(ReleaseRung.stable),
            reason: 'no authored version carries a prerelease identifier',
          );
          expect(plan.promotionIntent, isFalse);
          expect(plan.dryRun, isFalse);
          expect(plan.workspaceRoot, p.normalize(harness.root.path));

          // wave_settled is published at its authored version, so it never
          // enters the wave; wave_private is `publish_to: none`, so it is
          // never even polled.
          expect(harness.pubDev.calls, contains('wave_settled'));
          expect(harness.pubDev.calls, isNot(contains('wave_private')));
        },
      );

      test('a wave with nothing to publish returns an empty plan', () async {
        final harness = _harness(
          responder: (package, attempt) => switch (package) {
            'wave_base' => _listing(const ['0.1.4', '0.1.5']),
            'wave_middle' => _listing(const ['0.2.4']),
            'wave_leaf' => _listing(const ['0.3.2']),
            'wave_settled' => _listing(const ['0.1.0']),
            _ => throw StateError('unexpected poll for $package'),
          },
        );
        final plan = await harness.service.publishWorkspace(
          workspaceRoot: harness.root.path,
          change: ReleaseChange.fix,
          consumers: [_consumerAt(harness.consumer)],
        );
        expect(plan.packages, isEmpty);
        expect(
          harness.process.calls,
          isEmpty,
          reason: 'no gate, no git and no consumer work for an empty wave',
        );
      });

      test('an unsupported pub.dev status refuses the wave', () async {
        final harness = _harness(
          responder: (package, attempt) => package == 'wave_middle'
              ? const HttpFetch(statusCode: 503, body: 'unavailable')
              : _fixResponder(package, attempt),
        );
        await expectLater(
          harness.service.publishWorkspace(
            workspaceRoot: harness.root.path,
            change: ReleaseChange.fix,
            consumers: [_consumerAt(harness.consumer)],
          ),
          throwsA(
            _stoppedAt(
              'discovery',
              package: 'wave_middle',
              message: allOf(contains('503'), contains('not published yet')),
            ),
          ),
        );
      });

      test(
        'no published predecessor reaching the authored version refuses',
        () async {
          final harness = _harness(
            responder: (package, attempt) => package == 'wave_base'
                ? _listing(const ['0.1.1'])
                : _fixResponder(package, attempt),
          );
          await expectLater(
            harness.service.publishWorkspace(
              workspaceRoot: harness.root.path,
              change: ReleaseChange.fix,
              consumers: [_consumerAt(harness.consumer)],
            ),
            throwsA(
              _stoppedAt(
                'discovery',
                package: 'wave_base',
                message: allOf(
                  contains('0.1.5'),
                  contains('--change fix --rung stable'),
                ),
              ),
            ),
          );
        },
      );

      test('a malformed published version refuses the wave', () async {
        final harness = _harness(
          responder: (package, attempt) => package == 'wave_base'
              ? _listing(const ['0.1.4', 'not-a-version'])
              : _fixResponder(package, attempt),
        );
        await expectLater(
          harness.service.publishWorkspace(
            workspaceRoot: harness.root.path,
            change: ReleaseChange.fix,
            consumers: [_consumerAt(harness.consumer)],
          ),
          throwsA(
            _stoppedAt(
              'discovery',
              package: 'wave_base',
              message: contains('not-a-version'),
            ),
          ),
        );
      });

      test(
        'an inferred rc first release refuses without declared intent',
        () async {
          final harness = _harness(leaf: '0.3.2-rc.1');
          await expectLater(
            harness.service.publishWorkspace(
              workspaceRoot: harness.root.path,
              change: ReleaseChange.fix,
              consumers: [_consumerAt(harness.consumer)],
            ),
            throwsA(
              _stoppedAt(
                'discovery',
                package: 'wave_leaf',
                message: allOf(
                  contains('0.3.2-rc.1'),
                  contains('rc means a human has declared intent to promote'),
                ),
              ),
            ),
          );
        },
      );

      test('a version on no supported rung refuses LOUDLY', () async {
        final harness = _harness(leaf: '0.3.2-alpha.1');
        await expectLater(
          harness.service.publishWorkspace(
            workspaceRoot: harness.root.path,
            change: ReleaseChange.fix,
            consumers: [_consumerAt(harness.consumer)],
          ),
          throwsA(
            _stoppedAt(
              'discovery',
              package: 'wave_leaf',
              message: allOf(
                contains('0.3.2-alpha.1'),
                contains('<dev|beta|rc>'),
              ),
            ),
          ),
        );
      });

      test('a root that declares no workspace refuses LOUDLY', () async {
        final root = Directory.systemTemp.createTempSync('release-no-wave-');
        addTearDown(() => root.delete(recursive: true));
        File(
          p.join(root.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: lonely\nversion: 0.1.0\n');
        await expectLater(
          const ReleaseService().publishWorkspace(
            workspaceRoot: root.path,
            change: ReleaseChange.fix,
          ),
          throwsA(
            _stoppedAt(
              'workspace',
              package: null,
              message: contains('no pub workspace members'),
            ),
          ),
        );
      });

      test(
        'a member without a version refuses at the workspace stage',
        () async {
          final harness = _harness();
          final pubspec = File(
            p.join(harness.root.path, 'packages', 'base', 'pubspec.yaml'),
          );
          pubspec.writeAsStringSync(
            pubspec.readAsStringSync().replaceFirst('version: 0.1.5\n', ''),
          );
          await expectLater(
            harness.service.publishWorkspace(
              workspaceRoot: harness.root.path,
              change: ReleaseChange.fix,
              consumers: [_consumerAt(harness.consumer)],
            ),
            throwsA(
              _stoppedAt(
                'workspace',
                package: 'wave_base',
                message: contains('no version'),
              ),
            ),
          );
          expect(harness.pubDev.calls, isEmpty);
        },
      );
    },
  );

  group('publishWorkspace composes existing ops and polls between one-tag '
      'pushes', () {
    test(
      'gates run first, then one tag push per package behind a poll',
      () async {
        final harness = _harness();
        await harness.service.publishWorkspace(
          workspaceRoot: harness.root.path,
          change: ReleaseChange.fix,
          consumers: [_consumerAt(harness.consumer)],
          pollInterval: const Duration(milliseconds: 7),
        );

        // The PREFLIGHT: the existing scrub gate (its declared-floors leg is a
        // pub get + analyze in a throwaway copy) for every changed package,
        // then the existing publish dry-run gate for every ordered package,
        // then the release commit and the consumer gate — all before any tag.
        final preflight = harness.timeline.sublist(
          0,
          harness.timeline.indexOf('git tag wave_base-v0.1.5'),
        );
        expect(
          preflight.where((entry) => entry == 'dart pub get'),
          hasLength(3),
          reason: 'one declared-floors resolution per changed package',
        );
        expect(
          preflight.where((entry) => entry == 'dart pub publish --dry-run'),
          hasLength(3),
        );
        expect(preflight, contains('git rev-parse HEAD'));
        expect(
          preflight,
          contains('git branch --remotes --contains $_releaseSha'),
        );

        // The WAVE: tag, push, then poll until published — and only then the
        // next dependent moves.
        expect(
          harness.timeline.sublist(
            harness.timeline.indexOf('git tag wave_base-v0.1.5'),
          ),
          [
            'git tag wave_base-v0.1.5',
            'git push origin wave_base-v0.1.5',
            'poll wave_base',
            'poll wave_base',
            'git tag wave_middle-v0.2.4',
            'git push origin wave_middle-v0.2.4',
            'poll wave_middle',
            'git tag wave_leaf-v0.3.2',
            'git push origin wave_leaf-v0.3.2',
            'poll wave_leaf',
          ],
        );
        expect(
          harness.wait.waited,
          [const Duration(milliseconds: 7)],
          reason: 'the injected wait runs only BETWEEN unpublished polls',
        );

        // The tag push IS the publish: nothing ever uploads, and the stable
        // promotion op is not composed here.
        expect(
          harness.process.calls.where(
            (call) => call.arguments.contains('publish'),
          ),
          everyElement(
            isA<
                  ({
                    String executable,
                    List<String> arguments,
                    String? workingDirectory,
                  })
                >()
                .having(
                  (call) => call.arguments,
                  'arguments',
                  contains('--dry-run'),
                ),
          ),
        );
        // Every git tag cut is a wave tag — no promoted stable base rode along.
        expect(
          harness.process.calls
              .where(
                (call) =>
                    call.executable == 'git' && call.arguments.first == 'tag',
              )
              .map((call) => call.arguments[1]),
          ['wave_base-v0.1.5', 'wave_middle-v0.2.4', 'wave_leaf-v0.3.2'],
        );
      },
    );

    test(
      'consumers resolve against the origin-reachable release commit',
      () async {
        final harness = _harness();
        await harness.service.publishWorkspace(
          workspaceRoot: harness.root.path,
          change: ReleaseChange.fix,
          consumers: [_consumerAt(harness.consumer)],
          pollInterval: Duration.zero,
        );

        final consumerCalls = [
          for (var i = 0; i < harness.process.calls.length; i++)
            if (harness.process.calls[i].workingDirectory ==
                harness.consumer.path)
              i,
        ];
        expect(consumerCalls, hasLength(2));
        expect(harness.process.calls[consumerCalls[0]].arguments, ['analyze']);
        expect(harness.process.calls[consumerCalls[1]].arguments, ['test']);
        expect(
          harness.process.overrideSnapshots[consumerCalls[0]],
          contains("ref: '$_releaseSha'"),
          reason: 'pub takes a commit SHA as a git ref exactly like a tag',
        );
        expect(
          File(
            p.join(harness.consumer.path, 'pubspec_overrides.yaml'),
          ).existsSync(),
          isFalse,
          reason:
              'the generated override is removed once the wave is validated',
        );
      },
    );

    test('an unpushed release commit refuses before any tag', () async {
      final harness = _harness(
        script: (executable, arguments, workingDirectory) =>
            executable == 'git' && arguments.first == 'branch'
            ? ProcessResult(0, 0, '', '')
            : _defaultScript(executable, arguments, workingDirectory),
      );
      await expectLater(
        harness.service.publishWorkspace(
          workspaceRoot: harness.root.path,
          change: ReleaseChange.fix,
          consumers: [_consumerAt(harness.consumer)],
        ),
        throwsA(
          _stoppedAt(
            'release-commit',
            package: null,
            message: allOf(contains(_releaseSha), contains('origin/')),
          ),
        ),
      );
      expect(harness.timeline, isNot(contains('git tag wave_base-v0.1.5')));
    });
  });

  // Breaking work is agent work BELOW rc: it enters the ladder at dev, may
  // occupy beta, and reaches rc only on a declared human intent. The rung is a
  // property of each PACKAGE, so a wave carries a mix of them.
  group('breaking prerelease rungs and promotion intent', () {
    test('breaking dev and beta publish without promotion intent', () async {
      final harness = _harness(
        responder: _devResponder,
        base: '0.2.0-dev.1',
        middle: '0.3.0-dev.1',
        leaf: '0.1.0-dev.1',
      );
      final plan = await harness.service.publishWorkspace(
        workspaceRoot: harness.root.path,
        change: ReleaseChange.breaking,
        pollInterval: Duration.zero,
      );

      expect(plan.packages.map((package) => package.tag), [
        'wave_base-v0.2.0-dev.1',
        'wave_middle-v0.3.0-dev.1',
        'wave_leaf-v0.1.0-dev.1',
      ]);
      expect(
        plan.packages.map((package) => package.rung),
        everyElement(ReleaseRung.dev),
      );
      expect(
        plan.packages.map(
          (package) => package.publishedPredecessor?.toString(),
        ),
        ['0.1.4', '0.2.3', null],
        reason:
            'wave_leaf is a first release authored straight onto the ladder',
      );
      expect(plan.promotionIntent, isFalse);
      expect(
        harness.timeline,
        isNot(contains('git rev-parse HEAD')),
        reason: 'a prerelease wave is cut first; the separate ops gate it',
      );
      expect(
        harness.process.calls.where(
          (call) => call.workingDirectory == harness.consumer.path,
        ),
        isEmpty,
      );

      // The same wave one rung up, requested explicitly and still unattended.
      final beta = _harness(
        responder: (package, attempt) => switch (package) {
          'wave_base' =>
            attempt == 0
                ? _listing(const ['0.1.4', '0.2.0-dev.2'])
                : _listing(const ['0.1.4', '0.2.0-dev.2', '0.2.0-beta.1']),
          'wave_middle' => _listing(const ['0.2.4']),
          'wave_leaf' => _listing(const ['0.3.2']),
          'wave_settled' => _listing(const ['0.1.0']),
          _ => throw StateError('unexpected poll for $package'),
        },
        base: '0.2.0-beta.1',
      );
      final betaPlan = await beta.service.publishWorkspace(
        workspaceRoot: beta.root.path,
        change: ReleaseChange.breaking,
        rung: ReleaseRung.beta,
        pollInterval: Duration.zero,
      );
      expect(betaPlan.packages.single.tag, 'wave_base-v0.2.0-beta.1');
      expect(betaPlan.packages.single.rung, ReleaseRung.beta);
      expect(
        betaPlan.packages.single.publishedPredecessor.toString(),
        '0.2.0-dev.2',
        reason: 'the counter restarts at 1 when the identifier changes',
      );
    });

    test('rc without promotion intent is refused before mutation', () async {
      final harness = _harness(
        responder: _rcResponder,
        base: '0.2.0-rc.1',
        middle: '0.3.0-rc.1',
        leaf: '0.1.0-rc.1',
      );
      await expectLater(
        harness.service.publishWorkspace(
          workspaceRoot: harness.root.path,
          change: ReleaseChange.breaking,
          rung: ReleaseRung.rc,
        ),
        throwsA(
          _stoppedAt(
            'discovery',
            package: 'wave_base',
            message: contains(
              'rc means a human has declared intent to promote',
            ),
          ),
        ),
      );
      expect(
        harness.timeline.where((entry) => entry.startsWith('git tag')),
        isEmpty,
      );
    });

    test('declared rc succeeds', () async {
      final harness = _harness(
        responder: _rcResponder,
        base: '0.2.0-rc.1',
        middle: '0.3.0-rc.1',
        leaf: '0.1.0-rc.1',
      );
      final plan = await harness.service.publishWorkspace(
        workspaceRoot: harness.root.path,
        change: ReleaseChange.breaking,
        rung: ReleaseRung.rc,
        promotionIntent: true,
        pollInterval: Duration.zero,
      );
      expect(plan.packages.map((package) => package.tag), [
        'wave_base-v0.2.0-rc.1',
        'wave_middle-v0.3.0-rc.1',
        'wave_leaf-v0.1.0-rc.1',
      ]);
      expect(
        plan.packages.map((package) => package.rung),
        everyElement(ReleaseRung.rc),
      );
      expect(plan.promotionIntent, isTrue);
      expect(
        harness.timeline.where((entry) => entry.startsWith('git tag')),
        hasLength(3),
      );
    });

    test('stable breaking and consumer failure direct to dev', () async {
      // A breaking move authored as a STABLE version: refused at the plan
      // stage, before any gate, and pointed at the bottom of the ladder.
      final stable = _harness(
        responder: (package, attempt) => switch (package) {
          'wave_base' => _listing(const ['0.1.4']),
          'wave_middle' => _listing(const ['0.2.4']),
          'wave_leaf' => _listing(const ['0.3.2']),
          'wave_settled' => _listing(const ['0.1.0']),
          _ => throw StateError('unexpected poll for $package'),
        },
        base: '0.2.0',
      );
      await expectLater(
        stable.service.publishWorkspace(
          workspaceRoot: stable.root.path,
          change: ReleaseChange.breaking,
          consumers: [_consumerAt(stable.consumer)],
        ),
        throwsA(
          _stoppedAt(
            'plan',
            package: 'wave_base',
            message: allOf(
              contains('--change breaking --rung dev'),
              contains('validate-consumers'),
              contains('promote'),
              isNot(contains('rc-first')),
              isNot(contains('--change rc')),
            ),
          ),
        ),
      );
      expect(
        stable.timeline.where((entry) => entry.startsWith('git ')),
        isEmpty,
        reason: 'the plan stage runs before any gate, tag or push',
      );

      // A stable wave whose consumer fails is breaking by definition, and the
      // remedy names the same dev rung rather than the retired rc path.
      final failing = _harness(
        script: (executable, arguments, workingDirectory) =>
            executable == 'dart' &&
                arguments.join(' ') == 'analyze' &&
                workingDirectory != null &&
                p.basename(workingDirectory) == 'consumer'
            ? ProcessResult(0, 1, '', 'consumer analyze failed')
            : _defaultScript(executable, arguments, workingDirectory),
      );
      await expectLater(
        failing.service.publishWorkspace(
          workspaceRoot: failing.root.path,
          change: ReleaseChange.fix,
          consumers: [_consumerAt(failing.consumer)],
        ),
        throwsA(
          _stoppedAt(
            'validate-consumers',
            package: null,
            message: allOf(
              contains('--change breaking --rung dev'),
              isNot(contains('rc-first')),
              isNot(contains('--change rc')),
            ),
          ),
        ),
      );
    });

    test('mixed dev/beta wave carries each rung', () async {
      final harness = _harness(
        responder: _mixedRungResponder,
        base: '0.2.0-beta.1',
        middle: '0.3.0-dev.1',
      );
      final plan = await harness.service.publishWorkspace(
        workspaceRoot: harness.root.path,
        change: ReleaseChange.breaking,
        pollInterval: Duration.zero,
      );

      expect(plan.packages.map((package) => package.package), [
        'wave_base',
        'wave_middle',
      ]);
      expect(plan.packages.map((package) => package.rung), [
        ReleaseRung.beta,
        ReleaseRung.dev,
      ]);
      expect(plan.packages.map((package) => package.tag), [
        'wave_base-v0.2.0-beta.1',
        'wave_middle-v0.3.0-dev.1',
      ]);
      expect(
        plan.toJson()['packages'],
        [containsPair('rung', 'beta'), containsPair('rung', 'dev')],
        reason: 'the rung rides the per-package JSON the skill parses',
      );
      expect(plan.toJson()['promotionIntent'], false);

      // An explicit --rung cannot re-rung a package behind its author's back.
      final pinned = _harness(
        responder: _mixedRungResponder,
        base: '0.2.0-beta.1',
        middle: '0.3.0-dev.1',
      );
      await expectLater(
        pinned.service.publishWorkspace(
          workspaceRoot: pinned.root.path,
          change: ReleaseChange.breaking,
          rung: ReleaseRung.dev,
        ),
        throwsA(
          _stoppedAt(
            'discovery',
            package: 'wave_base',
            message: allOf(contains('0.2.0-beta.1'), contains('dev rung')),
          ),
        ),
      );
    });
  });

  // A FIRST RELEASE is the branch with no published predecessor to argue with:
  // pub.dev answers 404, so nothing but the authored version says what rung the
  // package is on. That is also the branch that reaches an irreversible tag push
  // with no consumer to validate against, so the rung the author wrote and the
  // rung the wave was asked for must agree BEFORE the wave touches anything.
  group('first-release rung consistency', () {
    /// The sole discovery lookup a restricted workspace makes: 404, and a
    /// refusal must stop there.
    HttpFetch firstReleaseOnly(String package, int attempt) =>
        package == 'wave_leaf'
        ? _unpublished
        : throw StateError('unexpected pub.dev poll for $package');

    /// Everything a refusal at discovery must have left untouched: one poll,
    /// no scrub process, no dry-run, no tag, no push, no propagation wait.
    void expectStoppedBeforeMutation({
      required List<String> timeline,
      required _FakeProcess process,
      required _FakePubDev pubDev,
      required _FakeWait wait,
    }) {
      expect(pubDev.calls, ['wave_leaf']);
      expect(timeline, [
        'poll wave_leaf',
      ], reason: 'the refusal lands on the one discovery lookup');
      expect(
        process.calls,
        isEmpty,
        reason: 'no scrub, no publish dry-run, no tag and no push began',
      );
      expect(wait.waited, isEmpty, reason: 'no propagation poll began');
    }

    test(
      'fix with requested stable refuses authored dev first release',
      () async {
        final harness = _harness(
          responder: firstReleaseOnly,
          leaf: '0.2.0-dev.1',
        );
        _restrictWorkspaceToWaveLeaf(harness.root);
        await expectLater(
          harness.service.publishWorkspace(
            workspaceRoot: harness.root.path,
            change: ReleaseChange.fix,
            rung: ReleaseRung.stable,
            consumers: [_consumerAt(harness.consumer)],
          ),
          throwsA(
            _stoppedAt(
              'discovery',
              package: 'wave_leaf',
              message: allOf(
                contains('is authored as'),
                contains('0.2.0-dev.1'),
                contains('stable rung'),
                contains('re-author the version or drop'),
              ),
            ),
          ),
        );
        expectStoppedBeforeMutation(
          timeline: harness.timeline,
          process: harness.process,
          pubDev: harness.pubDev,
          wait: harness.wait,
        );
      },
    );

    test(
      'fix with requested dev refuses authored stable first release',
      () async {
        final harness = _harness(responder: firstReleaseOnly, leaf: '0.2.0');
        _restrictWorkspaceToWaveLeaf(harness.root);
        await expectLater(
          harness.service.publishWorkspace(
            workspaceRoot: harness.root.path,
            change: ReleaseChange.fix,
            rung: ReleaseRung.dev,
            consumers: [_consumerAt(harness.consumer)],
          ),
          throwsA(
            _stoppedAt(
              'discovery',
              package: 'wave_leaf',
              message: allOf(
                contains('is authored as'),
                contains('0.2.0'),
                contains('dev rung'),
                contains('re-author the version or drop'),
              ),
            ),
          ),
        );
        expectStoppedBeforeMutation(
          timeline: harness.timeline,
          process: harness.process,
          pubDev: harness.pubDev,
          wait: harness.wait,
        );
      },
    );

    test(
      'breaking with requested beta refuses authored dev first release',
      () async {
        final harness = _harness(
          responder: firstReleaseOnly,
          leaf: '0.2.0-dev.1',
        );
        _restrictWorkspaceToWaveLeaf(harness.root);
        await expectLater(
          harness.service.publishWorkspace(
            workspaceRoot: harness.root.path,
            change: ReleaseChange.breaking,
            rung: ReleaseRung.beta,
          ),
          throwsA(
            _stoppedAt(
              'discovery',
              package: 'wave_leaf',
              message: allOf(
                contains('is authored as'),
                contains('0.2.0-dev.1'),
                contains('beta rung'),
                contains('re-author the version or drop'),
              ),
            ),
          ),
        );
        expectStoppedBeforeMutation(
          timeline: harness.timeline,
          process: harness.process,
          pubDev: harness.pubDev,
          wait: harness.wait,
        );
      },
    );

    test('fix with inferred stable publishes first release', () async {
      final harness = _harness(
        responder: (package, attempt) => package == 'wave_leaf'
            ? (attempt == 0 ? _unpublished : _listing(const ['0.3.2']))
            : throw StateError('unexpected pub.dev poll for $package'),
      );
      _restrictWorkspaceToWaveLeaf(harness.root);
      final plan = await harness.service.publishWorkspace(
        workspaceRoot: harness.root.path,
        change: ReleaseChange.fix,
        consumers: [_consumerAt(harness.consumer)],
        pollInterval: Duration.zero,
      );

      final leaf = plan.packages.single;
      expect(leaf.tag, 'wave_leaf-v0.3.2');
      expect(
        leaf.publishedPredecessor,
        isNull,
        reason: 'a first release bumps off nothing',
      );
      expect(leaf.rung, ReleaseRung.stable);
      expect(harness.timeline, contains('git tag wave_leaf-v0.3.2'));
      expect(harness.timeline, contains('git push origin wave_leaf-v0.3.2'));
    });

    test('breaking with inferred dev publishes first release', () async {
      final harness = _harness(
        responder: (package, attempt) => package == 'wave_leaf'
            ? (attempt == 0 ? _unpublished : _listing(const ['0.1.0-dev.1']))
            : throw StateError('unexpected pub.dev poll for $package'),
        leaf: '0.1.0-dev.1',
      );
      _restrictWorkspaceToWaveLeaf(harness.root);
      final plan = await harness.service.publishWorkspace(
        workspaceRoot: harness.root.path,
        change: ReleaseChange.breaking,
        pollInterval: Duration.zero,
      );

      final leaf = plan.packages.single;
      expect(leaf.tag, 'wave_leaf-v0.1.0-dev.1');
      expect(
        leaf.publishedPredecessor,
        isNull,
        reason: 'a first release enters the ladder with nothing behind it',
      );
      expect(leaf.rung, ReleaseRung.dev);
      expect(harness.timeline, contains('git tag wave_leaf-v0.1.0-dev.1'));
      expect(
        harness.timeline,
        contains('git push origin wave_leaf-v0.1.0-dev.1'),
      );
    });
  });

  group('publish Command delegates once and renders service JSON', () {
    ReleaseWavePlan cannedPlan(Directory root) => ReleaseWavePlan(
      workspaceRoot: root.path,
      change: ReleaseChange.fix,
      dryRun: false,
      packages: [
        ReleaseWavePackage(
          package: 'wave_base',
          directory: 'packages/base',
          publishedPredecessor: Version.parse('0.1.4'),
          localVersion: Version.parse('0.1.5'),
          dependencies: const [],
          rung: ReleaseRung.stable,
          tag: 'wave_base-v0.1.5',
        ),
      ],
    );

    test(
      'the Command parses argv, delegates once, and renders the plan',
      () async {
        final temp = Directory.systemTemp.createTempSync(
          'release-publish-cmd-',
        );
        addTearDown(() => temp.delete(recursive: true));
        final manifest = File(p.join(temp.path, 'consumers.json'))
          ..writeAsStringSync(
            jsonEncode({
              'consumers': [
                {
                  'name': 'space_station',
                  'directory': temp.path,
                  'links': [
                    {
                      'package': 'wave_base',
                      'git_url':
                          'git@github.com:memento-engineering/power_station.git',
                    },
                  ],
                },
              ],
            }),
          );
        final service = _RecordingReleaseService(plan: cannedPlan(temp));
        final out = StringBuffer();
        final runner = CommandRunner<int>('t', 'test')
          ..addCommand(
            ReleaseCommand(service: service, out: out, err: StringBuffer()),
          );

        final code = await runner.run([
          'release',
          'publish',
          '--workspace',
          temp.path,
          '--change',
          'fix',
          '--consumers',
          manifest.path,
          '--json',
        ]);

        expect(code, 0);
        expect(service.calls, hasLength(1));
        expect(service.calls.single.workspaceRoot, temp.path);
        expect(service.calls.single.change, ReleaseChange.fix);
        expect(
          service.calls.single.rung,
          isNull,
          reason: 'an omitted --rung lets the service infer each package rung',
        );
        expect(service.calls.single.promotionIntent, isFalse);
        expect(service.calls.single.dryRunOnly, isFalse);
        expect(service.calls.single.consumers.single.name, 'space_station');
        expect(
          service.calls.single.consumers.single.links.single.package,
          'wave_base',
        );
        expect(
          jsonDecode(out.toString().trim()),
          cannedPlan(temp).toJson(),
          reason: 'the Command renders the service result and nothing else',
        );
      },
    );

    test('--dry-run rides through to the service', () async {
      final temp = Directory.systemTemp.createTempSync('release-publish-dry-');
      addTearDown(() => temp.delete(recursive: true));
      final service = _RecordingReleaseService(plan: cannedPlan(temp));
      final runner = CommandRunner<int>('t', 'test')
        ..addCommand(
          ReleaseCommand(
            service: service,
            out: StringBuffer(),
            err: StringBuffer(),
          ),
        );
      final code = await runner.run([
        'release',
        'publish',
        '--workspace',
        temp.path,
        '--change',
        'breaking',
        '--rung',
        'dev',
        '--dry-run',
      ]);
      expect(code, 0);
      expect(service.calls.single.dryRunOnly, isTrue);
      expect(service.calls.single.change, ReleaseChange.breaking);
      expect(service.calls.single.rung, ReleaseRung.dev);
      expect(service.calls.single.consumers, isEmpty);
    });

    test('publish delegates rung and promotion intent', () async {
      final temp = Directory.systemTemp.createTempSync('release-publish-rung-');
      addTearDown(() => temp.delete(recursive: true));
      final service = _RecordingReleaseService(plan: cannedPlan(temp));
      final out = StringBuffer();
      final runner = CommandRunner<int>('t', 'test')
        ..addCommand(
          ReleaseCommand(service: service, out: out, err: StringBuffer()),
        );

      // The legacy `--change rc` spelling pins the rc rung and still needs the
      // declared intent; the Command does no version arithmetic either way.
      final code = await runner.run([
        'release',
        'publish',
        '--workspace',
        temp.path,
        '--change',
        'rc',
        '--promotion-intent',
        '--json',
      ]);

      expect(code, 0);
      expect(service.calls, hasLength(1));
      expect(service.calls.single.change, ReleaseChange.breaking);
      expect(service.calls.single.rung, ReleaseRung.rc);
      expect(service.calls.single.promotionIntent, isTrue);
      expect(
        jsonDecode(out.toString().trim()),
        cannedPlan(temp).toJson(),
        reason: 'the Command renders the service result and nothing else',
      );
    });

    test('publish refuses a rung that conflicts with the rc alias', () async {
      final service = _RecordingReleaseService();
      final err = StringBuffer();
      final runner = CommandRunner<int>('t', 'test')
        ..addCommand(
          ReleaseCommand(service: service, out: StringBuffer(), err: err),
        );
      final code = await runner.run([
        'release',
        'publish',
        '--workspace',
        '.',
        '--change',
        'rc',
        '--rung',
        'beta',
      ]);
      expect(code, 64);
      expect(service.calls, isEmpty);
      expect(err.toString(), contains('conflicts with `--rung beta`'));
    });

    test('a structured failure renders as JSON and exits 1', () async {
      final service = _RecordingReleaseService(
        failure: const ReleaseWaveFailure(
          stage: ReleaseWaveStage.push,
          package: 'wave_middle',
          message: 'git push origin wave_middle-v0.2.4 failed (exit 128)',
        ),
      );
      final out = StringBuffer();
      final runner = CommandRunner<int>('t', 'test')
        ..addCommand(
          ReleaseCommand(service: service, out: out, err: StringBuffer()),
        );
      final code = await runner.run([
        'release',
        'publish',
        '--workspace',
        '.',
        '--change',
        'breaking',
        '--rung',
        'dev',
        '--json',
      ]);
      expect(code, 1);
      expect(jsonDecode(out.toString().trim()), {
        'stage': 'push',
        'package': 'wave_middle',
        'message': 'git push origin wave_middle-v0.2.4 failed (exit 128)',
      });
    });

    test('an omitted --consumers still reaches the service gate', () async {
      // Whether the wave carries a stable package is not knowable from
      // --change alone once the rung is inferred, so the requirement lives in
      // the service's stable-member gate rather than in argv.
      final temp = Directory.systemTemp.createTempSync('release-publish-gate-');
      addTearDown(() => temp.delete(recursive: true));
      final service = _RecordingReleaseService(plan: cannedPlan(temp));
      final runner = CommandRunner<int>('t', 'test')
        ..addCommand(
          ReleaseCommand(
            service: service,
            out: StringBuffer(),
            err: StringBuffer(),
          ),
        );
      final code = await runner.run([
        'release',
        'publish',
        '--workspace',
        temp.path,
        '--change',
        'fix',
      ]);
      expect(code, 0);
      expect(service.calls.single.consumers, isEmpty);
    });

    test('a missing manifest is a usage error before delegation', () async {
      final service = _RecordingReleaseService();
      final runner = CommandRunner<int>('t', 'test')
        ..addCommand(
          ReleaseCommand(
            service: service,
            out: StringBuffer(),
            err: StringBuffer(),
          ),
        );
      final code = await runner.run([
        'release',
        'publish',
        '--workspace',
        '.',
        '--change',
        'fix',
        '--consumers',
        '/no/such/manifest.json',
      ]);
      expect(code, 64);
      expect(service.calls, isEmpty);
    });

    test('publish joins the release op group', () {
      expect(
        DartCommand().subcommands['release']!.subcommands.keys,
        contains('publish'),
      );
    });
  });

  group('dry-run executes gates without tag or push mutations', () {
    test(
      'every gate runs, no tag is cut, and overrides are restored',
      () async {
        final harness = _harness();
        final overrides = File(
          p.join(harness.consumer.path, 'pubspec_overrides.yaml'),
        )..writeAsStringSync('# a machine-local dev override\n');
        final before = overrides.readAsBytesSync();

        final plan = await harness.service.publishWorkspace(
          workspaceRoot: harness.root.path,
          change: ReleaseChange.fix,
          consumers: [_consumerAt(harness.consumer)],
          dryRunOnly: true,
        );

        expect(plan.dryRun, isTrue);
        expect(plan.packages.map((package) => package.package), [
          'wave_base',
          'wave_middle',
          'wave_leaf',
        ]);
        expect(
          harness.timeline.where(
            (entry) => entry == 'dart pub publish --dry-run',
          ),
          hasLength(3),
        );
        expect(harness.timeline, contains('git rev-parse HEAD'));
        expect(
          harness.timeline.where((entry) => entry.startsWith('git tag')),
          isEmpty,
        );
        expect(
          harness.timeline.where((entry) => entry.startsWith('git push')),
          isEmpty,
        );
        expect(
          harness.pubDev.calls.where((call) => call == 'wave_base'),
          hasLength(1),
          reason: 'discovery only — a dry run never waits on propagation',
        );
        expect(harness.wait.waited, isEmpty);
        expect(
          overrides.readAsBytesSync(),
          before,
          reason: 'a pre-existing consumer override is restored byte-for-byte',
        );
      },
    );
  });

  group(
    'failing consumer validation refuses the wave before the first tag',
    () {
      test('a failed consumer stops the wave and names the dev rung', () async {
        final harness = _harness(
          script: (executable, arguments, workingDirectory) =>
              executable == 'dart' &&
                  arguments.join(' ') == 'analyze' &&
                  workingDirectory != null &&
                  workingDirectory.startsWith('/') &&
                  p.basename(workingDirectory) == 'consumer'
              ? ProcessResult(0, 1, '', 'consumer analyze failed')
              : _defaultScript(executable, arguments, workingDirectory),
        );
        await expectLater(
          harness.service.publishWorkspace(
            workspaceRoot: harness.root.path,
            change: ReleaseChange.fix,
            consumers: [_consumerAt(harness.consumer)],
          ),
          throwsA(
            _stoppedAt(
              'validate-consumers',
              package: null,
              message: allOf(
                contains('space_station'),
                contains('--change breaking --rung dev'),
                contains(_releaseSha),
              ),
            ),
          ),
        );
        expect(
          harness.timeline.where((entry) => entry.startsWith('git tag')),
          isEmpty,
        );
        expect(
          File(
            p.join(harness.consumer.path, 'pubspec_overrides.yaml'),
          ).existsSync(),
          isFalse,
          reason:
              'the generated override is cleared even when the wave refuses',
        );
      });

      test('a stable wave with no consumers at all refuses', () async {
        final harness = _harness();
        await expectLater(
          harness.service.publishWorkspace(
            workspaceRoot: harness.root.path,
            change: ReleaseChange.fix,
          ),
          throwsA(
            _stoppedAt(
              'validate-consumers',
              package: null,
              message: contains('--consumers'),
            ),
          ),
        );
        expect(
          harness.timeline.where((entry) => entry.startsWith('git tag')),
          isEmpty,
        );
      });
    },
  );

  group('a mid-wave failure leaves later packages untagged', () {
    test('a preflight scrub failure creates no tags at all', () async {
      final harness = _harness(
        script: (executable, arguments, workingDirectory) =>
            executable == 'dart' &&
                arguments.join(' ') == 'analyze' &&
                workingDirectory != null &&
                p.basename(workingDirectory) == 'wave_middle'
            ? ProcessResult(0, 1, '', "no member named 'waveMiddle'")
            : _defaultScript(executable, arguments, workingDirectory),
      );
      await expectLater(
        harness.service.publishWorkspace(
          workspaceRoot: harness.root.path,
          change: ReleaseChange.fix,
          consumers: [_consumerAt(harness.consumer)],
        ),
        throwsA(
          _stoppedAt(
            'scrub',
            package: 'wave_middle',
            message: contains('waveMiddle'),
          ),
        ),
      );
      expect(
        harness.timeline.where((entry) => entry.startsWith('git tag')),
        isEmpty,
      );
    });

    test('a preflight dry-run failure creates no tags at all', () async {
      final harness = _harness(
        script: (executable, arguments, workingDirectory) =>
            executable == 'dart' &&
                arguments.join(' ') == 'pub publish --dry-run' &&
                workingDirectory != null &&
                p.basename(workingDirectory) == 'middle'
            ? ProcessResult(
                0,
                65,
                '* Line 3: leaked\nPackage has 1 warning.',
                '',
              )
            : _defaultScript(executable, arguments, workingDirectory),
      );
      await expectLater(
        harness.service.publishWorkspace(
          workspaceRoot: harness.root.path,
          change: ReleaseChange.fix,
          consumers: [_consumerAt(harness.consumer)],
        ),
        throwsA(
          _stoppedAt(
            'dry-run',
            package: 'wave_middle',
            message: contains('Line 3: leaked'),
          ),
        ),
      );
      expect(
        harness.timeline.where((entry) => entry.startsWith('git tag')),
        isEmpty,
      );
    });

    test('a tag failure leaves the stopping package unpushed', () async {
      final harness = _harness(
        script: (executable, arguments, workingDirectory) =>
            executable == 'git' &&
                arguments.first == 'tag' &&
                arguments[1] == 'wave_middle-v0.2.4'
            ? ProcessResult(0, 128, '', 'tag already exists')
            : _defaultScript(executable, arguments, workingDirectory),
      );
      await expectLater(
        harness.service.publishWorkspace(
          workspaceRoot: harness.root.path,
          change: ReleaseChange.fix,
          consumers: [_consumerAt(harness.consumer)],
          pollInterval: Duration.zero,
        ),
        throwsA(
          _stoppedAt(
            'tag',
            package: 'wave_middle',
            message: contains('tag already exists'),
          ),
        ),
      );
      expect(
        harness.timeline.sublist(
          harness.timeline.indexOf('git tag wave_base-v0.1.5'),
        ),
        [
          'git tag wave_base-v0.1.5',
          'git push origin wave_base-v0.1.5',
          'poll wave_base',
          'poll wave_base',
          'git tag wave_middle-v0.2.4',
        ],
      );
    });

    test('a push failure leaves every later package untagged', () async {
      final harness = _harness(
        script: (executable, arguments, workingDirectory) =>
            executable == 'git' &&
                arguments.first == 'push' &&
                arguments.last == 'wave_middle-v0.2.4'
            ? ProcessResult(0, 128, '', 'remote rejected')
            : _defaultScript(executable, arguments, workingDirectory),
      );
      await expectLater(
        harness.service.publishWorkspace(
          workspaceRoot: harness.root.path,
          change: ReleaseChange.fix,
          consumers: [_consumerAt(harness.consumer)],
          pollInterval: Duration.zero,
        ),
        throwsA(
          _stoppedAt(
            'push',
            package: 'wave_middle',
            message: contains('remote rejected'),
          ),
        ),
      );
      expect(
        harness.timeline.last,
        'git push origin wave_middle-v0.2.4',
        reason: 'wave_leaf is never tagged',
      );
      expect(
        harness.timeline.where((entry) => entry.contains('wave_leaf')),
        [equals('poll wave_leaf')],
        reason: 'only the discovery poll — wave_leaf never mutates',
      );
    });

    test('an exhausted propagation poll stops the wave', () async {
      final harness = _harness(
        responder: (package, attempt) => package == 'wave_middle'
            ? _listing(const ['0.2.3'])
            : _fixResponder(package, attempt),
      );
      await expectLater(
        harness.service.publishWorkspace(
          workspaceRoot: harness.root.path,
          change: ReleaseChange.fix,
          consumers: [_consumerAt(harness.consumer)],
          pollInterval: const Duration(milliseconds: 3),
          maxPollAttempts: 3,
        ),
        throwsA(
          _stoppedAt(
            'poll',
            package: 'wave_middle',
            message: contains('untagged and unpushed'),
          ),
        ),
      );
      expect(
        harness.timeline.sublist(
          harness.timeline.indexOf('git tag wave_middle-v0.2.4'),
        ),
        [
          'git tag wave_middle-v0.2.4',
          'git push origin wave_middle-v0.2.4',
          'poll wave_middle',
          'poll wave_middle',
          'poll wave_middle',
        ],
      );
      expect(
        harness.wait.waited,
        List.filled(3, const Duration(milliseconds: 3)),
        reason:
            'one wait for wave_base (2 polls) plus two for wave_middle (3 '
            'polls) — the wait runs BETWEEN attempts, never after the last',
      );
    });
  });
}
