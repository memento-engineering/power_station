// The LADDER REPORT — `ReleaseService.reportLadder` and the thin `dart release
// ladder` Command over it: per workspace package, the rung its current
// published version occupies, the counter at that rung, its last stable
// version, how many prereleases followed it, and whether that is over the
// shared staleness threshold.
//
// The report is READ-ONLY, so the suite proves the negative too: no process
// runs, no wait is requested, and no pubspec byte moves. Every seam is a
// recording Fake (Fakes, not mocks) — the suite never touches the network.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_grid_assets/dart_grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A Fake [HttpGetter] over the pub.dev package API: answers from a responder
/// keyed on the package name and records every GET, so a test can prove ONE
/// probe per package per call.
class _FakePubDev {
  _FakePubDev(this.responder);

  final HttpFetch Function(String package) responder;
  final calls = <String>[];

  Future<HttpFetch> call(Uri url) async {
    final package = url.pathSegments.last;
    calls.add(package);
    return responder(package);
  }
}

/// A Fake [ProcessRunner] that must never be reached — the report spawns
/// nothing.
class _FakeProcess {
  final calls = <List<String>>[];

  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    calls.add([executable, ...arguments]);
    return ProcessResult(0, 0, '', '');
  }
}

/// A Fake [ReleaseWait] that must never be reached — the report polls nothing.
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

/// One publishable (or, with [publishable] false, deliberately unpublishable)
/// workspace member.
typedef _Member = ({String dir, String name, String version, bool publishable});

_Member _member(String name, String version, {bool publishable = true}) =>
    (dir: name, name: name, version: version, publishable: publishable);

/// Writes a pub workspace declaring [members] IN THE GIVEN ORDER (which the
/// fixtures keep deliberately unsorted, so a package-name-sorted report cannot
/// be a declaration-order one).
Directory _writeWorkspace(List<_Member> members) {
  final root = Directory.systemTemp.createTempSync('ladder-report-');
  addTearDown(() => root.delete(recursive: true));
  final rootPubspec = StringBuffer()
    ..writeln('name: ladder_workspace')
    ..writeln('publish_to: none')
    ..writeln('environment:')
    ..writeln('  sdk: ^3.11.0')
    ..writeln('workspace:');
  for (final member in members) {
    rootPubspec.writeln('  - packages/${member.dir}');
  }
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('$rootPubspec');
  for (final member in members) {
    final directory = Directory(p.join(root.path, 'packages', member.dir))
      ..createSync(recursive: true);
    final pubspec = StringBuffer()
      ..writeln('name: ${member.name}')
      ..writeln('version: ${member.version}')
      ..writeln('resolution: workspace');
    if (!member.publishable) pubspec.writeln('publish_to: none');
    pubspec
      ..writeln('environment:')
      ..writeln('  sdk: ^3.11.0');
    File(p.join(directory.path, 'pubspec.yaml')).writeAsStringSync('$pubspec');
  }
  return root;
}

/// The report harness: a fixture workspace plus the three recording seams.
({
  Directory root,
  _FakePubDev pubDev,
  _FakeProcess process,
  _FakeWait wait,
  ReleaseService service,
})
_harness(List<_Member> members, HttpFetch Function(String package) responder) {
  final root = _writeWorkspace(members);
  final pubDev = _FakePubDev(responder);
  final process = _FakeProcess();
  final wait = _FakeWait();
  return (
    root: root,
    pubDev: pubDev,
    process: process,
    wait: wait,
    service: ReleaseService(
      runProcess: process.call,
      httpGet: pubDev.call,
      wait: wait.call,
    ),
  );
}

/// Every `pubspec.yaml` under [root], as raw bytes — the mutation probe.
Map<String, List<int>> _pubspecBytes(Directory root) => {
  for (final entity in root.listSync(recursive: true))
    if (entity is File && p.basename(entity.path) == 'pubspec.yaml')
      entity.path: entity.readAsBytesSync(),
};

ReleaseLadderPackage _record(ReleaseLadderReport report, String package) =>
    report.packages.firstWhere((record) => record.package == package);

/// The four-member fixture: a package that legally stepped DOWN a rung, one
/// that has never been published, one sitting on a stable version, and one the
/// workspace declares unpublishable.
final _mixedMembers = [
  _member('ladder_zulu', '0.2.0-dev.3'),
  _member('ladder_private', '0.9.0', publishable: false),
  _member('ladder_alpha', '0.2.0-beta.2'),
  _member('ladder_stable', '0.2.1'),
  _member('ladder_mike', '0.1.0'),
];

