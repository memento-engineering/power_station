import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/asset_fakes.dart' show callMetadata;

/// Creates a REAL grid home — `<home>/.grid/.beads` — because the resolver
/// probes the filesystem to tell a grid home from its own state store.
String _gridHome() {
  final home = Directory.systemTemp.createTempSync('grid-home-');
  Directory(p.join(home.path, '.grid', '.beads')).createSync(recursive: true);
  addTearDown(() => home.deleteSync(recursive: true));
  return home.path;
}

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
  List<String> roots,
})
_harness(_ScriptedBdRunner bd, {String? stateRoot}) {
  final out = StringBuffer();
  final err = StringBuffer();
  final roots = <String>[];
  return (
    runner: CommandRunner<int>('space', 'test station')
      ..addCommand(
        ApproveCommand(
          service: ApproveService(
            runnerFor: (root) {
              roots.add(root);
              return bd;
            },
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
    roots: roots,
  );
}

void main() {
  const linked = {
    'grid.link.from': 'pow-child',
    'grid.link.to': 'tg-89y8',
    'grid.link.type': 'blocks',
  };

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
  });

  test('stamps the deterministic filing revision in one update', () async {
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
    expect(h.bd.updates, hasLength(1));
    final argv = h.bd.updates.single;
    expect(argv.take(2), ['update', 'pow-child']);
    expect(argv, containsAllInOrder(['--actor', 'nico']));
    expect(argv, isNot(contains('--add-label')));
    expect(argv.where((arg) => arg == '--set-metadata'), hasLength(3));

    final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
    final filing = report['filing'] as Map<String, dynamic>;
    final revision = filing['approval_revision'] as String;
    // The stamp is the revision the PASSING preflight evaluated — the receipt
    // names WHAT was approved, not which commit the store sat on.
    expect(revision, startsWith(kFilingApprovalRevisionPrefix));
    expect(callMetadata(argv), {
      'grid.approved_by': 'nico',
      'grid.approved_at': '2026-09-02T14:30:00.000Z',
      'grid.approved_rev': revision,
    });
    expect(report['approved'], isTrue);
    expect(report['by'], 'nico');
    expect(DateTime.parse(report['at'] as String).isUtc, isTrue);
    expect(report['rev'], revision);

    // The verb reached NO git: `/work/power_station` is a fiction, and only
    // the injected bd runner was ever spawned against it.
    expect(Directory('/work/power_station').existsSync(), isFalse);
    expect(h.roots, everyElement(isNot(endsWith('.git'))));
  });

  test('a foreign blocker needs its link bead', () async {
    _ScriptedBdRunner bd(List<Map<String, String>> links) => _ScriptedBdRunner({
      'query': _beadReply(description: 'BLOCKED on tg-89y8 across stores.'),
      'dep': _depReply(const []),
      'list': _linkReply(links),
    });
    final home = _gridHome();

    final without = _harness(bd(const []), stateRoot: home);
    expect(
      await without.runner.run(['approve', '--actor', 'nico', 'pow-child']),
      1,
    );
    expect(
      without.out.toString(),
      contains('missing outgoing blocks edges: tg-89y8'),
    );
    expect(without.bd.updates, isEmpty);

    final withLink = _harness(bd(const [linked]), stateRoot: home);
    expect(
      await withLink.runner.run(['approve', '--actor', 'nico', 'pow-child']),
      0,
      reason: '${withLink.out}${withLink.err}',
    );
    expect(withLink.bd.updates, hasLength(1));
  });

  test('documented grid home reaches the state store', () async {
    final home = _gridHome();
    final h = _harness(
      _ScriptedBdRunner({
        'query': _beadReply(description: 'BLOCKED on tg-89y8 across stores.'),
        'dep': _depReply(const []),
        'list': _linkReply(const [linked]),
      }),
    );

    expect(
      await h.runner.run([
        'approve',
        '--actor',
        'nico',
        '--json',
        '--state-root',
        home,
        'pow-child',
      ]),
      0,
      reason: '${h.out}${h.err}',
    );
    expect(h.roots, contains(p.join(home, '.grid')));
    expect(h.err.toString(), isEmpty);
    expect(h.out.toString(), isNot(contains('invalid issue type')));
  });

  test('an unrelated state root refuses before any read or write', () async {
    final unrelated = Directory.systemTemp.createTempSync('not-a-grid-home-');
    addTearDown(() => unrelated.deleteSync(recursive: true));
    final h = _harness(
      _ScriptedBdRunner({
        'query': _beadReply(description: 'No local ordering.'),
        'dep': _depReply(const []),
      }),
    );

    expect(
      await h.runner.run([
        'approve',
        '--actor',
        'nico',
        '--state-root',
        unrelated.path,
        'pow-child',
      ]),
      1,
    );
    expect(h.err.toString(), allOf(contains('.grid'), contains('.beads')));
    expect(h.bd.argvs, isEmpty);
  });

  test(
    'an unconsulted cross-store blocker is unchecked, never missing',
    () async {
      final h = _harness(
        _ScriptedBdRunner({
          'query': _beadReply(description: 'BLOCKED on tg-89y8 across stores.'),
          'dep': _depReply(const []),
          'list': _linkReply(const [linked]),
        }),
      );

      expect(
        await h.runner.run(['approve', '--actor', 'nico', 'pow-child']),
        1,
      );
      expect(
        h.out.toString(),
        contains(
          'FAIL dependencies: cross-store edges not consulted — '
          'pass --state-root',
        ),
      );
      expect(h.out.toString(), isNot(contains('tg-89y8')));
      expect(h.bd.updates, isEmpty);
    },
  );

  test('a missing actor is a usage refusal that spawns nothing', () async {
    final h = _harness(_ScriptedBdRunner(const {}));

    expect(await h.runner.run(['approve', 'pow-child']), 64);
    expect(h.err.toString(), contains('--actor'));
    expect(h.bd.argvs, isEmpty);
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
