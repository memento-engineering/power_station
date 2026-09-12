// The one-bead READ verb — `show`.
//
// Offline end to end: the only seam that reaches a store is a scripted
// `BdRunner` Fake (never a mock), so no probe starts a process, a station, a
// bead store or a Dolt server. One group per acceptance id.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_root.dart';

const String _beadId = 'pow-cmnw';

/// The injected work store, written UNNORMALIZED so every probe also proves
/// the command normalizes before the root reaches a runner.
const String _rawStoreRoot = '/work/power_station/packages/..';
const String _storeRoot = '/work/power_station';

/// What the runner Fake does for one `bd` call.
sealed class _Reply {
  const _Reply();
}

/// Answer with an envelope on stdout and exit 0.
final class _Ok extends _Reply {
  const _Ok(this.stdout);
  final String stdout;
}

/// Answer with a non-zero exit — the refusing-`bd` arm.
final class _Fails extends _Reply {
  const _Fails(this.stderr);
  final String stderr;
}

/// Throw instead of answering — the unreachable-`bd` arm.
final class _Throws extends _Reply {
  const _Throws(this.error);
  final Object error;
}

/// A scripted `bd`: replies per subcommand, records every argv it was handed.
final class _ScriptedBd implements BdRunner {
  _ScriptedBd(this.replies);

  final Map<String, _Reply> replies;
  final List<List<String>> argvs = [];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(args);
    final reply = replies[args.first] ?? const _Ok(_emptyEnvelope);
    return switch (reply) {
      _Ok(:final stdout) => BdResult(exitCode: 0, stdout: stdout, stderr: ''),
      _Fails(:final stderr) => BdResult(
        exitCode: 2,
        stdout: '',
        stderr: stderr,
      ),
      _Throws(:final error) => throw error,
    };
  }

  List<List<String>> withVerb(String verb) =>
      argvs.where((argv) => argv.first == verb).toList();
}

const String _emptyEnvelope = '{"schema_version":1,"data":[]}';

/// `bd` could not be run at all — the arm that proves a THROWN read is caught
/// at the service boundary rather than escaping the verb.
final class _BdUnreachable implements Exception {
  const _BdUnreachable();

  @override
  String toString() => 'bd is not on PATH';
}

/// One `bd query` envelope carrying [rows].
String _queryEnvelope(List<Map<String, Object?>> rows) =>
    jsonEncode({'schema_version': 1, 'data': rows});

/// A complete bead row — every field the verb renders, plus the metadata it
/// must NOT render.
Map<String, Object?> _beadRow({
  String title = 'vend a ShowCommand',
  String description = 'no verb prints one bead',
  String design = 'a thin Command over a service',
  String acceptance = '- [ ] AC-1 renders the bead',
  String notes = 'the suppression key is the revision',
  String? updatedAt = '2026-09-08T11:22:33.000Z',
  Map<String, Object?> metadata = const {
    'grid.approved_by': 'nico',
    'grid.approved_at': '2026-09-12T09:00:00.000Z',
    'grid.approved_rev': 'filing:v1:sha256:abc',
    'validation_plan': 'dart test',
    'grid.round': '1',
    'grid.lane.coherence': 'D',
  },
}) => {
  'id': _beadId,
  'title': title,
  'issue_type': 'feature',
  'status': 'in_progress',
  'priority': 2,
  'description': description,
  'design': design,
  'acceptance_criteria': acceptance,
  'notes': notes,
  if (updatedAt != null) 'updated_at': updatedAt,
  'metadata': metadata,
};

/// A `bd dep list` envelope in the released edge-row shape.
String _depEnvelope(List<String> blockers) => jsonEncode({
  'schema_version': 1,
  'data': [
    for (final blocker in blockers)
      {'issue_id': _beadId, 'depends_on_id': blocker, 'type': 'blocks'},
  ],
});

/// A REAL grid home — `<home>/.grid/.beads` — because the shared resolver
/// probes the filesystem to tell a grid home from its own state store.
String _gridHome() {
  final home = Directory.systemTemp.createTempSync('show-grid-home-');
  Directory(p.join(home.path, '.grid', '.beads')).createSync(recursive: true);
  addTearDown(() => home.deleteSync(recursive: true));
  return home.path;
}

