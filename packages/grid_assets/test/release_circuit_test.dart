// The RELEASE circuit — the gated pipeline that makes publishing to pub.dev
// non-optional.
//
// Offline by construction. Every leg runs through the injected
// [ReleaseCommandInvoker] seam: most probes hand it a recording Fake with
// canned vended-command JSON, and the two probes that must prove a REAL vended
// command runs (the declared-floor scrub and the propagation barrier) hand the
// real `InProcessReleaseCommandInvoker` a `ReleaseService` over process,
// pub.dev and wait Fakes. No network, no git, no pub — and no process at all.
//
// Checked-in paths resolve off `packageRoot()`; fixture trees are temporary
// directories. Nothing here reads or assigns the process working directory.
import 'dart:convert';
import 'dart:io';

import 'package:dart_grid_assets/dart_grid_assets.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/package_root.dart';

const String _beadId = 'pow-release';
const String _diffRef = 'origin/main';
const String _base = 'base_pack';
const String _dependent = 'dependent_pack';
const String _baseDir = 'packages/base_pack';
const String _dependentDir = 'packages/dependent_pack';
const String _version = '0.1.0-dev.1';

String _node(String stepId) => '$_beadId/release/$stepId';

/// The default two-package wave: a base and the dependent that resolves it.
ReleaseCircuitRequest _request({
  String workspaceRoot = '/w/release',
  ReleaseRung baseRung = ReleaseRung.dev,
  ReleaseRung dependentRung = ReleaseRung.dev,
  bool humanPromotionIntent = false,
  String? consumersManifest,
  ReleaseChange change = ReleaseChange.fix,
}) => ReleaseCircuitRequest(
  workspaceRoot: workspaceRoot,
  diff: _diffRef,
  change: change,
  consumersManifest: consumersManifest,
  humanPromotionIntent: humanPromotionIntent,
  packages: [
    ReleasePackageTarget(
      package: _base,
      directory: _baseDir,
      targetRung: baseRung,
    ),
    ReleasePackageTarget(
      package: _dependent,
      directory: _dependentDir,
      targetRung: dependentRung,
    ),
  ],
);

// ── the driver ──────────────────────────────────────────────────────────────

/// One walk of [kReleaseCircuit] in graph order: which steps ran, the receipts
/// they recorded, and the verdict that STOPPED the walk (null when it finished).
typedef _RunReport = ({
  List<String> ran,
  Map<String, Map<String, String>> results,
  Object? stop,
});

/// Drives the release circuit's steps in their declared order, threading each
/// node's recorded payload into the next step's ambient [SiblingView] exactly as
/// the engine does — and STOPPING at the first non-positive verdict, exactly as
/// the graph's `dependsOn` chain does.
Future<_RunReport> _drive(
  ReleaseCircuitRequest request,
  ReleaseCommandInvoker invoker,
) async {
  final gate = ReleaseGateCapability(invoker);
  const promotion = ReleasePromotionRouteCapability();
  final results = <String, Map<String, String>>{};
  final ran = <String>[];
  Object? stop;
  for (final step in kReleaseCircuit.steps.whereType<CapabilityStep>()) {
    final context = FakeTreeContext(
      values: <Type, Object>{
        ReleaseCircuitRequest: request,
        SiblingView: SiblingView(results: Map.of(results)),
      },
    );
    final args = stepArgs(_node(step.stepId), params: step.params);
    ran.add(step.stepId);
    if (step.capabilityId == kReleasePromotionRouteCapabilityId) {
      final RouteVerdict verdict;
      try {
        verdict = await promotion.route(context, args);
      } on RouteFailure catch (failure) {
        stop = failure;
        break;
      }
      if (verdict is! Advance) {
        stop = verdict;
        break;
      }
      final payload = verdict.payload;
      if (payload != null) results[args.nodePath] = payload;
    } else {
      final outcome = await gate.run(context, args);
      if (outcome is! Ok) {
        stop = outcome;
        break;
      }
      final payload = outcome.payload;
      if (payload != null) results[args.nodePath] = payload;
    }
  }
  return (ran: ran, results: results, stop: stop);
}

/// The receipt a step recorded, decoded.
Map<String, Object?> _receipt(_RunReport report, String stepId) {
  final raw = report.results[_node(stepId)]?[kReleaseReceiptKey];
  if (raw == null) fail('no `$stepId` receipt in ${report.results.keys}');
  return jsonDecode(raw) as Map<String, Object?>;
}

// ── the vended-command Fake ─────────────────────────────────────────────────

/// One package's ladder facts, as the vended ladder report would carry them.
class _LadderFact {
  const _LadderFact({this.published = false, this.version, this.rung});

  final bool published;
  final String? version;
  final String? rung;
}

