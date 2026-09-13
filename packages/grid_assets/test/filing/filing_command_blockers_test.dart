import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Replies by bd subcommand and records every argv, so a run can prove the
/// filing verb wrote nothing (read-only by construction) and that it never
/// reached a second store.
final class _ScriptedBdRunner implements BdRunner {
  _ScriptedBdRunner(this.replies);

  final Map<String, String> replies;
  final List<List<String>> argvs = [];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(args);
    return BdResult(
      exitCode: 0,
      stdout: replies[args.first] ?? '{"schema_version":1,"data":[]}',
      stderr: '',
    );
  }
}

/// Creates a REAL grid home — `<home>/.grid/.beads` — because the resolver
/// probes the filesystem to tell a grid home from its own state store.
String _gridHome() {
  final home = Directory.systemTemp.createTempSync('grid-home-');
  Directory(p.join(home.path, '.grid', '.beads')).createSync(recursive: true);
  addTearDown(() => home.deleteSync(recursive: true));
  return home.path;
}

/// Creates a directory holding NEITHER `.grid` nor `.beads`.
String _unrelatedRoot() {
  final root = Directory.systemTemp.createTempSync('not-a-grid-home-');
  addTearDown(() => root.deleteSync(recursive: true));
  return root.path;
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

_ScriptedBdRunner _bd({required String description}) => _ScriptedBdRunner({
  'query': _beadReply(description: description),
  'dep': '{"schema_version":1,"data":[]}',
});

({
  CommandRunner<int> runner,
  StringBuffer out,
  StringBuffer err,
  _ScriptedBdRunner bd,
})
_harness(_ScriptedBdRunner bd, {String? stateRoot}) {
  final out = StringBuffer();
  final err = StringBuffer();
  return (
    runner: CommandRunner<int>('space', 'test station')
      ..addCommand(
        FilingCommand(
          service: FilingService(
            source: ExactSubstationBeadSource(runnerFor: (_) => bd),
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
  );
}

Map<String, dynamic> _dependencyRow(StringBuffer out) =>
    ((jsonDecode(out.toString()) as Map<String, dynamic>)['requirements']
            as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => row['requirement'] == 'dependencies');

const List<String> _mutations = ['create', 'update', 'close'];

void main() {
  const crossStore = 'BLOCKED on tg-89y8 across stores.';

  test('a named cross-store blocker needs the bead\'s OWN outgoing edge', () {
    // grid_engine 0.4.0-dev.3 deleted the state-store link surface this verb
    // used to project (the_grid#447): there is no second store to consult, so
    // an unwired foreign id is reported missing like any other — fail-closed.
    final h = _harness(_bd(description: crossStore), stateRoot: _gridHome());

    expect(
      h.runner.run(['filing', '--json', 'pow-child']),
      completion(1),
      reason: '${h.out}${h.err}',
    );
  });

  test('the state store is never read, even with a root resolved', () async {
    final h = _harness(_bd(description: crossStore), stateRoot: _gridHome());

    expect(await h.runner.run(['filing', '--json', 'pow-child']), 1);
    expect(
      _dependencyRow(h.out)['detail'],
      'missing outgoing blocks edges: tg-89y8',
    );
    expect(h.bd.argvs.map((argv) => argv.first), isNot(contains('list')));
    expect(
      h.bd.argvs.map((argv) => argv.first),
      everyElement(isNot(isIn(_mutations))),
    );
  });

  test('state-root help contract accepts grid home and state store roots and '
      'rejects unrelated roots', () {
    final parser = ArgParser();
    addStateRootOption(parser);
    String? resolve(String? value) => resolveStateRoot(
      parser.parse(value == null ? const [] : ['--state-root', value]),
      noStateRoot,
    );

    // The help documents the GRID HOME, and both accepted forms land on the
    // same `.grid` state store — so the documented value is the working one.
    // It names the home rather than either store because that is where the
    // session-lifecycle beads `park`/`unpark` close and retire live.
    expect(
      kStateRootHelp,
      'The grid home whose .grid/.beads holds the session-lifecycle state '
      'beads.',
    );
    final home = _gridHome();
    final store = p.join(home, '.grid');
    expect(resolve(home), store);
    expect(resolve('$home${p.separator}.'), store);
    expect(resolve(store), store);

    // No value on either seam means no home was named at all.
    expect(resolve(null), isNull);
    expect(resolve('   '), isNull);
    expect(resolveStateRoot(parser.parse(const []), () => home), store);
    expect(resolveStateRoot(parser.parse(const []), () => '  '), isNull);

    // Guards LOUD or GONE: a root holding neither child is refused by name.
    final unrelated = _unrelatedRoot();
    expect(
      () => resolve(unrelated),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains(unrelated), contains('.grid'), contains('.beads')),
        ),
      ),
    );
  });

  test('the documented grid home is accepted on the flag', () async {
    final home = _gridHome();
    final h = _harness(_bd(description: 'Depends on pow-1rn.5.'));

    expect(
      await h.runner.run([
        'filing',
        '--json',
        '--state-root',
        home,
        'pow-child',
      ]),
      1,
      reason: '${h.out}${h.err}',
    );
    expect(
      _dependencyRow(h.out)['detail'],
      'missing outgoing blocks edges: pow-1rn.5',
    );
    expect(h.err.toString(), isEmpty);
  });

  test(
    'an unrelated state root is refused LOUD, and nothing is read',
    () async {
      final h = _harness(_bd(description: crossStore));

      expect(
        await h.runner.run([
          'filing',
          '--json',
          '--state-root',
          _unrelatedRoot(),
          'pow-child',
        ]),
        1,
      );
      expect(h.err.toString(), allOf(contains('.grid'), contains('.beads')));
      expect(h.out.toString(), isEmpty);
      expect(h.bd.argvs, isEmpty);
    },
  );

  test('both verbs register ONE state-root seam', () {
    final filing = FilingCommand(out: StringBuffer(), err: StringBuffer());
    final approve = ApproveCommand(out: StringBuffer(), err: StringBuffer());

    expect(noStateRoot(), isNull);
    expect(filing.argParser.options[kStateRootOption]?.help, kStateRootHelp);
    expect(approve.argParser.options[kStateRootOption]?.help, kStateRootHelp);
    expect(filing.invocation, contains('[--state-root <path>]'));
  });

  test('a hyphenated compound is not a bead id', () async {
    final h = _harness(
      _bd(description: 'Blocked by: the cross-store link bead wiring.'),
    );

    expect(
      await h.runner.run(['filing', '--json', 'pow-child']),
      0,
      reason: '${h.out}${h.err}',
    );
    expect(_dependencyRow(h.out)['detail'], 'no local blockers named');
  });

  test('a mid-sentence mention declares nothing', () async {
    final h = _harness(
      _bd(
        description:
            "RECEIPT: pow-pry0 carries a 'DEPENDS ON: tg-1n4y' sentence; "
            'approve refused it.',
      ),
    );

    expect(
      await h.runner.run(['filing', '--json', 'pow-child']),
      0,
      reason: '${h.out}${h.err}',
    );
    expect(_dependencyRow(h.out)['detail'], 'no local blockers named');
  });

  test('a dotted child id still parses', () async {
    final h = _harness(_bd(description: 'Depends on pow-1rn.5.'));

    expect(await h.runner.run(['filing', '--json', 'pow-child']), 1);
    expect(
      _dependencyRow(h.out)['detail'],
      'missing outgoing blocks edges: pow-1rn.5',
    );
  });
}
