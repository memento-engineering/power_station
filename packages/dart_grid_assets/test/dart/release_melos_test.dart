// The MELOS-backed legs of the DART-domain RELEASE ops: workspace DISCOVERY
// (`melos list --no-published` / `--diff`) and workspace ORDERING (`melos list
// --graph`), plus the `dart release discover` / `dart release order
// --workspace` Commands over them.
//
// Two facts drive every probe here, both measured on the 2026-09-08 lenny
// release:
//
//   - the dependency graph that decides publish order used to be TRANSCRIBED
//     into a hand-written manifest, so the manifest and the melos graph must
//     resolve to the SAME order or the transcription was buying nothing;
//   - melos's graph carries `dev_dependencies` and `dependency_overrides`
//     edges too, and `leonard_agent` / `leonard_flutter` /
//     `leonard_flutter_test` form a DEV cycle. A dev cycle is not a publish
//     cycle, so ordering the RAW graph refuses a perfectly releasable
//     workspace — the runtime filter is load-bearing.
//
// Offline: melos rides the injected [ProcessRunner] seam (Fakes, not mocks),
// so nothing here launches dart, melos or git.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_grid_assets/dart_grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A Fake [ProcessRunner] that records every call and answers a queue of
/// canned results. An unexpected call is LOUD — a silent extra process call is
/// exactly the kind of drift these probes exist to catch.
class _FakeMelos {
  _FakeMelos(List<ProcessResult> results) : _results = [...results];

  final List<ProcessResult> _results;
  final calls =
      <
        ({String executable, List<String> arguments, String? workingDirectory})
      >[];

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

/// The lenny-shaped fixture workspace: a RUNTIME chain
/// (`leonard_contract` <- `leonard_agent` <- `leonard_flutter`) crossed by the
/// `leonard_agent` / `leonard_flutter` / `leonard_flutter_test` DEV cycle that
/// broke the 2026-09-08 wave's resolve.
Directory _writeLennyWorkspace() {
  final root = Directory.systemTemp.createTempSync('release-melos-');
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
    'name: leonard_workspace\n'
    'publish_to: none\n'
    'environment:\n'
    '  sdk: ^3.11.0\n'
    'workspace:\n'
    '  - packages/leonard_contract\n'
    '  - packages/leonard_agent\n'
    '  - packages/leonard_flutter\n'
    '  - packages/leonard_flutter_test\n',
  );
  void member(String name, String pubspec) {
    final dir = Directory(p.join(root.path, 'packages', name))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
  }

  member(
    'leonard_contract',
    'name: leonard_contract\n'
        'version: 0.1.0\n'
        'resolution: workspace\n'
        'environment:\n'
        '  sdk: ^3.11.0\n',
  );
  member(
    'leonard_agent',
    'name: leonard_agent\n'
        'version: 0.2.0\n'
        'resolution: workspace\n'
        'environment:\n'
        '  sdk: ^3.11.0\n'
        'dependencies:\n'
        '  leonard_contract: ^0.1.0\n'
        'dev_dependencies:\n'
        '  leonard_flutter_test: ^0.4.0\n',
  );
  member(
    'leonard_flutter',
    'name: leonard_flutter\n'
        'version: 0.3.0\n'
        'resolution: workspace\n'
        'environment:\n'
        '  sdk: ^3.11.0\n'
        'dependencies:\n'
        '  leonard_agent: ^0.2.0\n'
        'dev_dependencies:\n'
        '  leonard_flutter_test: ^0.4.0\n',
  );
  member(
    'leonard_flutter_test',
    'name: leonard_flutter_test\n'
        'version: 0.4.0\n'
        'resolution: workspace\n'
        'environment:\n'
        '  sdk: ^3.11.0\n'
        'dependencies:\n'
        '  leonard_contract: ^0.1.0\n'
        'dev_dependencies:\n'
        '  leonard_agent: ^0.2.0\n'
        '  leonard_flutter: ^0.3.0\n',
  );
  return root;
}

/// `melos list --json --graph`'s adjacency object for [_writeLennyWorkspace] —
/// ALL in-workspace edges, dev ones included, exactly as melos emits them
/// (`allDependenciesInWorkspace`).
const String _melosGraphJson = '''
{
  "leonard_agent": ["leonard_contract", "leonard_flutter_test"],
  "leonard_contract": [],
  "leonard_flutter": ["leonard_agent", "leonard_flutter_test"],
  "leonard_flutter_test": [
    "leonard_contract",
    "leonard_agent",
    "leonard_flutter"
  ]
}
''';

/// The hand-written deps manifest the operator used to transcribe: the same
/// workspace, RUNTIME edges only.
const String _handManifestJson =
    '{"leonard_agent":["leonard_contract"],'
    '"leonard_contract":[],'
    '"leonard_flutter":["leonard_agent"],'
    '"leonard_flutter_test":["leonard_contract"]}';

/// The dependency-first sequence both inputs must resolve to.
const List<String> _runtimeOrder = [
  'leonard_contract',
  'leonard_agent',
  'leonard_flutter',
  'leonard_flutter_test',
];

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');