/// A directory that is NEITHER a grid home nor a state store.
String _unrelatedRoot() {
  final dir = Directory.systemTemp.createTempSync('show-unrelated-');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir.path;
}

typedef _Harness = ({
  CommandRunner<int> runner,
  ShowCommand command,
  StringBuffer out,
  StringBuffer err,
  _ScriptedBd bd,
  List<String> roots,
});

_Harness _harness(_ScriptedBd bd, {String? stateRoot}) {
  final out = StringBuffer();
  final err = StringBuffer();
  final roots = <String>[];
  final command = ShowCommand(
    service: ShowService(
      runnerFor: (root) {
        roots.add(root);
        return bd;
      },
    ),
    storeRoot: () => _rawStoreRoot,
    stateRoot: () => stateRoot,
    out: out,
    err: err,
  );
  return (
    runner: CommandRunner<int>('space', 'test station')..addCommand(command),
    command: command,
    out: out,
    err: err,
    bd: bd,
    roots: roots,
  );
}

/// The whole bead as one plain rendering: a healthy bead plus two edges.
_ScriptedBd _healthyBd({Map<String, Object?>? row, List<String>? blockers}) =>
    _ScriptedBd({
      'query': _Ok(_queryEnvelope([row ?? _beadRow()])),
      'dep': _Ok(_depEnvelope(blockers ?? const ['tg-89y8', 'space-pww'])),
    });

/// Every UTF-8 byte of [sink], the trailing newline included.
int _bytes(StringBuffer sink) => utf8.encode(sink.toString()).length;

/// The TRUNCATION row a bounded string field prints.
Matcher _withheldRow(String key) => matches(
  RegExp('^${RegExp.escape(key)}: [0-9]+ bytes withheld\$', multiLine: true),
);

/// This package's copy of the implementation, off the shared cwd-independent
/// package root. LOUD when it cannot be read — a source fence that silently
/// reads nothing is a fence that is GONE.
///
/// Never a walk up from the process working directory: that is a process
/// property and `dart test` runs the suites concurrently, so a walk from here
/// could read a directory another file had pointed somewhere else.
File _implementation() {
  final file = File(
    p.join(packageRoot(), 'lib', 'src', 'filing', 'show_command.dart'),
  );
  if (!file.existsSync()) fail('show_command.dart not found at ${file.path}');
  return file;
}

