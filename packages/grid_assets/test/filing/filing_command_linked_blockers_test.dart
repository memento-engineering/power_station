import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Replies by bd subcommand and records every argv, so a run can prove the
/// filing verb wrote nothing (read-only by construction).
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

_ScriptedBdRunner _bd({
  required String description,
  List<Map<String, String>> links = const [],
}) => _ScriptedBdRunner({
  'query': _beadReply(description: description),
  'dep': '{"schema_version":1,"data":[]}',
  'list': _linkReply(links),
});

({
  CommandRunner<int> runner,
  StringBuffer out,
  StringBuffer err,
  _ScriptedBdRunner bd,
  List<String> linkRoots,
})
_harness(_ScriptedBdRunner bd, {String? stateRoot}) {
  final out = StringBuffer();
  final err = StringBuffer();
  final linkRoots = <String>[];
  return (
    runner: CommandRunner<int>('space', 'test station')
      ..addCommand(
        FilingCommand(
          service: FilingService(
            source: ExactSubstationBeadSource(runnerFor: (_) => bd),
            links: CrossLinkBlockerSource(
              runnerFor: (root) {
                linkRoots.add(root);
                return bd;
              },
            ),
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
    linkRoots: linkRoots,
  );
}

Map<String, dynamic> _dependencyRow(StringBuffer out) =>
    ((jsonDecode(out.toString()) as Map<String, dynamic>)['requirements']
            as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => row['requirement'] == 'dependencies');

const List<String> _mutations = ['create', 'update', 'close'];

void main() {
  const linked = {
    'grid.link.from': 'pow-child',
    'grid.link.to': 'tg-89y8',
    'grid.link.type': 'blocks',
  };
  const crossStore = 'BLOCKED on tg-89y8 across stores.';

  test('an open link bead wires a named cross-store blocker', () async {
    final h = _harness(
      _bd(description: crossStore, links: const [linked]),
      stateRoot: _gridHome(),
    );

    expect(
      await h.runner.run(['filing', '--json', 'pow-child']),
      0,
      reason: '${h.out}${h.err}',
    );
    expect(_dependencyRow(h.out)['passed'], isTrue);
    expect(
      _dependencyRow(h.out)['detail'],
      'all named local blockers are wired',
    );
    expect(h.bd.argvs.any((argv) => argv.first == 'list'), isTrue);
    expect(
      h.bd.argvs.map((argv) => argv.first),
      everyElement(isNot(isIn(_mutations))),
    );
  });

  test('without the link bead the same blocker is missing', () async {
    final h = _harness(_bd(description: crossStore), stateRoot: _gridHome());

    expect(await h.runner.run(['filing', '--json', 'pow-child']), 1);
    expect(_dependencyRow(h.out)['passed'], isFalse);
    expect(
      _dependencyRow(h.out)['detail'],
      'missing outgoing blocks edges: tg-89y8',
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
    expect(
      kStateRootHelp,
      'The grid home whose .grid/.beads holds the cross-store link beads.',
    );
    final home = _gridHome();
    final store = p.join(home, '.grid');
    expect(resolve(home), store);
    expect(resolve('$home${p.separator}.'), store);
    expect(resolve(store), store);

    // No value on either seam means the store is not consulted at all.
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

  test('documented grid home reaches the state store', () async {
    final home = _gridHome();
    final h = _harness(_bd(description: crossStore, links: const [linked]));

    expect(
      await h.runner.run([
        'filing',
        '--json',
        '--state-root',
        home,
        'pow-child',
      ]),
      0,
      reason: '${h.out}${h.err}',
    );
    expect(h.linkRoots, [p.join(home, '.grid')]);
    expect(_dependencyRow(h.out)['passed'], isTrue);
    expect(h.err.toString(), isEmpty);
    expect(h.out.toString(), isNot(contains('invalid issue type')));
  });

  test(
    'an unrelated state root is refused LOUD, and nothing is read',
    () async {
      final h = _harness(_bd(description: crossStore, links: const [linked]));

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
      expect(h.linkRoots, isEmpty);
    },
  );

  test('wired cross-store blocker is unchecked without a state root and '
      'passes when consulted', () async {
    final without = _harness(
      _bd(description: crossStore, links: const [linked]),
    );

    expect(await without.runner.run(['filing', '--json', 'pow-child']), 1);
    expect(without.linkRoots, isEmpty);
    expect(without.bd.argvs.any((argv) => argv.first == 'list'), isFalse);
    final unchecked = _dependencyRow(without.out);
    expect(unchecked['passed'], isFalse);
    expect(
      unchecked['detail'],
      'cross-store edges not consulted — pass --state-root',
    );
    expect(unchecked['detail'], isNot(contains('tg-89y8')));
    expect(
      unchecked['detail'],
      isNot(contains('missing outgoing blocks edges')),
    );

    final consulted = _harness(
      _bd(description: crossStore, links: const [linked]),
      stateRoot: _gridHome(),
    );
    expect(
      await consulted.runner.run(['filing', '--json', 'pow-child']),
      0,
      reason: '${consulted.out}${consulted.err}',
    );
    expect(
      _dependencyRow(consulted.out)['detail'],
      'all named local blockers are wired',
    );
  });

  test('an unconsulted store names only the local edge as missing', () async {
    final h = _harness(
      _bd(
        description: 'Depends on pow-1rn.5.\nBLOCKED on tg-89y8 across stores.',
      ),
    );

    expect(await h.runner.run(['filing', '--json', 'pow-child']), 1);
    expect(
      _dependencyRow(h.out)['detail'],
      'missing outgoing blocks edges: pow-1rn.5; '
      'cross-store edges not consulted — pass --state-root',
    );
  });

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