/// The recording Fake for the vended release commands: it logs every argv and
/// answers with canned JSON in the vended shapes.
///
/// [delegateOperations] routes named operations to [delegate] instead — the seam
/// the two probes that must exercise a REAL vended command use, so they still
/// ride the same one invoker interface the circuit composes.
class _FakeReleaseCommandInvoker implements ReleaseCommandInvoker {
  _FakeReleaseCommandInvoker({
    required this.request,
    Map<String, _LadderFact>? ladder,
    List<String>? workspaceOrder,
    List<Map<String, Object?>>? wavePackages,
    this.publishWavePackages,
    this.pollPublished = true,
    this.delegate,
    this.delegateOperations = const <String>{},
  }) : ladder =
           ladder ??
           {for (final name in request.packageNames) name: const _LadderFact()},
       workspaceOrder = workspaceOrder ?? request.packageNames,
       wavePackages =
           wavePackages ??
           [
             for (final target in request.packages)
               wavePackage(
                 package: target.package,
                 directory: target.directory,
                 rung: target.targetRung.name,
               ),
           ];

  final ReleaseCircuitRequest request;
  final Map<String, _LadderFact> ladder;
  final List<String> workspaceOrder;
  final List<Map<String, Object?>> wavePackages;

  /// The wave the IRREVERSIBLE run answers with, when it must differ from the
  /// one the preflight cleared; null ⇒ both runs answer [wavePackages].
  final List<Map<String, Object?>>? publishWavePackages;
  final bool pollPublished;
  final ReleaseCommandInvoker? delegate;
  final Set<String> delegateOperations;

  /// Every argv the circuit invoked, in order.
  final List<List<String>> calls = <List<String>>[];

  /// One vended wave package record.
  static Map<String, Object?> wavePackage({
    required String package,
    required String directory,
    String version = _version,
    String rung = 'dev',
    List<String> dependencies = const <String>[],
    String? predecessor,
  }) => <String, Object?>{
    'package': package,
    'directory': directory,
    'publishedPredecessor': predecessor,
    'localVersion': version,
    'dependencies': dependencies,
    'rung': rung,
    'tag': '$package-v$version',
  };

  @override
  Future<ReleaseCommandInvocation> run(List<String> arguments) async {
    calls.add(List<String>.unmodifiable(arguments));
    final operation = arguments.length > 1 ? arguments[1] : '';
    if (delegateOperations.contains(operation)) {
      return delegate!.run(arguments);
    }
    return _ok(_answer(operation, arguments));
  }

  String? _option(List<String> arguments, String flag) {
    final index = arguments.indexOf(flag);
    return index < 0 || index + 1 >= arguments.length
        ? null
        : arguments[index + 1];
  }

  Object _answer(String operation, List<String> arguments) {
    switch (operation) {
      case 'discover':
        return <String, Object?>{
          'workspaceRoot': request.workspaceRoot,
          'diff': request.diff,
          'candidates': request.packageNames,
          'changed': request.packageNames,
        };
      case 'ladder':
        return _ladderPage(int.parse(_option(arguments, '--skip')!));
      case 'plan':
        final package = _option(arguments, '--package')!;
        final current = _option(arguments, '--current')!;
        return <String, Object?>{
          'current': current,
          'next': _version,
          'change': _option(arguments, '--change')!,
          'rung': _option(arguments, '--rung')!,
          'promotionIntent': arguments.contains('--promotion-intent'),
          'requiresBreakingChangelog': false,
          'package': package,
          'tag': '$package-v$_version',
        };
      case 'scrub':
        return <String, Object?>{
          'root': _option(arguments, '--dir')!,
          'clean': true,
          'filesScanned': 3,
          'hits': <Object?>[],
          'declaredFloors': <String, Object?>{
            'candidate': p.basename(_option(arguments, '--dir')!),
            'pins': <Object?>[],
            'pubGetExitCode': 0,
            'analyzeExitCode': 0,
            'passed': true,
            'message': 'declared-floor validation passed',
            'stdout': '',
            'stderr': '',
          },
        };
      case 'classify':
        final package = _option(arguments, '--package')!;
        return <String, Object?>{
          'package': package,
          'baseline': '0.1.0-dev.1',
          'head': _version,
          'removed': <Object?>[],
          'changed': <Object?>[],
          'added': <Object?>[],
          'requiredChange': 'additive',
          'declaredChange': 'patch',
          'verdict': 'ok',
          'message': '$package: additive delta, patch bump',
        };
      case 'order':
        return <String, Object?>{'order': workspaceOrder};
      case 'dry-run':
        return <String, Object?>{
          'package': _option(arguments, '--package')!,
          'exitCode': 0,
          'warningCount': 0,
          'clean': true,
          'warnings': <Object?>[],
        };
      case 'publish':
        final dryRun = arguments.contains('--dry-run');
        return <String, Object?>{
          'workspaceRoot': request.workspaceRoot,
          'change': request.change.name,
          'promotionIntent': arguments.contains('--promotion-intent'),
          'dryRun': dryRun,
          'packages': dryRun
              ? wavePackages
              : (publishWavePackages ?? wavePackages),
        };
      case 'poll':
        final wanted = _option(arguments, '--version')!;
        return <String, Object?>{
          'package': _option(arguments, '--package')!,
          'wanted': wanted,
          'statusCode': 200,
          'versions': pollPublished ? <Object?>[wanted] : <Object?>[],
          'latest': pollPublished ? wanted : null,
          'isPublished': pollPublished,
        };
      default:
        fail('the circuit invoked an unknown operation: $operation');
    }
  }

