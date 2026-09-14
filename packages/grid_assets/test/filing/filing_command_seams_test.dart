import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

/// The filing verb's SEAMS: one store, one roster, and no prose.
///
/// Scripted rather than real-bd, because what is asserted here is the argv the
/// verb spawns and the options it registers — the end-to-end proof over a real
/// `bd` store lives in `filing_command_test.dart` and
/// `filing_command_blockers_test.dart`.

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

/// bd's RECORD surface for `pow-child`, carrying the dependency ROWS bd holds.
String _beadReply({
  required String description,
  List<String> blockers = const [],
}) => jsonEncode({
  'schema_version': 1,
  'data': [
    {
      'id': 'pow-child',
      'title': 'child',
      'issue_type': 'task',
      'description': description,
      'acceptance_criteria': '- [ ] checked',
      'metadata': {'validation_plan': 'dart test'},
      'dependencies': [
        for (final blocker in blockers)
          {'issue_id': 'pow-child', 'depends_on_id': blocker, 'type': 'blocks'},
      ],
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
_harness(_ScriptedBdRunner bd, {Set<String>? armed}) {
  final out = StringBuffer();
  final err = StringBuffer();
  final roots = <String>[];
  return (
    runner: CommandRunner<int>('space', 'test station')
      ..addCommand(
        FilingCommand(
          service: FilingService(
            source: ExactSubstationBeadSource(
              runnerFor: (root) {
                roots.add(root);
                return bd;
              },
            ),
          ),
          storeRoot: () => '/work/power_station',
          armedSubstations: () => armed,
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

Map<String, dynamic> _dependencyRow(StringBuffer out) =>
    ((jsonDecode(out.toString()) as Map<String, dynamic>)['requirements']
            as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => row['requirement'] == 'dependencies');

const List<String> _mutations = ['create', 'update', 'close'];

void main() {
  test('prose declares nothing, and ONE store answers the verb', () async {
    // The sentence that used to refuse this bead. bd holds no row, so there is
    // no blocker — and no second store is reached to ask about one.
    final h = _harness(
      _ScriptedBdRunner({
        'query': _beadReply(description: 'BLOCKED on tg-89y8 across stores.'),
      }),
    );

    expect(
      await h.runner.run(['filing', '--json', 'pow-child']),
      0,
      reason: '${h.out}${h.err}',
    );
    expect(
      _dependencyRow(h.out)['detail'],
      'bd holds no blocking dependency rows',
    );
    expect(h.roots.toSet(), {'/work/power_station'});
    expect(h.bd.argvs.map((argv) => argv.first), isNot(contains('list')));
    expect(
      h.bd.argvs.map((argv) => argv.first),
      everyElement(isNot(isIn(_mutations))),
    );
  });

  test('the two prose spellings project identically', () async {
    // AC-1 at the verb level; the end-to-end proof over a real bd store lives
    // in `filing_command_test.dart`.
    final hyphen = _harness(
      _ScriptedBdRunner({
        'query': _beadReply(description: 'Blocked-by: pow-x'),
      }),
    );
    final spaced = _harness(
      _ScriptedBdRunner({'query': _beadReply(description: 'Blocked by pow-x')}),
    );

    expect(await hyphen.runner.run(['filing', '--json', 'pow-child']), 0);
    expect(await spaced.runner.run(['filing', '--json', 'pow-child']), 0);
    expect(_dependencyRow(hyphen.out), _dependencyRow(spaced.out));
    expect(
      _dependencyRow(spaced.out)['detail'],
      'bd holds no blocking dependency rows',
    );
  });

  test('the roster is an INJECTED seam, never an operator flag', () async {
    final filing = FilingCommand(out: StringBuffer(), err: StringBuffer());
    final approve = ApproveCommand(out: StringBuffer(), err: StringBuffer());

    // Fail-closed by default, and the row says WHICH condition refused it.
    expect(noArmedSubstations(), isNull);
    for (final parser in [filing.argParser, approve.argParser]) {
      expect(parser.options.keys, isNot(contains('armed-substations')));
      // The option retired with the cross-store read that was its one reader.
      expect(parser.options.keys, isNot(contains(kStateRootOption)));
    }
    expect(filing.invocation, 'filing [--json] <bead-id>');
    expect(approve.invocation, 'approve --actor <name> [--json] <bead-id>');

    final h = _harness(
      _ScriptedBdRunner({
        'query': _beadReply(
          description: 'Needs the native external reader.',
          blockers: const ['external:the_grid:tg-xh5d'],
        ),
      }),
    );
    expect(await h.runner.run(['filing', '--json', 'pow-child']), 1);
    expect(_dependencyRow(h.out)['passed'], isFalse);
    expect(
      _dependencyRow(h.out)['detail'],
      contains('no station roster was supplied'),
    );
  });

  test(
    'a retired --state-root is a usage refusal, not a silent accept',
    () async {
      final h = _harness(
        _ScriptedBdRunner({'query': _beadReply(description: 'The work.')}),
      );

      await expectLater(
        h.runner.run(['filing', '--json', '--state-root', '/x', 'pow-child']),
        throwsA(
          isA<UsageException>().having(
            (error) => error.message,
            'message',
            contains('state-root'),
          ),
        ),
      );
      expect(h.bd.argvs, isEmpty);
    },
  );
}