void main() {
  group('ReleaseService — the melos workspace graph', () {
    test(
      'orders a workspace from the melos graph, dropping every DEV edge',
      () async {
        final root = _writeLennyWorkspace();
        addTearDown(() => root.deleteSync(recursive: true));
        final fake = _FakeMelos([_ok(_melosGraphJson)]);
        final service = ReleaseService(runProcess: fake.call);

        final order = await service.publishOrderFromMelosWorkspace(
          workspaceRoot: root.path,
        );

        expect(order.order, _runtimeOrder);
        expect(fake.calls, hasLength(1));
        expect(fake.calls.single.executable, 'dart');
        expect(fake.calls.single.arguments, [
          'run',
          'melos',
          'list',
          '--json',
          '--graph',
          '--no-private',
        ]);
        expect(
          fake.calls.single.workingDirectory,
          p.normalize(p.absolute(root.path)),
        );
      },
    );

    test('the RAW melos graph is a cycle — proving the runtime filter is what '
        'makes the workspace orderable at all', () {
      final graph = (jsonDecode(_melosGraphJson) as Map<String, dynamic>).map(
        (key, value) =>
            MapEntry(key, [for (final v in value as List) v as String]),
      );

      expect(
        () => const ReleaseService().publishOrder(graph),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('dependency cycle'),
              contains('leonard_agent'),
              contains('leonard_flutter_test'),
            ),
          ),
        ),
      );
    });

    test('a graph node that is not a publishable workspace member is a LOUD '
        'refusal', () async {
      final root = _writeLennyWorkspace();
      addTearDown(() => root.deleteSync(recursive: true));
      final fake = _FakeMelos([_ok('{"leonard_ghost": []}')]);
      final service = ReleaseService(runProcess: fake.call);

      expect(
        () => service.publishOrderFromMelosWorkspace(workspaceRoot: root.path),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('leonard_ghost'),
              contains('not a publishable member'),
            ),
          ),
        ),
      );
    });
  });

  group('ReleaseService.discoverWorkspace', () {
    test('runs both melos queries and sorts each answer', () async {
      final root = _writeLennyWorkspace();
      addTearDown(() => root.deleteSync(recursive: true));
      final fake = _FakeMelos([
        _ok(
          '[{"name":"leonard_flutter","version":"0.3.0"},'
          '{"name":"leonard_agent","version":"0.2.0"}]',
        ),
        _ok(
          '[{"name":"leonard_flutter_test","version":"0.4.0"},'
          '{"name":"leonard_agent","version":"0.2.0"}]',
        ),
      ]);
      final service = ReleaseService(runProcess: fake.call);

      final discovery = await service.discoverWorkspace(
        workspaceRoot: root.path,
        diff: 'leonard_agent-v0.1.9',
      );

      expect(discovery.workspaceRoot, p.normalize(p.absolute(root.path)));
      expect(discovery.diff, 'leonard_agent-v0.1.9');
      expect(discovery.candidates, ['leonard_agent', 'leonard_flutter']);
      expect(discovery.changed, ['leonard_agent', 'leonard_flutter_test']);
      expect(discovery.toJson(), {
        'workspaceRoot': p.normalize(p.absolute(root.path)),
        'diff': 'leonard_agent-v0.1.9',
        'candidates': ['leonard_agent', 'leonard_flutter'],
        'changed': ['leonard_agent', 'leonard_flutter_test'],
      });

      expect(fake.calls.map((c) => c.executable), ['dart', 'dart']);
      expect(fake.calls.map((c) => c.arguments), [
        ['run', 'melos', 'list', '--no-published', '--json', '--no-private'],
        [
          'run',
          'melos',
          'list',
          '--diff=leonard_agent-v0.1.9',
          '--json',
          '--no-private',
        ],
      ]);
      expect(fake.calls.map((c) => c.workingDirectory).toSet(), {
        p.normalize(p.absolute(root.path)),
      });
    });

    test('a failed melos call refuses LOUD, carrying the command, the exit '
        'code and the process diagnostic', () async {
      final root = _writeLennyWorkspace();
      addTearDown(() => root.deleteSync(recursive: true));
      final fake = _FakeMelos([
        ProcessResult(0, 78, '', 'Melos: workspace not found'),
      ]);
      final service = ReleaseService(runProcess: fake.call);

      expect(
        () => service.discoverWorkspace(workspaceRoot: root.path, diff: 'main'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('melos list --no-published --json --no-private'),
              contains('exit 78'),
              contains('Melos: workspace not found'),
            ),
          ),
        ),
      );
    });
  });

  group('dart release — the melos-backed Commands', () {
    Future<({int code, String out, String err})> run(
      List<String> argv, {
      required ReleaseService service,
    }) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = CommandRunner<int>('t', 'test')
        ..addCommand(ReleaseCommand(service: service, out: out, err: err));
      final code = await runner.run(argv) ?? 0;
      return (code: code, out: out.toString(), err: err.toString());
    }

    test('release order --workspace resolves the SAME order as the equivalent '
        'hand-written --manifest', () async {
      final root = _writeLennyWorkspace();
      addTearDown(() => root.deleteSync(recursive: true));
      final manifest = File(p.join(root.path, 'deps.json'))
        ..writeAsStringSync(_handManifestJson);

      final fake = _FakeMelos([_ok(_melosGraphJson)]);
      final fromWorkspace = await run([
        'release',
        'order',
        '--workspace',
        root.path,
        '--json',
      ], service: ReleaseService(runProcess: fake.call));
      final fromManifest = await run([
        'release',
        'order',
        '--manifest',
        manifest.path,
        '--json',
      ], service: const ReleaseService());

      expect(fromWorkspace.code, 0);
      expect(fromManifest.code, 0);
      expect(fromWorkspace.out, fromManifest.out);
      expect(jsonDecode(fromWorkspace.out.trim()), {'order': _runtimeOrder});
    });

    test(
      'release discover --json emits exactly the discovery object',
      () async {
        final root = _writeLennyWorkspace();
        addTearDown(() => root.deleteSync(recursive: true));
        final fake = _FakeMelos([
          _ok('[{"name":"leonard_flutter"},{"name":"leonard_agent"}]'),
          _ok('[{"name":"leonard_agent"}]'),
        ]);

        final result = await run([
          'release',
          'discover',
          '--workspace',
          root.path,
          '--diff',
          'origin/main',
          '--json',
        ], service: ReleaseService(runProcess: fake.call));

        expect(result.code, 0);
        expect(jsonDecode(result.out.trim()), {
          'workspaceRoot': p.normalize(p.absolute(root.path)),
          'diff': 'origin/main',
          'candidates': ['leonard_agent', 'leonard_flutter'],
          'changed': ['leonard_agent'],
        });
      },
    );

    test(
      'release discover without --json prints the candidate names',
      () async {
        final root = _writeLennyWorkspace();
        addTearDown(() => root.deleteSync(recursive: true));
        final fake = _FakeMelos([
          _ok('[{"name":"leonard_flutter"},{"name":"leonard_agent"}]'),
          _ok('[]'),
        ]);

        final result = await run([
          'release',
          'discover',
          '--workspace',
          root.path,
          '--diff',
          'origin/main',
        ], service: ReleaseService(runProcess: fake.call));

        expect(result.code, 0);
        expect(result.out, 'leonard_agent\nleonard_flutter\n');
      },
    );

    test('release discover surfaces a failed melos call as a diagnostic on '
        'stderr, with NO candidate JSON on stdout', () async {
      final root = _writeLennyWorkspace();
      addTearDown(() => root.deleteSync(recursive: true));
      final fake = _FakeMelos([
        ProcessResult(0, 66, '', 'Melos: no melos dev_dependency'),
      ]);

      final result = await run([
        'release',
        'discover',
        '--workspace',
        root.path,
        '--diff',
        'origin/main',
        '--json',
      ], service: ReleaseService(runProcess: fake.call));

      expect(result.code, 1);
      expect(result.out, isEmpty);
      expect(result.err, startsWith('release discover: '));
      expect(result.err, contains('exit 66'));
      expect(result.err, contains('Melos: no melos dev_dependency'));
    });

    test('release order refuses BOTH --workspace and --manifest with exit 64, '
        'before any process work', () async {
      final root = _writeLennyWorkspace();
      addTearDown(() => root.deleteSync(recursive: true));
      final manifest = File(p.join(root.path, 'deps.json'))
        ..writeAsStringSync(_handManifestJson);
      final fake = _FakeMelos([]);

      final result = await run([
        'release',
        'order',
        '--workspace',
        root.path,
        '--manifest',
        manifest.path,
        '--json',
      ], service: ReleaseService(runProcess: fake.call));

      expect(result.code, 64);
      expect(fake.calls, isEmpty);
      expect(result.out, isEmpty);
      expect(
        result.err,
        contains('exactly one of --workspace <dir> or --manifest <deps.json>'),
      );
    });

    test('release order refuses NEITHER --workspace nor --manifest with exit '
        '64, before any process work', () async {
      final fake = _FakeMelos([]);

      final result = await run([
        'release',
        'order',
        '--json',
      ], service: ReleaseService(runProcess: fake.call));

      expect(result.code, 64);
      expect(fake.calls, isEmpty);
      expect(result.out, isEmpty);
      expect(
        result.err,
        contains('exactly one of --workspace <dir> or --manifest <deps.json>'),
      );
    });

    test('release order --workspace surfaces a melos refusal non-zero and '
        'loud', () async {
      final root = _writeLennyWorkspace();
      addTearDown(() => root.deleteSync(recursive: true));
      final fake = _FakeMelos([
        ProcessResult(0, 1, '', 'Melos: bad workspace'),
      ]);

      final result = await run([
        'release',
        'order',
        '--workspace',
        root.path,
        '--json',
      ], service: ReleaseService(runProcess: fake.call));

      expect(result.code, 1);
      expect(result.out, isEmpty);
      expect(result.err, startsWith('release order: '));
      expect(result.err, contains('Melos: bad workspace'));
    });
  });
}