  /// ONE record per page, so every probe exercises the bounded paged read.
  Map<String, Object?> _ladderPage(int skip) {
    final names = ladder.keys.toList()..sort();
    final window = names.skip(skip).take(1).toList();
    return <String, Object?>{
      'workspaceRoot': request.workspaceRoot,
      'packages': [
        for (final name in window)
          <String, Object?>{
            'package': name,
            'hasPublishedVersion': ladder[name]!.published,
            'currentPublishedVersion': ladder[name]!.version,
            'rung': ladder[name]!.rung,
            'rungCounter': 0,
            'hasStableVersion': false,
            'lastStableVersion': null,
            'prereleasesSinceStable': 0,
            'isOverStalenessThreshold': false,
          },
      ],
      'offset': skip,
      'totalPackages': names.length,
      'withheldPackages': names.length - window.length,
      'withheld': null,
      'show': null,
    };
  }
}

ReleaseCommandInvocation _ok(Object json) => ReleaseCommandInvocation(
  exitCode: 0,
  stdout: '${jsonEncode(json)}\n',
  stderr: '',
);

// ── the process / pub.dev / wait Fakes the REAL service rides ───────────────

/// A recording process Fake for [ReleaseService]: it answers `dart pub get`,
/// `dart analyze`, `dart pub publish --dry-run`, `git tag` and `git push`
/// without launching anything, and logs the tag and push events a propagation
/// probe reads.
class _FakeProcesses {
  _FakeProcesses({this.analyzeFailsIn = const <String>{}});

  /// Copy directories (named for their candidate package) whose declared-floor
  /// analyze must FAIL.
  final Set<String> analyzeFailsIn;

  /// The ordered timeline of everything the wave did.
  final List<String> events = <String>[];

  /// Packages whose tag reached the remote.
  final Set<String> pushed = <String>{};

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final argv = '$executable ${arguments.join(' ')}';
    if (executable == 'dart' && arguments.first == 'analyze') {
      final candidate = p.basename(workingDirectory ?? '');
      events.add('analyze:$candidate');
      return analyzeFailsIn.contains(candidate)
          ? ProcessResult(
              0,
              1,
              'error - lib/$candidate.dart:3:24 - The getter '
                  "'renamedApi' isn't defined - undefined_getter\n"
                  '1 issue found.',
              '',
            )
          : ProcessResult(0, 0, 'No issues found!', '');
    }
    if (executable == 'dart' && arguments.first == 'pub') {
      if (arguments.contains('publish')) {
        events.add('dry-run:${p.basename(workingDirectory ?? '')}');
        return ProcessResult(0, 0, 'Package has 0 warnings.', '');
      }
      events.add('pub-get:${p.basename(workingDirectory ?? '')}');
      return ProcessResult(0, 0, 'Got dependencies!', '');
    }
    if (executable == 'git' && arguments.first == 'tag') {
      events.add('tag:${arguments[1]}');
      return ProcessResult(0, 0, '', '');
    }
    if (executable == 'git' && arguments.first == 'push') {
      final tag = arguments.last;
      events.add('push:$tag');
      pushed.add(tag.substring(0, tag.lastIndexOf('-v')));
      return ProcessResult(0, 0, '', '');
    }
    fail('the release service launched an unexpected process: $argv');
  }
}

/// A pub.dev Fake that models PROPAGATION: a package nobody pushed is a 404,
/// and a package whose tag was pushed answers "not yet" exactly once before its
/// version appears in the versions list.
class _FakePubDev {
  _FakePubDev(this._processes, {required this.version});

  final _FakeProcesses _processes;
  final String version;
  final Map<String, int> _probes = <String, int>{};

  Future<HttpFetch> get(Uri url) async {
    final package = url.pathSegments.last;
    if (!_processes.pushed.contains(package)) {
      _processes.events.add('probe:$package:absent');
      return const HttpFetch(statusCode: 404, body: '{}');
    }
    final seen = (_probes[package] ?? 0) + 1;
    _probes[package] = seen;
    final published = seen >= 2;
    _processes.events.add(
      'probe:$package:${published ? 'published' : 'pending'}',
    );
    return HttpFetch(
      statusCode: 200,
      body: jsonEncode(<String, Object?>{
        'latest': published ? <String, Object?>{'version': version} : null,
        'versions': published
            ? <Object?>[
                <String, Object?>{'version': version},
              ]
            : <Object?>[],
      }),
    );
  }
}

/// A wait Fake: a wave suite never sleeps.
Future<void> _noWait(Duration duration) async {}

// ── fixture trees ───────────────────────────────────────────────────────────

