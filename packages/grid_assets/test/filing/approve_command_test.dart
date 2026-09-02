import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart' show callMetadata;

/// Replies by bd subcommand, recording every argv so a refusal can prove it
/// wrote nothing.
final class _ScriptedBdRunner implements BdRunner {
  _ScriptedBdRunner(this.replies, {this.updateExitCode = 0});

  final Map<String, String> replies;
  final int updateExitCode;
  final List<List<String>> argvs = [];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(args);
    return BdResult(
      exitCode: args.first == 'update' ? updateExitCode : 0,
      stdout: replies[args.first] ?? '{"schema_version":1,"data":[]}',
      stderr: args.first == 'update' && updateExitCode != 0
          ? 'bd: refused'
          : '',
    );
  }

  List<List<String>> get updates =>
      argvs.where((argv) => argv.first == 'update').toList();
}

final class _FakeGitRunner implements GitRunner {
  _FakeGitRunner(this.result);

  final GitRunResult result;
  final List<({String workingDirectory, List<String> args})> calls = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add((workingDirectory: workingDirectory, args: args));
    return result;
  }
}

const String _sha = '9f1c2d3e4b5a69788899aabbccddeeff00112233';

String _beadReply({required String description}) => jsonEncode({
  'schema_version': 1,
  'data': [
    {
      'id': 'pow-child',
      'title': 'child',
      'issue_type': 'task',
      'description': description,
      'acceptance_criteria': '- [ ] checked',
      'metadata': {'validation_plan': 'dart test'},
    },
  ],
});

String _depReply(List<String> blockers) => jsonEncode({
  'schema_version': 1,
  'data': [
    for (final blocker in blockers)
      {'issue_id': 'pow-child', 'depends_on_id': blocker, 'type': 'blocks'},
  ],
});

String _linkReply(List<Map<String, String>> links) => jsonEncode({
  'schema_version': 1,
  'data': [
    for (final (index, link) in links.indexed)
      {
        'id': 'tgdog-l$index',
        'issue_type': 'link',
        'status': 'open',
        'metadata': link,
      },
  ],
});

({
  CommandRunner<int> runner,
  StringBuffer out,
  StringBuffer err,
  _ScriptedBdRunner bd,
  _FakeGitRunner git,
})
_harness(
  _ScriptedBdRunner bd, {
  GitRunResult gitResult = const GitRunResult(exitCode: 0, output: '$_sha\n'),
  String? stateRoot,
}) {
  final out = StringBuffer();
  final err = StringBuffer();
  final git = _FakeGitRunner(gitResult);
  return (
    runner: CommandRunner<int>('space', 'test station')
      ..addCommand(
        ApproveCommand(
          service: ApproveService(
            runnerFor: (_) => bd,
            git: git,
            now: () => DateTime.utc(2026, 9, 2, 14, 30),
          ),
          storeRoot: () => '/work/power_station',
          stateRoot: () => stateRoot,
          out: out,
          err: err,
        ),
      ),
    out: out,
    err: err,
    bd: bd,
    git: git,
  );
}

