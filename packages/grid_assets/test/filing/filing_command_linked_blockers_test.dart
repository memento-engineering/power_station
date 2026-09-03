import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
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
            links: CrossLinkBlockerSource(runnerFor: (_) => bd),
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
  const linked = {
    'grid.link.from': 'pow-child',
    'grid.link.to': 'tg-89y8',
    'grid.link.type': 'blocks',
  };

  test('an open link bead wires a named cross-store blocker', () async {
    final h = _harness(
      _bd(
        description: 'BLOCKED on tg-89y8 across stores.',
        links: const [linked],
      ),
      stateRoot: '/work/home/.grid',
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
    final h = _harness(
      _bd(description: 'BLOCKED on tg-89y8 across stores.'),
      stateRoot: '/work/home/.grid',
    );

    expect(await h.runner.run(['filing', '--json', 'pow-child']), 1);
    expect(_dependencyRow(h.out)['passed'], isFalse);
    expect(
      _dependencyRow(h.out)['detail'],
      'missing outgoing blocks edges: tg-89y8',
    );
  });

  test('--state-root supplies the grid home, absent means unread', () async {
    final withOption = _harness(
      _bd(
        description: 'BLOCKED on tg-89y8 across stores.',
        links: const [linked],
      ),
    );
    expect(
      await withOption.runner.run([
        'filing',
        '--json',
        '--state-root',
        '/work/home/.grid',
        'pow-child',
      ]),
      0,
      reason: '${withOption.out}${withOption.err}',
    );
    expect(_dependencyRow(withOption.out)['passed'], isTrue);

    final without = _harness(
      _bd(
        description: 'BLOCKED on tg-89y8 across stores.',
        links: const [linked],
      ),
    );
    expect(await without.runner.run(['filing', '--json', 'pow-child']), 1);
    expect(without.bd.argvs.any((argv) => argv.first == 'list'), isFalse);
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