HttpFetch _mixedResponder(String package) => switch (package) {
  // Published in this order: the rc came FIRST and the beta demoted off it, so
  // the current version is NOT the semver-greatest one.
  'ladder_alpha' => _listing(const [
    '0.1.9',
    '0.2.0-dev.1',
    '0.2.0-dev.2',
    '0.2.0-rc.5',
    '0.2.0-beta.1',
  ]),
  'ladder_zulu' => _listing(const ['0.1.0', '0.2.0-dev.1', '0.2.0-dev.2']),
  'ladder_stable' => _listing(const ['0.1.0', '0.2.0']),
  'ladder_mike' => _unpublished,
  _ => throw StateError('unexpected pub.dev read for $package'),
};

void main() {
  group('the workspace ladder report', () {
    test(
      'ladder report projects publication-order facts for every package',
      () async {
        final harness = _harness(_mixedMembers, _mixedResponder);

        final report = await harness.service.reportLadder(
          workspaceRoot: harness.root.path,
        );

        expect(
          report.packages.map((record) => record.package),
          ['ladder_alpha', 'ladder_mike', 'ladder_stable', 'ladder_zulu'],
          reason:
              'every PUBLISHABLE member, package-name sorted — and never the '
              'unpublishable ladder_private, which cannot reach pub.dev',
        );
        expect(report.totalPackages, 4);
        expect(report.isComplete, isTrue);
        expect(
          report.workspaceRoot,
          p.normalize(p.absolute(harness.root.path)),
        );

        final alpha = _record(report, 'ladder_alpha');
        expect(alpha.currentPublishedVersion.toString(), '0.2.0-beta.1');
        expect(
          alpha.rung,
          ReleaseRung.beta,
          reason:
              'pub.dev lists 0.2.0-rc.5 BEFORE 0.2.0-beta.1, and publication '
              'order is what says where the package sits now — reading the '
              'semver-greatest version would report a rung it stepped down from',
        );
        expect(alpha.rungCounter, 1);
        expect(alpha.hasPublishedVersion, isTrue);
        expect(alpha.hasStableVersion, isTrue);
        expect(alpha.lastStableVersion.toString(), '0.1.9');
        expect(alpha.prereleasesSinceStable, 4);
        expect(alpha.isOverStalenessThreshold, isFalse);

        final zulu = _record(report, 'ladder_zulu');
        expect(zulu.rung, ReleaseRung.dev);
        expect(zulu.rungCounter, 2);
        expect(zulu.lastStableVersion.toString(), '0.1.0');
        expect(zulu.prereleasesSinceStable, 2);

        final stable = _record(report, 'ladder_stable');
        expect(stable.rung, ReleaseRung.stable);
        expect(stable.rungCounter, 0);
        expect(stable.currentPublishedVersion.toString(), '0.2.0');
        expect(stable.lastStableVersion.toString(), '0.2.0');
        expect(stable.prereleasesSinceStable, 0);
        expect(stable.isOverStalenessThreshold, isFalse);

        final unpublished = _record(report, 'ladder_mike');
        expect(unpublished.hasPublishedVersion, isFalse);
        expect(unpublished.currentPublishedVersion, isNull);
        expect(unpublished.rung, isNull);
        expect(unpublished.rungCounter, 0);
        expect(unpublished.prereleasesSinceStable, 0);
        expect(unpublished.isOverStalenessThreshold, isFalse);

        expect(
          harness.pubDev.calls,
          ['ladder_alpha', 'ladder_mike', 'ladder_stable', 'ladder_zulu'],
          reason: 'one registry read per publishable package, and no other',
        );
        expect(harness.process.calls, isEmpty);
        expect(harness.wait.waited, isEmpty);
      },
    );

    test('staleness flips at the shared demotion threshold', () async {
      // The counts are derived from the ONE threshold the demotion mechanism
      // applies, so this suite cannot drift from it.
      List<String> under(int prereleases) => [
        '0.1.0',
        for (var counter = 1; counter <= prereleases; counter++)
          '0.2.0-dev.$counter',
      ];
      final harness = _harness(
        [
          _member('ladder_fresh', '0.2.0-dev.1'),
          _member('ladder_stale', '0.2.0-dev.1'),
        ],
        (package) => switch (package) {
          'ladder_fresh' => _listing(under(kStaleRcDemotionThreshold - 1)),
          'ladder_stale' => _listing(under(kStaleRcDemotionThreshold)),
          _ => throw StateError('unexpected pub.dev read for $package'),
        },
      );

      final report = await harness.service.reportLadder(
        workspaceRoot: harness.root.path,
      );

      final fresh = _record(report, 'ladder_fresh');
      expect(fresh.prereleasesSinceStable, kStaleRcDemotionThreshold - 1);
      expect(
        fresh.isOverStalenessThreshold,
        isFalse,
        reason: 'one short of the threshold is not over it',
      );
      expect(fresh.toJson()['isOverStalenessThreshold'], isFalse);

      final stale = _record(report, 'ladder_stale');
      expect(stale.prereleasesSinceStable, kStaleRcDemotionThreshold);
      expect(
        stale.isOverStalenessThreshold,
        isTrue,
        reason: 'the threshold itself is over it — the boundary is inclusive',
      );
      expect(stale.toJson()['isOverStalenessThreshold'], isTrue);
    });

    test('no stable publication is explicit in the model and JSON', () async {
      final harness = _harness(
        [
          _member('ladder_never', '0.1.0-beta.2'),
          _member('ladder_unpublished', '0.1.0'),
        ],
        (package) => switch (package) {
          'ladder_never' => _listing(const [
            '0.1.0-dev.1',
            '0.1.0-dev.2',
            '0.1.0-beta.1',
          ]),
          'ladder_unpublished' => _unpublished,
          _ => throw StateError('unexpected pub.dev read for $package'),
        },
      );

      final report = await harness.service.reportLadder(
        workspaceRoot: harness.root.path,
      );

      final never = _record(report, 'ladder_never');
      expect(never.hasStableVersion, isFalse);
      expect(never.lastStableVersion, isNull);
      expect(
        never.prereleasesSinceStable,
        3,
        reason: 'with no stable version, every published prerelease counts',
      );
      expect(never.hasPublishedVersion, isTrue);
      expect(never.currentPublishedVersion.toString(), '0.1.0-beta.1');

      final json = never.toJson();
      expect(
        json.containsKey('lastStableVersion'),
        isTrue,
        reason: 'the key is always present, so absence is explicit',
      );
      expect(json['lastStableVersion'], isNull);
      expect(json['lastStableVersion'], isNot(''));
      expect(json['hasStableVersion'], isFalse);
      expect(json['prereleasesSinceStable'], 3);

      final unpublished = _record(report, 'ladder_unpublished').toJson();
      expect(unpublished.containsKey('currentPublishedVersion'), isTrue);
      expect(unpublished['currentPublishedVersion'], isNull);
      expect(unpublished.containsKey('rung'), isTrue);
      expect(unpublished['rung'], isNull);
      expect(unpublished['hasPublishedVersion'], isFalse);
    });

    test(
      'ladder report is repeatable, concurrent, and mutation-free',
      () async {
        final harness = _harness(_mixedMembers, _mixedResponder);
        final before = _pubspecBytes(harness.root);

        final reports = await Future.wait([
          harness.service.reportLadder(workspaceRoot: harness.root.path),
          harness.service.reportLadder(workspaceRoot: harness.root.path),
        ]);

        expect(
          jsonEncode(reports.first.toJson()),
          jsonEncode(reports.last.toJson()),
          reason: 'two concurrent reads of the same registry answer the same',
        );
        expect(
          harness.pubDev.calls.length,
          8,
          reason:
              'four publishable packages, one GET each, per call — a '
              'time-varying read never suppresses a repeat',
        );
        expect(
          harness.process.calls,
          isEmpty,
          reason: 'no tag, no push, no dry-run: the report spawns nothing',
        );
        expect(
          harness.wait.waited,
          isEmpty,
          reason: 'no propagation polling: the report waits on nothing',
        );
        expect(_pubspecBytes(harness.root), before);
      },
    );

    test('the report bounds its output and names what it withheld', () async {
      // Fifty uniform members: more records than one capped rendering carries.
      final members = [
        for (var index = 0; index < 50; index++)
          _member('ladder_pkg_${index.toString().padLeft(2, '0')}', '0.2.0'),
      ];
      final harness = _harness(
        members,
        (package) => _listing(const ['0.1.0', '0.2.0-dev.1', '0.2.0']),
      );

      final complete = await harness.service.reportLadder(
        workspaceRoot: harness.root.path,
      );
      expect(
        complete.packages.length,
        50,
        reason: 'the SERVICE answers in full — the cap is a rendering bound',
      );
      expect(complete.withheld, isNull);
      expect(complete.show, isNull);

      final window = complete.bounded();
      expect(window.packages.length, lessThan(50));
      expect(window.offset, 0);
      expect(window.withheldPackages, 50 - window.packages.length);
      expect(
        window.withheld,
        '${window.withheldPackages} of 50 package records',
      );
      expect(window.show, 'rerun with --skip ${window.packages.length}');
      expect(
        utf8.encode('${jsonEncode(window.toJson())}\n').length,
        lessThanOrEqualTo(kLadderOutputCapBytes),
      );

      final next = complete.bounded(skip: window.packages.length);
      expect(
        next.packages.first.package,
        complete.packages[window.packages.length].package,
        reason: 'the marker\'s --skip reaches the first withheld record',
      );

      // Both renderings of the same window are bounded, and the plain one
      // carries the marker as its own line rather than dropping it.
      final out = StringBuffer();
      final runner = CommandRunner<int>('t', 'test')
        ..addCommand(
          ReleaseCommand(
            service: harness.service,
            out: out,
            err: StringBuffer(),
          ),
        );
      expect(
        await runner.run([
          'release',
          'ladder',
          '--workspace',
          harness.root.path,
        ]),
        0,
      );
      final lines = const LineSplitter().convert('$out');
      expect(lines.length, window.packages.length + 1);
      expect(lines.first, startsWith('ladder_pkg_00 0.2.0 rung=stable '));
      expect(lines.last, '${window.withheld} withheld — ${window.show}');
      expect(
        utf8.encode('$out').length,
        lessThanOrEqualTo(kLadderOutputCapBytes),
      );
    });
  });

  group('the `dart release ladder` command', () {
    test('release ladder --json emits exactly the report object', () async {
      final harness = _harness(_mixedMembers, _mixedResponder);
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = CommandRunner<int>('t', 'test')
        ..addCommand(
          ReleaseCommand(service: harness.service, out: out, err: err),
        );

      final code = await runner.run([
        'release',
        'ladder',
        '--workspace',
        harness.root.path,
        '--json',
      ]);

      expect(code, 0);
      expect(err.toString(), isEmpty);
      final lines = const LineSplitter().convert('$out');
      expect(lines.length, 1, reason: 'one JSON object, no transcript');
      final expected = (await harness.service.reportLadder(
        workspaceRoot: harness.root.path,
      )).bounded();
      expect(
        jsonDecode(lines.single),
        jsonDecode(jsonEncode(expected.toJson())),
      );
      expect((jsonDecode(lines.single) as Map<String, Object?>).keys, [
        'workspaceRoot',
        'packages',
        'offset',
        'totalPackages',
        'withheldPackages',
        'withheld',
        'show',
      ]);

      expect(
        DartCommand().subcommands['release']!.subcommands.keys,
        contains('ladder'),
        reason: 'the op is reachable on the runner a station installs',
      );
    });

    test('release ladder fails closed without partial JSON', () async {
      for (final broken in [
        const HttpFetch(statusCode: 503, body: 'upstream is down'),
        const HttpFetch(statusCode: 200, body: 'not json at all'),
      ]) {
        final harness = _harness(
          [_member('ladder_first', '0.2.0'), _member('ladder_second', '0.2.0')],
          (package) => switch (package) {
            'ladder_first' => _listing(const ['0.1.0', '0.2.0']),
            'ladder_second' => broken,
            _ => throw StateError('unexpected pub.dev read for $package'),
          },
        );
        final out = StringBuffer();
        final err = StringBuffer();
        final runner = CommandRunner<int>('t', 'test')
          ..addCommand(
            ReleaseCommand(service: harness.service, out: out, err: err),
          );

        final code = await runner.run([
          'release',
          'ladder',
          '--workspace',
          harness.root.path,
          '--json',
        ]);

        expect(code, 1);
        expect(
          out.toString(),
          isEmpty,
          reason:
              'ladder_first was read successfully — a half-read workspace is '
              'still no answer, so no partial JSON reaches stdout',
        );
        expect(err.toString(), startsWith('release ladder: '));
        expect(err.toString(), contains('ladder_second'));
      }
    });

    test('release ladder refuses a --skip that is not an index', () async {
      final harness = _harness(_mixedMembers, _mixedResponder);
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = CommandRunner<int>('t', 'test')
        ..addCommand(
          ReleaseCommand(service: harness.service, out: out, err: err),
        );

      final code = await runner.run([
        'release',
        'ladder',
        '--workspace',
        harness.root.path,
        '--skip',
        '-3',
      ]);

      expect(code, 64, reason: 'an argv refusal keeps the runner convention');
      expect(out.toString(), isEmpty);
      expect(err.toString(), startsWith('release ladder: --skip'));
      expect(harness.pubDev.calls, isEmpty, reason: 'refused before any read');
    });
  });
}