void main() {
  group('AC-1 — the plain rendering, over the exact read', () {
    test('renders every field and reaches the store ONLY through '
        'readExact', () async {
      final h = _harness(_healthyBd());

      expect(await h.runner.run(['show', _beadId]), 0);

      // The store the fake was handed is the NORMALIZED work root, and
      // nothing else.
      expect(h.roots, isNotEmpty);
      expect(h.roots.toSet(), {_storeRoot});

      // One exact-id query, one dependency list, and NEVER `bd show`.
      final queries = h.bd.withVerb('query');
      expect(queries, hasLength(1));
      expect(queries.single, contains('id=$_beadId'));
      expect(h.bd.withVerb('dep'), [
        ['dep', 'list', _beadId, '--json'],
      ]);
      expect(
        h.bd.argvs.map((argv) => argv.first),
        isNot(contains('show')),
        reason: '`bd show` writes .beads/last-touched and trips the watcher',
      );

      final plain = h.out.toString();
      expect(plain, contains('ID: $_beadId'));
      expect(plain, contains('TITLE: vend a ShowCommand'));
      expect(plain, contains('TYPE: feature'));
      expect(plain, contains('STATUS: in_progress'));
      expect(plain, contains('PRIORITY: 2'));
      expect(plain, contains('REVISION: 2026-09-08T11:22:33.000Z'));
      expect(plain, contains('DESCRIPTION:\nno verb prints one bead'));
      expect(plain, contains('DESIGN:\na thin Command over a service'));
      expect(
        plain,
        contains('ACCEPTANCE CRITERIA:\n- [ ] AC-1 renders the bead'),
      );
      expect(plain, contains('NOTES:\nthe suppression key is the revision'));
      expect(plain, contains('APPROVAL:'));
      expect(plain, contains('grid.approved_by: nico'));
      expect(plain, contains('grid.approved_at: 2026-09-12T09:00:00.000Z'));
      expect(plain, contains('grid.approved_rev: filing:v1:sha256:abc'));
      expect(plain, contains('DEPENDENCIES:'));
      expect(
        plain,
        contains('- issue_id=$_beadId depends_on_id=tg-89y8 type=blocks'),
      );
      expect(
        plain,
        contains('- issue_id=$_beadId depends_on_id=space-pww type=blocks'),
      );
      expect(plain, isNot(contains('TRUNCATION:')));
    });

    test('a bead with no edges says so rather than printing nothing', () async {
      final h = _harness(_healthyBd(blockers: const []));

      expect(await h.runner.run(['show', _beadId]), 0);
      expect(h.out.toString(), contains('DEPENDENCIES:\n(none)'));
    });

    test('no bead id is a usage refusal that spawns nothing', () async {
      final h = _harness(_healthyBd());

      expect(await h.runner.run(['show']), 64);
      expect(h.err.toString(), contains('exactly one bead id is required'));
      expect(h.bd.argvs, isEmpty);
    });
  });

  group('AC-2 — one structured map, with no round data in it', () {
    test('--json writes exactly one newline-terminated object', () async {
      final h = _harness(_healthyBd());

      expect(await h.runner.run(['show', '--json', _beadId]), 0);

      final raw = h.out.toString();
      expect(raw.endsWith('\n'), isTrue);
      expect(
        '\n'.allMatches(raw).length,
        1,
        reason: 'one result is ONE line — a skill parses it, never scrapes it',
      );

      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded.keys, [
        'id',
        'shown',
        'unchanged',
        'revision',
        'title',
        'type',
        'status',
        'priority',
        'description',
        'design',
        'acceptance_criteria',
        'notes',
        'approval',
        'dependencies',
      ]);
      expect(decoded['id'], _beadId);
      expect(decoded['shown'], isTrue);
      expect(decoded['unchanged'], isFalse);
      expect(decoded['revision'], '2026-09-08T11:22:33.000Z');
      expect(decoded['title'], 'vend a ShowCommand');
      expect(decoded['type'], 'feature');
      expect(decoded['status'], 'in_progress');
      expect(decoded['priority'], 2);
      expect(decoded['description'], 'no verb prints one bead');
      expect(decoded['design'], 'a thin Command over a service');
      expect(decoded['acceptance_criteria'], '- [ ] AC-1 renders the bead');
      expect(decoded['notes'], 'the suppression key is the revision');
      expect(decoded['approval'], {
        'grid.approved_by': 'nico',
        'grid.approved_at': '2026-09-12T09:00:00.000Z',
        'grid.approved_rev': 'filing:v1:sha256:abc',
      });
      expect(decoded['dependencies'], [
        {'issue_id': _beadId, 'depends_on_id': 'tg-89y8', 'type': 'blocks'},
        {'issue_id': _beadId, 'depends_on_id': 'space-pww', 'type': 'blocks'},
      ]);

      // `bead round` owns the round; this verb must not grow a second view of
      // it — nor leak the rest of the bead's metadata as approval.
      for (final forbidden in [
        'round',
        'lane',
        'grade',
        'rationale',
        'validation_plan',
      ]) {
        expect(raw, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('an absent approval stamp is three null keys, never a missing '
        'map', () async {
      final h = _harness(
        _healthyBd(row: _beadRow(metadata: const {'validation_plan': 'x'})),
      );

      expect(await h.runner.run(['show', '--json', _beadId]), 0);

      final decoded = jsonDecode(h.out.toString()) as Map<String, dynamic>;
      expect(decoded['approval'], {
        'grid.approved_by': null,
        'grid.approved_at': null,
        'grid.approved_rev': null,
      });
    });
  });

  group('AC-3 — every unreadable answer is a bounded, NAMED refusal', () {
    Future<({int? code, String out, String err})> refusal(
      _ScriptedBd bd,
    ) async {
      final h = _harness(bd);
      final code = await h.runner.run(['show', _beadId]);
      return (code: code, out: h.out.toString(), err: h.err.toString());
    }

    void expectNoBeadPayload(String out) {
      for (final leak in [
        'TITLE:',
        'DESCRIPTION:',
        'APPROVAL:',
        'DEPENDENCIES:',
        'vend a ShowCommand',
      ]) {
        expect(out, isNot(contains(leak)), reason: leak);
      }
    }

    test('an empty exact read is "not found", never an empty bead', () async {
      final result = await refusal(
        _ScriptedBd({'query': const _Ok(_emptyEnvelope)}),
      );

      expect(result.code, 1);
      expect(result.out, contains('REFUSED $_beadId: bead $_beadId not found'));
      expect(result.out, contains(_storeRoot));
      expectNoBeadPayload(result.out);
    });

    test('a refusing bd is named, never rethrown', () async {
      final result = await refusal(
        _ScriptedBd({'query': const _Fails('bd: store is locked')}),
      );

      expect(result.code, 1);
      expect(result.out, contains('REFUSED $_beadId'));
      expect(result.out, contains(_beadId));
      expect(result.out, contains('Bd'), reason: 'the failure CLASS is named');
      expectNoBeadPayload(result.out);
    });

    test('an unreachable bd is named, never rethrown', () async {
      final result = await refusal(
        _ScriptedBd({'query': const _Throws(_BdUnreachable())}),
      );

      expect(result.code, 1);
      expect(result.out, contains('REFUSED $_beadId'));
      expect(result.out, contains('_BdUnreachable'));
      expectNoBeadPayload(result.out);
    });

    test('a malformed envelope is named, never rethrown', () async {
      final result = await refusal(
        _ScriptedBd({'query': const _Ok('{not json at all')}),
      );

      expect(result.code, 1);
      expect(result.out, contains('REFUSED $_beadId'));
      expect(result.out, contains('BdParseException'));
      expectNoBeadPayload(result.out);
    });

    test('a duplicate id is named, never silently collapsed', () async {
      final result = await refusal(
        _ScriptedBd({
          'query': _Ok(_queryEnvelope([_beadRow(), _beadRow()])),
        }),
      );

      expect(result.code, 1);
      expect(result.out, contains('REFUSED $_beadId'));
      expect(result.out, contains('StateError'));
      expectNoBeadPayload(result.out);
    });
  });

  group('AC-4 — the SHARED state-root seam, and no second bead store', () {
    test('the parser exposes state-root and NO grid-home of its own', () {
      final h = _harness(_healthyBd());

      expect(h.command.argParser.options, contains('state-root'));
      expect(
        h.command.argParser.options,
        isNot(contains('grid-home')),
        reason: 'the roster-aware --grid-home belongs to the RUNNER',
      );
      expect(h.command.argParser.options, contains('json'));
      expect(h.command.argParser.options, contains('if-revision'));
    });

    test('a documented grid home resolves, and only the WORK root is '
        'read', () async {
      final home = _gridHome();
      final h = _harness(_healthyBd(), stateRoot: home);

      expect(await h.runner.run(['show', _beadId]), 0);
      expect(h.roots.toSet(), {_storeRoot});
      expect(h.roots, isNot(contains(home)));
      expect(h.roots, isNot(contains(p.join(home, '.grid'))));
    });

    test('an unrelated --state-root refuses BEFORE any read', () async {
      final h = _harness(_healthyBd());

      expect(
        await h.runner.run(['show', '--state-root', _unrelatedRoot(), _beadId]),
        1,
      );
      expect(h.err.toString(), contains('show: failed to read $_beadId'));
      expect(h.bd.argvs, isEmpty, reason: 'the guard runs before the store');
      expect(h.roots, isEmpty);
    });
  });

  group('AC-5 — the hard cap, and an explicit marker for every cut', () {
    // Multibyte in every variable string, plus edges too long to fit an equal
    // share, so a bound MUST cut all eight fields and drop every edge.
    final long = '日本語の説明・テスト🧪 ' * 260;
    final row = _beadRow(
      title: 'タイトル $long',
      description: '説明 $long',
      design: '設計 $long',
      acceptance: '受入 $long',
      notes: 'ノート $long',
      metadata: {
        'grid.approved_by': 'nico $long',
        'grid.approved_at': '2026-09-12T09:00:00.000Z $long',
        'grid.approved_rev': 'filing:v1:sha256:$long',
      },
    );
    final blockers = [for (var i = 0; i < 40; i++) 'tg-${'q' * 150}-$i'];

    test('plain output fits the cap and names every cut', () async {
      final h = _harness(_healthyBd(row: row, blockers: blockers));

      expect(await h.runner.run(['show', _beadId]), 0);
      expect(_bytes(h.out), lessThanOrEqualTo(kShowOutputCapBytes));
      // Near the ceiling, not far under it: a bound that withholds budget it
      // had room for is a quieter version of the same waste.
      expect(_bytes(h.out), greaterThan(kShowOutputCapBytes - 800));

      final plain = h.out.toString();
      expect(plain, contains('ID: $_beadId'));
      expect(plain, contains('TRUNCATION:'));
      expect(plain, contains('cap_bytes: $kShowOutputCapBytes'));
      for (final key in const [
        'title',
        'description',
        'design',
        'acceptance_criteria',
        'notes',
        'grid.approved_by',
        'grid.approved_at',
        'grid.approved_rev',
      ]) {
        expect(plain, _withheldRow(key), reason: key);
      }
      expect(
        plain,
        matches(
          RegExp(r'^dependency_edges: 40 edges withheld$', multiLine: true),
        ),
      );
    });

    test('json output fits the cap, still decodes, and cuts on RUNE '
        'boundaries', () async {
      final h = _harness(_healthyBd(row: row, blockers: blockers));

      expect(await h.runner.run(['show', '--json', _beadId]), 0);
      expect(_bytes(h.out), lessThanOrEqualTo(kShowOutputCapBytes));
      expect(_bytes(h.out), greaterThan(kShowOutputCapBytes - 800));

      final decoded = jsonDecode(h.out.toString()) as Map<String, dynamic>;
      expect(decoded['id'], _beadId);
      expect(decoded['type'], 'feature');
      expect(decoded['status'], 'in_progress');
      expect(decoded['revision'], '2026-09-08T11:22:33.000Z');

      final truncation = decoded['truncation']! as Map<String, dynamic>;
      expect(truncation['cap_bytes'], kShowOutputCapBytes);
      final withheld = truncation['withheld']! as Map<String, dynamic>;
      expect(
        withheld.keys,
        containsAll(const [
          'title',
          'description',
          'design',
          'acceptance_criteria',
          'notes',
          'grid.approved_by',
          'grid.approved_at',
          'grid.approved_rev',
          'dependency_edges',
        ]),
      );
      for (final entry in withheld.entries) {
        expect(entry.value, isA<int>(), reason: entry.key);
        expect(entry.value as int, greaterThan(0), reason: entry.key);
      }
      expect(withheld['dependency_edges'], 40);
      expect(decoded['dependencies'], isEmpty);

      // A cut string is a clean leading RUNE prefix — never half a character.
      final description = decoded['description']! as String;
      expect(description, isNotEmpty);
      expect((row['description']! as String).startsWith(description), isTrue);
      expect(description.contains('�'), isFalse);
    });

    test('an oversized refusal reason is bounded and says so', () async {
      final h = _harness(
        _ScriptedBd({'query': _Throws(StateError('boom ${'x' * 40000}'))}),
      );

      expect(await h.runner.run(['show', _beadId]), 1);
      expect(_bytes(h.out), lessThanOrEqualTo(kShowOutputCapBytes));

      final plain = h.out.toString();
      expect(plain, contains('REFUSED $_beadId'));
      expect(plain, contains('StateError'));
      expect(plain, contains('cap_bytes: $kShowOutputCapBytes'));
      expect(plain, _withheldRow('reason'));

      final json = _harness(
        _ScriptedBd({'query': _Throws(StateError('boom ${'x' * 40000}'))}),
      );
      expect(await json.runner.run(['show', '--json', _beadId]), 1);
      expect(_bytes(json.out), lessThanOrEqualTo(kShowOutputCapBytes));
      final decoded = jsonDecode(json.out.toString()) as Map<String, dynamic>;
      expect(decoded['shown'], isFalse);
      final withheld =
          (decoded['truncation']! as Map<String, dynamic>)['withheld']!
              as Map<String, dynamic>;
      expect(withheld['reason'], greaterThan(0));
    });
  });

  group('AC-6 — suppression is keyed on the ANSWER', () {
    const revision = '2026-09-08T11:22:33.000Z';

    test('an EXACT revision withholds the prose and the edges', () async {
      final h = _harness(_healthyBd());

      expect(
        await h.runner.run(['show', '--if-revision', revision, _beadId]),
        0,
      );
      expect(h.out.toString(), 'UNCHANGED $_beadId revision $revision\n');
    });

    test('surrounding whitespace is trimmed, not a mismatch', () async {
      final h = _harness(_healthyBd());

      expect(
        await h.runner.run(['show', '--if-revision', '  $revision  ', _beadId]),
        0,
      );
      expect(h.out.toString(), 'UNCHANGED $_beadId revision $revision\n');
    });

    test('an unchanged answer is still ONE structured result', () async {
      final h = _harness(_healthyBd());

      expect(
        await h.runner.run([
          'show',
          '--json',
          '--if-revision',
          revision,
          _beadId,
        ]),
        0,
      );
      expect(jsonDecode(h.out.toString()), {
        'id': _beadId,
        'shown': true,
        'unchanged': true,
        'revision': revision,
      });
    });

    for (final (label, args) in <(String, List<String>)>[
      ('an ABSENT revision', ['show', _beadId]),
      ('a BLANK revision', ['show', '--if-revision', '   ', _beadId]),
      (
        'a MISMATCHED revision',
        ['show', '--if-revision', '2026-01-01T00:00:00.000Z', _beadId],
      ),
    ]) {
      test('$label renders fresh', () async {
        final h = _harness(_healthyBd());

        expect(await h.runner.run(args), 0);
        final plain = h.out.toString();
        expect(plain, isNot(contains('UNCHANGED')));
        expect(plain, contains('TITLE: vend a ShowCommand'));
        expect(plain, contains('depends_on_id=tg-89y8'));
      });
    }

    test('a bead with NO revision can never prove itself unchanged', () async {
      final h = _harness(_healthyBd(row: _beadRow(updatedAt: null)));

      expect(
        await h.runner.run(['show', '--if-revision', revision, _beadId]),
        0,
      );
      final plain = h.out.toString();
      expect(plain, isNot(contains('UNCHANGED')));
      expect(plain, contains('REVISION: \n'));
      expect(plain, contains('TITLE: vend a ShowCommand'));
    });
  });

  group('AC-7 — the store-only, station-independent fence', () {
    final source = _implementation().readAsStringSync();

    test('the store is reached through the SHARED exact read', () {
      expect(source, contains('readExact'));
      expect(
        source,
        contains('BeadDependency'),
        reason: "an edge stays beads' own value type",
      );
      expect(
        source,
        isNot(contains('class ShowDependencyEdge')),
        reason: 'a parallel edge type is the duplication this bead forbids',
      );
      expect(
        RegExp(r"'show'\s*,").hasMatch(source),
        isFalse,
        reason: '`bd show` self-triggers the store watcher (A37)',
      );
    });

    test('no station, roster, harness or raw-spawn symbol is named', () {
      for (final forbidden in const [
        'StationCommandClient',
        'grid_cli',
        'codedRosterOf',
        'mountedRosterOf',
        'GridDelegate',
        'Process.start',
        'Process.run',
        'Process.runSync',
        'DoltQueryService',
        'DoltEndpoint',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason:
              'an operator reads a bead while the station is DOWN — "$forbidden" '
              'would put something between the verb and the store',
        );
      }
    });
  });
}