void _writeFile(String path, String content) => File(path)
  ..createSync(recursive: true)
  ..writeAsStringSync(content);

/// A two-member pub workspace on disk: [dependent] declares [base] at
/// [declaredFloor].
String _workspaceFixture(
  Directory root, {
  required String base,
  required String dependent,
  required String declaredFloor,
  String version = _version,
}) {
  _writeFile(p.join(root.path, 'pubspec.yaml'), '''
name: release_fixture_workspace
publish_to: none
environment:
  sdk: ^3.11.0
workspace:
  - packages/$base
  - packages/$dependent
''');
  for (final member in <String>[base, dependent]) {
    final dir = p.join(root.path, 'packages', member);
    _writeFile(p.join(dir, 'pubspec.yaml'), '''
name: $member
version: $version
resolution: workspace
environment:
  sdk: ^3.11.0
${member == dependent ? 'dependencies:\n  $base: $declaredFloor\n' : ''}''');
    _writeFile(
      p.join(dir, 'lib', '$member.dart'),
      'const int ${member.replaceAll('_', '')}Answer = 1;\n',
    );
  }
  return root.path;
}

/// A mount for one release step, so a probe can resolve what the registry
/// actually binds the step's capability id to.
StepMount _mount(String stepId) {
  final step = kReleaseCircuit.stepById(stepId)! as CapabilityStep;
  return StepMount(
    step: step,
    nodePath: _node(stepId),
    circuit: kReleaseCircuit,
    circuitPath: '$_beadId/release',
    session: const SessionHandle('tgdog-s'),
    node: const NodeCursor(),
    key: ValueKey('${_node(stepId)}#0.0'),
  );
}