void main() {
  test('refuses an unwired mid-sentence blocker and writes nothing', () async {
    final h = _harness(
      _ScriptedBdRunner({
        'query': _beadReply(
          description: 'Child 2 of epic pow-n6n. Depends on child pow-n6n.1.',
        ),
        'dep': _depReply(const []),
      }),
    );

    expect(
      await h.runner.run(['approve', '--json', '--actor', 'nico', 'pow-child']),
      1,
    );
    final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
    expect(report['approved'], isFalse);
    final filing = report['filing'] as Map<String, dynamic>;
    final rows = (filing['requirements'] as List).cast<Map<String, dynamic>>();
    final dependencies = rows.singleWhere(
      (row) => row['requirement'] == 'dependencies',
    );
    expect(dependencies['passed'], isFalse);
    expect(dependencies['detail'], contains('pow-n6n.1'));
    expect(h.bd.updates, isEmpty);
    expect(h.git.calls, isEmpty);
  });

  test('stamps a wired bead in ONE bd update', () async {
    final h = _harness(
      _ScriptedBdRunner({
        'query': _beadReply(
          description: 'Child 2 of epic pow-n6n. Depends on child pow-n6n.1.',
        ),
        'dep': _depReply(const ['pow-n6n.1']),
      }),
    );

    expect(
      await h.runner.run(['approve', '--json', '--actor', 'nico', 'pow-child']),
      0,
      reason: '${h.out}${h.err}',
    );
    expect(h.git.calls, [
      (
        workingDirectory: '/work/power_station',
        args: const ['rev-parse', 'HEAD'],
      ),
    ]);
    expect(h.bd.updates, hasLength(1));
    final argv = h.bd.updates.single;
    expect(argv.take(2), ['update', 'pow-child']);
    expect(argv, containsAllInOrder(['--actor', 'nico']));
    expect(argv, containsAllInOrder(['--add-label', 'grid.approved']));
    expect(argv.where((arg) => arg == '--set-metadata'), hasLength(3));
    expect(callMetadata(argv), {
      'grid.approved_by': 'nico',
      'grid.approved_at': '2026-09-02T14:30:00.000Z',
      'grid.approved_rev': _sha,
    });
    final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
    expect(report['approved'], isTrue);
    expect(report['by'], 'nico');
    expect(DateTime.parse(report['at'] as String).isUtc, isTrue);
    expect(report['rev'], _sha);
  });

  test('a foreign blocker needs its link bead', () async {
    _ScriptedBdRunner bd(List<Map<String, String>> links) => _ScriptedBdRunner({
      'query': _beadReply(description: 'BLOCKED on tg-89y8 across stores.'),
      'dep': _depReply(const []),
      'list': _linkReply(links),
    });

    final without = _harness(bd(const []), stateRoot: '/work/home/.grid');
    expect(
      await without.runner.run(['approve', '--actor', 'nico', 'pow-child']),
      1,
    );
    expect(without.out.toString(), contains('tg-89y8'));
    expect(without.bd.updates, isEmpty);

    final withLink = _harness(
      bd(const [
        {
          'grid.link.from': 'pow-child',
          'grid.link.to': 'tg-89y8',
          'grid.link.type': 'blocks',
        },
      ]),
      stateRoot: '/work/home/.grid',
    );
    expect(
      await withLink.runner.run(['approve', '--actor', 'nico', 'pow-child']),
      0,
      reason: '${withLink.out}${withLink.err}',
    );
    expect(withLink.bd.updates, hasLength(1));
  });

  test('a missing actor is a usage refusal that spawns nothing', () async {
    final h = _harness(_ScriptedBdRunner(const {}));

    expect(await h.runner.run(['approve', 'pow-child']), 64);
    expect(h.err.toString(), contains('--actor'));
    expect(h.bd.argvs, isEmpty);
    expect(h.git.calls, isEmpty);
  });

  test('an unreadable revision refuses before any write', () async {
    final h = _harness(
      _ScriptedBdRunner({
        'query': _beadReply(description: 'No local ordering.'),
        'dep': _depReply(const []),
      }),
      gitResult: const GitRunResult(
        exitCode: -1,
        output: 'not a git repository',
        launched: false,
      ),
    );

    expect(await h.runner.run(['approve', '--actor', 'nico', 'pow-child']), 1);
    expect(h.out.toString(), contains('approval revision'));
    expect(h.bd.updates, isEmpty);
  });

  test('a refused bd update is reported, never claimed as approval', () async {
    final h = _harness(
      _ScriptedBdRunner({
        'query': _beadReply(description: 'No local ordering.'),
        'dep': _depReply(const []),
      }, updateExitCode: 1),
    );

    expect(
      await h.runner.run(['approve', '--json', '--actor', 'nico', 'pow-child']),
      1,
    );
    final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
    expect(report['approved'], isFalse);
    expect(report['reason'], contains('bd update refused'));
  });
}