void main() {
  group('the release pipeline is a registered circuit', () {
    test('registers release beside existing circuits', () {
      final registry = buildCodeRegistry(overlaySourceRef: 'test');
      expect(identical(registry.circuit('release'), kReleaseCircuit), isTrue);
      // Registering it changes nothing about the circuits already there.
      for (final existing in const <String>[
        'code',
        'spec_review',
        'code_review',
        'landing',
      ]) {
        expect(registry.circuit(existing), isNotNull, reason: existing);
      }
      // Both release capability ids resolve — a station that roots the circuit
      // gets the real legs, not the fail-soft idle leaf.
      final gate = registry.host(_mount('scrub'));
      expect(gate, isA<CapabilityHost>());
      expect((gate as CapabilityHost).capability, isA<ReleaseGateCapability>());
      final promotion = registry.host(_mount('promotion'));
      expect(promotion, isA<CapabilityHost>());
      expect(
        (promotion as CapabilityHost).capability,
        isA<ReleasePromotionRouteCapability>(),
      );
    });

    test('the invoker is an injectable implementation seam', () async {
      final request = _request();
      final invoker = _FakeReleaseCommandInvoker(request: request);
      final registry = buildCodeRegistry(
        overlaySourceRef: 'test',
        releaseCommands: invoker,
      );
      final host = registry.host(_mount('discover')) as CapabilityHost;
      final capability = host.capability as ReleaseGateCapability;
      await capability.run(
        FakeTreeContext(values: <Type, Object>{ReleaseCircuitRequest: request}),
        stepArgs(_node('discover'), params: const {'operation': 'discover'}),
      );
      expect(invoker.calls.single.first, 'release');
      expect(invoker.calls.single[1], 'discover');
    });
  });

  group('the release pipeline composes the vended commands', () {
    test('calls only vended release commands in circuit order', () async {
      final request = _request();
      final invoker = _FakeReleaseCommandInvoker(
        request: request,
        ladder: const <String, _LadderFact>{
          _base: _LadderFact(
            published: true,
            version: '0.1.0-dev.1',
            rung: 'dev',
          ),
          _dependent: _LadderFact(),
        },
        workspaceOrder: const <String>['unrelated_pack', _base, _dependent],
        wavePackages: <Map<String, Object?>>[
          _FakeReleaseCommandInvoker.wavePackage(
            package: _base,
            directory: _baseDir,
            predecessor: '0.1.0-dev.1',
          ),
          _FakeReleaseCommandInvoker.wavePackage(
            package: _dependent,
            directory: _dependentDir,
            dependencies: const <String>[_base],
          ),
        ],
      );

      final report = await _drive(request, invoker);
      expect(report.stop, isNull, reason: '${report.stop}');
      expect(report.ran, [
        'discover',
        'ladder',
        'promotion',
        'plan',
        'scrub',
        'classify',
        'order',
        'dry-run',
        'preflight',
        'publish',
        'poll',
      ]);

      expect(invoker.calls, <List<String>>[
        [
          'release',
          'discover',
          '--workspace',
          '/w/release',
          '--diff',
          _diffRef,
          '--json',
        ],
        [
          'release',
          'ladder',
          '--workspace',
          '/w/release',
          '--skip',
          '0',
          '--json',
        ],
        [
          'release',
          'ladder',
          '--workspace',
          '/w/release',
          '--skip',
          '1',
          '--json',
        ],
        // The dependent is a FIRST publication, so the two baseline-dependent
        // legs run no command for it at all.
        [
          'release',
          'plan',
          '--package',
          _base,
          '--current',
          '0.1.0-dev.1',
          '--change',
          'fix',
          '--rung',
          'dev',
          '--json',
        ],
        ['release', 'scrub', '--dir', '/w/release/$_baseDir', '--json'],
        ['release', 'scrub', '--dir', '/w/release/$_dependentDir', '--json'],
        [
          'release',
          'classify',
          '--dir',
          '/w/release/$_baseDir',
          '--package',
          _base,
          '--json',
        ],
        ['release', 'order', '--workspace', '/w/release', '--json'],
        [
          'release',
          'dry-run',
          '--dir',
          '/w/release/$_baseDir',
          '--package',
          _base,
          '--json',
        ],
        [
          'release',
          'dry-run',
          '--dir',
          '/w/release/$_dependentDir',
          '--package',
          _dependent,
          '--json',
        ],
        [
          'release',
          'publish',
          '--workspace',
          '/w/release',
          '--change',
          'fix',
          '--dry-run',
          '--json',
        ],
        [
          'release',
          'publish',
          '--workspace',
          '/w/release',
          '--change',
          'fix',
          '--json',
        ],
        [
          'release',
          'poll',
          '--package',
          _base,
          '--version',
          _version,
          '--json',
        ],
        [
          'release',
          'poll',
          '--package',
          _dependent,
          '--version',
          _version,
          '--json',
        ],
      ]);

      // The first publication is RECORDED as inapplicable, never skipped.
      expect(
        (_receipt(report, 'plan')['packages']! as Map)[_dependent],
        <String, Object?>{'firstRelease': true},
      );
      expect(
        (_receipt(report, 'classify')['packages']! as Map)[_dependent],
        <String, Object?>{'firstRelease': true},
      );
      expect(_receipt(report, 'ladder')['pages'], 2);

      // The composition fence: the circuit reaches the release logic ONLY
      // through the vended command group, never through a service method.
      final source = File(
        p.join(packageRoot(), 'lib', 'src', 'code', 'release.dart'),
      ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
      expect(source, contains('ReleaseCommand('));
      for (final method in const <String>[
        'discoverWorkspace',
        'reportLadder',
        'planVersion',
        'tagFor',
        'createGitTag',
        'validateConsumers',
        'validateDeclaredFloors',
        'promoteTag',
        'scrubPackage',
        'scrubDir',
        'classifyRelease',
        'publishOrder',
        'publishOrderFromMelosWorkspace',
        'dryRun',
        'poll',
        'publishWorkspace',
      ]) {
        expect(
          source,
          isNot(matches(RegExp('[Ss]ervice\\.$method\\s*\\('))),
          reason: 'the circuit calls the release service method $method',
        );
      }
    });

    test('release graph has no committee round', () {
      final steps = kReleaseCircuit.steps;
      expect(steps.whereType<SubCircuitStep>(), isEmpty);
      expect(
        [for (final step in steps) step.stepId],
        const <String>[
          'discover',
          'ladder',
          'promotion',
          'plan',
          'scrub',
          'classify',
          'order',
          'dry-run',
          'preflight',
          'publish',
          'poll',
        ],
      );
      expect(kReleaseCircuit.terminalStepId, 'poll');
      // Strictly linear: every node waits on exactly its predecessor.
      for (var i = 0; i < steps.length; i++) {
        expect(
          steps[i].dependsOn,
          i == 0 ? isEmpty : <String>{steps[i - 1].stepId},
          reason: steps[i].stepId,
        );
      }
      final capabilityIds = {
        for (final step in steps.whereType<CapabilityStep>()) step.capabilityId,
      };
      expect(capabilityIds, {
        kReleaseGateCapabilityId,
        kReleasePromotionRouteCapabilityId,
      });
      for (final banned in const <String>[
        'committee',
        'critic',
        'review',
        'rubric',
        'inference',
      ]) {
        for (final id in capabilityIds) {
          expect(id, isNot(contains(banned)));
        }
        for (final step in steps) {
          expect(step.stepId, isNot(contains(banned)));
          for (final entry in step.params.entries) {
            expect('${entry.key}=${entry.value}', isNot(contains(banned)));
          }
        }
      }
    });
  });

  group('the gates are mandatory', () {
    test('under-declared floor fails before publish', () async {
      final root = Directory.systemTemp.createTempSync('release-floors-');
      addTearDown(() => root.deleteSync(recursive: true));
      // `floor_dependent` promises `floor_base ^0.1.0` while the API it calls
      // only arrived at 0.2.0 — so the candidate does NOT compile against the
      // minimum it declares, and the declared-floors analyze refuses.
      final workspaceRoot = _workspaceFixture(
        root,
        base: 'floor_base',
        dependent: 'floor_dependent',
        declaredFloor: '^0.1.0',
      );
      final processes = _FakeProcesses(
        analyzeFailsIn: const <String>{'floor_dependent'},
      );
      final request = ReleaseCircuitRequest(
        workspaceRoot: workspaceRoot,
        diff: _diffRef,
        change: ReleaseChange.fix,
        packages: const [
          ReleasePackageTarget(
            package: 'floor_base',
            directory: 'packages/floor_base',
            targetRung: ReleaseRung.dev,
          ),
          ReleasePackageTarget(
            package: 'floor_dependent',
            directory: 'packages/floor_dependent',
            targetRung: ReleaseRung.dev,
          ),
        ],
      );
      final invoker = _FakeReleaseCommandInvoker(
        request: request,
        // The scrub leg drives the REAL vended command over the Fakes.
        delegate: InProcessReleaseCommandInvoker(
          service: ReleaseService(
            runProcess: processes.run,
            httpGet: (_) async => const HttpFetch(statusCode: 404, body: '{}'),
            wait: _noWait,
          ),
        ),
        delegateOperations: const <String>{'scrub'},
      );

      final report = await _drive(request, invoker);

      expect(report.ran.last, 'scrub');
      final stop = report.stop;
      expect(stop, isA<Failed>());
      final refusal = stop! as Failed;
      expect(refusal.reason, contains('floor_dependent'));
      expect(refusal.reason, contains('declared-floor validation'));
      expect(refusal.kind, CapabilityFailureKind.work);

      // The irreversible half never ran: no preflight, no wave, no poll — and
      // no tag and no push reached the process seam.
      final invoked = {for (final call in invoker.calls) call[1]};
      expect(invoked, isNot(contains('preflight')));
      expect(invoked, isNot(contains('publish')));
      expect(invoked, isNot(contains('poll')));
      expect(
        processes.events.where(
          (event) => event.startsWith('tag:') || event.startsWith('push:'),
        ),
        isEmpty,
      );
      // The gate DID run for real: both candidates were analyzed at their
      // declared floors.
      expect(processes.events, contains('analyze:floor_base'));
      expect(processes.events, contains('analyze:floor_dependent'));
    });

    test('publishes a dependency-first wave', () async {
      final request = _request();
      final wave = <Map<String, Object?>>[
        _FakeReleaseCommandInvoker.wavePackage(
          package: _base,
          directory: _baseDir,
        ),
        _FakeReleaseCommandInvoker.wavePackage(
          package: _dependent,
          directory: _dependentDir,
          dependencies: const <String>[_base],
        ),
      ];
      final invoker = _FakeReleaseCommandInvoker(
        request: request,
        workspaceOrder: const <String>['unrelated_pack', _base, _dependent],
        wavePackages: wave,
      );

      final report = await _drive(request, invoker);
      expect(report.stop, isNull, reason: '${report.stop}');
      expect(_receipt(report, 'order')['projected'], <String>[
        _base,
        _dependent,
      ]);
      for (final stepId in const <String>['preflight', 'publish']) {
        final packages = _receipt(report, stepId)['packages']! as List;
        expect(
          [for (final fact in packages) (fact as Map)['package']],
          <String>[_base, _dependent],
        );
      }
      expect(_receipt(report, 'preflight')['dryRun'], isTrue);
      expect(_receipt(report, 'publish')['dryRun'], isFalse);
      // The poll barrier follows the same dependency-first order.
      expect(
        [
          for (final call in invoker.calls)
            if (call[1] == 'poll') call[call.indexOf('--package') + 1],
        ],
        <String>[_base, _dependent],
      );

      // A wave that would publish the dependent FIRST is refused before the
      // irreversible leg, against the workspace's own order.
      final mismatched = _FakeReleaseCommandInvoker(
        request: request,
        workspaceOrder: const <String>[_base, _dependent],
        wavePackages: wave.reversed.toList(),
      );
      final refused = await _drive(request, mismatched);
      expect(refused.ran.last, 'preflight');
      expect(refused.stop, isA<Failed>());
      expect((refused.stop! as Failed).reason, contains('dependency order'));
      expect({
        for (final call in mismatched.calls) call[1],
      }, isNot(contains('poll')));

      // And the SAME check binds the irreversible run: a wave that cleared its
      // preflight in dependency order and then ran in another one is refused
      // before a single poll, never reconciled after the fact.
      final drifted = _FakeReleaseCommandInvoker(
        request: request,
        workspaceOrder: const <String>[_base, _dependent],
        wavePackages: wave,
        publishWavePackages: wave.reversed.toList(),
      );
      final stopped = await _drive(request, drifted);
      expect(stopped.ran.last, 'publish');
      expect((stopped.stop! as Failed).reason, contains('dependency order'));
      expect({
        for (final call in drifted.calls) call[1],
      }, isNot(contains('poll')));
    });

    test(
      'the irreversible wave must match the plan the preflight cleared',
      () async {
        final request = _request();
        final wave = <Map<String, Object?>>[
          _FakeReleaseCommandInvoker.wavePackage(
            package: _base,
            directory: _baseDir,
          ),
          _FakeReleaseCommandInvoker.wavePackage(
            package: _dependent,
            directory: _dependentDir,
            dependencies: const <String>[_base],
          ),
        ];
        // Same packages, same order — a different VERSION, so only the fact
        // comparison can catch it.
        final drifted = _FakeReleaseCommandInvoker(
          request: request,
          workspaceOrder: const <String>[_base, _dependent],
          wavePackages: wave,
          publishWavePackages: <Map<String, Object?>>[
            _FakeReleaseCommandInvoker.wavePackage(
              package: _base,
              directory: _baseDir,
              version: '0.2.0-dev.1',
            ),
            wave[1],
          ],
        );
        final report = await _drive(request, drifted);
        expect(report.ran.last, 'publish');
        final reason = (report.stop! as Failed).reason;
        expect(reason, contains('position 0'));
        expect(reason, contains('0.2.0-dev.1'));
        expect(reason, contains('nothing publishes on a plan no gate saw'));
        expect({
          for (final call in drifted.calls) call[1],
        }, isNot(contains('poll')));
      },
    );

    test('waits for pub.dev before a dependent tag', () async {
      final root = Directory.systemTemp.createTempSync('release-wave-');
      addTearDown(() => root.deleteSync(recursive: true));
      final workspaceRoot = _workspaceFixture(
        root,
        base: _base,
        dependent: _dependent,
        declaredFloor: '^$_version',
      );
      final processes = _FakeProcesses();
      final pubDev = _FakePubDev(processes, version: _version);
      final request = ReleaseCircuitRequest(
        workspaceRoot: workspaceRoot,
        diff: _diffRef,
        change: ReleaseChange.fix,
        packages: const [
          ReleasePackageTarget(
            package: _base,
            directory: _baseDir,
            targetRung: ReleaseRung.dev,
          ),
          ReleasePackageTarget(
            package: _dependent,
            directory: _dependentDir,
            targetRung: ReleaseRung.dev,
          ),
        ],
      );
      final invoker = _FakeReleaseCommandInvoker(
        request: request,
        workspaceOrder: const <String>[_base, _dependent],
        // Both wave legs drive the REAL vended wave command over the Fakes.
        delegate: InProcessReleaseCommandInvoker(
          service: ReleaseService(
            runProcess: processes.run,
            httpGet: pubDev.get,
            wait: _noWait,
          ),
        ),
        delegateOperations: const <String>{'publish'},
      );

      final report = await _drive(request, invoker);
      expect(report.stop, isNull, reason: '${report.stop}');

      final events = processes.events;
      final basePublished = events.indexOf('probe:$_base:published');
      final baseTag = events.indexOf('tag:$_base-v$_version');
      final dependentTag = events.indexOf('tag:$_dependent-v$_version');
      expect(baseTag, greaterThanOrEqualTo(0), reason: '$events');
      expect(basePublished, greaterThan(baseTag), reason: '$events');
      // THE BARRIER: the dependent's tag is cut only after pub.dev's versions
      // list first carried the predecessor — never on the publish exit code.
      expect(events, contains('probe:$_base:pending'));
      expect(dependentTag, greaterThan(basePublished), reason: '$events');

      // A zero exit is not publication: a poll that answers isPublished=false
      // fails the circuit rather than completing it.
      final notPropagated = _FakeReleaseCommandInvoker(
        request: _request(),
        workspaceOrder: const <String>[_base, _dependent],
        pollPublished: false,
      );
      final stalled = await _drive(_request(), notPropagated);
      expect(stalled.ran.last, 'poll');
      expect(stalled.stop, isA<Failed>());
      expect(
        (stalled.stop! as Failed).reason,
        contains('an exit code is not publication'),
      );
    });
  });

  group('the human promotion boundary', () {
    test('halts beta to rc and rc to stable', () async {
      Future<_RunReport> run({
        required String currentRung,
        required ReleaseRung target,
        bool intent = false,
      }) {
        final request = _request(
          baseRung: target,
          humanPromotionIntent: intent,
        );
        return _drive(
          request,
          _FakeReleaseCommandInvoker(
            request: request,
            ladder: <String, _LadderFact>{
              _base: _LadderFact(
                published: true,
                version: '0.2.0-$currentRung.1',
                rung: currentRung,
              ),
              _dependent: const _LadderFact(
                published: true,
                version: '0.1.0-dev.1',
                rung: 'dev',
              ),
            },
          ),
        );
      }

      final toRc = await run(currentRung: 'beta', target: ReleaseRung.rc);
      expect(toRc.ran.last, 'promotion');
      expect(toRc.stop, isA<Escalate>());
      expect((toRc.stop! as Escalate).reason, contains('$_base beta -> rc'));

      final toStable = await run(currentRung: 'rc', target: ReleaseRung.stable);
      expect(toStable.ran.last, 'promotion');
      expect(toStable.stop, isA<Escalate>());
      expect(
        (toStable.stop! as Escalate).reason,
        contains('$_base rc -> stable'),
      );

      // A DECLARED human intent admits the same transition.
      final declared = await run(
        currentRung: 'beta',
        target: ReleaseRung.rc,
        intent: true,
      );
      expect(declared.stop, isNull, reason: '${declared.stop}');

      // Publishing again at a rung the package ALREADY occupies is agent work,
      // and the established intent rides through to the vended plan.
      final sameRung = await run(currentRung: 'rc', target: ReleaseRung.rc);
      expect(sameRung.stop, isNull, reason: '${sameRung.stop}');
      expect(_receipt(sameRung, 'promotion')['promotionIntentFlag'], isTrue);
    });

    test('the rc plan and wave carry the established intent', () async {
      final request = _request(baseRung: ReleaseRung.rc);
      final invoker = _FakeReleaseCommandInvoker(
        request: request,
        ladder: const <String, _LadderFact>{
          _base: _LadderFact(
            published: true,
            version: '0.2.0-rc.1',
            rung: 'rc',
          ),
          _dependent: _LadderFact(),
        },
      );
      final report = await _drive(request, invoker);
      expect(report.stop, isNull, reason: '${report.stop}');
      for (final call in invoker.calls) {
        if (call[1] == 'plan' && call.contains(_base)) {
          expect(call, contains('--promotion-intent'));
        }
        if (call[1] == 'publish') {
          expect(call, contains('--promotion-intent'));
        }
      }
    });
  });

  group('the pipeline order is enforced inside every leg', () {
    test('a leg refuses a predecessor receipt it cannot read', () async {
      final request = _request();
      final gate = ReleaseGateCapability(
        _FakeReleaseCommandInvoker(request: request),
      );
      final outcome = await gate.run(
        FakeTreeContext(values: <Type, Object>{ReleaseCircuitRequest: request}),
        stepArgs(_node('publish'), params: const {'operation': 'publish'}),
      );
      expect(outcome, isA<Failed>());
      expect((outcome as Failed).kind, CapabilityFailureKind.noResult);
      expect(outcome.reason, contains('`preflight` receipt is missing'));
    });

    test('the irreversible leg is spent once and parks', () {
      const gate = ReleaseGateCapability(_NeverInvoker());
      final publish = gate.supervisionPolicy(
        stepArgs(_node('publish'), params: const {'operation': 'publish'}),
      );
      for (final kind in CapabilityFailureKind.values) {
        expect(publish.policyFor(kind).maxRestarts, 0, reason: kind.name);
        expect(
          publish.policyFor(kind).onExhaustion,
          ExhaustionBehavior.parkAtGate,
          reason: kind.name,
        );
      }
      // Every reversible leg keeps the circuit's own supervision.
      final scrub = gate.supervisionPolicy(
        stepArgs(_node('scrub'), params: const {'operation': 'scrub'}),
      );
      expect(scrub.byKind, isEmpty);
    });

    test('the request refuses a wave it cannot publish', () {
      expect(
        () => ReleaseCircuitRequest(
          workspaceRoot: '/w',
          diff: _diffRef,
          change: ReleaseChange.fix,
          packages: const <ReleasePackageTarget>[],
        ),
        throwsArgumentError,
      );
      expect(
        () => _duplicate(package: _base, directory: 'packages/other'),
        throwsArgumentError,
      );
      expect(
        () => _duplicate(package: 'other_pack', directory: _baseDir),
        throwsArgumentError,
      );
      expect(
        () => ReleaseCircuitRequest(
          workspaceRoot: '/w',
          diff: _diffRef,
          change: ReleaseChange.fix,
          packages: const [
            ReleasePackageTarget(
              package: _base,
              directory: '../outside',
              targetRung: ReleaseRung.dev,
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('the invoker admits only the vended JSON surface', () {
      const invoker = InProcessReleaseCommandInvoker();
      expect(
        () => invoker.run(const <String>['release', 'scrub', '--dir', '/w']),
        throwsArgumentError,
      );
      expect(
        () => invoker.run(const <String>['dart', 'pub', 'publish', '--json']),
        throwsArgumentError,
      );
    });
  });
}

/// A request whose second target collides with the first on [package] or
/// [directory].
ReleaseCircuitRequest _duplicate({
  required String package,
  required String directory,
}) => ReleaseCircuitRequest(
  workspaceRoot: '/w',
  diff: _diffRef,
  change: ReleaseChange.fix,
  packages: [
    const ReleasePackageTarget(
      package: _base,
      directory: _baseDir,
      targetRung: ReleaseRung.dev,
    ),
    ReleasePackageTarget(
      package: package,
      directory: directory,
      targetRung: ReleaseRung.dev,
    ),
  ],
);

/// An invoker a policy probe never reaches.
class _NeverInvoker implements ReleaseCommandInvoker {
  const _NeverInvoker();

  @override
  Future<ReleaseCommandInvocation> run(List<String> arguments) async =>
      fail('the supervision declaration must be pure — it ran $arguments');
}
