import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart' show SubstationScope;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'filing_evidence_fakes.dart';
import 'real_bd_store.dart';

/// A recording [BdRunner] that answers every read with one enveloped list.
final class _RecordingBdRunner implements BdRunner {
  _RecordingBdRunner(this.rows);

  final List<Map<String, Object?>> rows;
  final List<List<String>> argvs = [];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    argvs.add(args);
    final type = args.contains('-t') ? args[args.indexOf('-t') + 1] : '';
    return BdResult(
      exitCode: 0,
      stdout: jsonEncode({
        'schema_version': 1,
        'data': [
          for (final row in rows)
            if (row['issue_type'] == type) row,
        ],
      }),
      stderr: '',
    );
  }
}

/// A [ShellRunner] that answers every `decisions index` run with one canned
/// roster-mode envelope, recording what it was asked.
final class _CannedDecisionShell implements ShellRunner {
  _CannedDecisionShell(this.body);

  final String body;
  final List<String> commands = [];

  // The optional deadline is part of the `ShellRunner.run` contract; this
  // decision-index Fake ignores the bound and answers its canned envelope.
  @override
  Future<ShellRunResult> run({
    required String workingDirectory,
    required String command,
    Duration? deadline,
  }) async {
    commands.add(command);
    return ShellRunResult(exitCode: 0, output: body);
  }
}

void main() {
  test(
    'real bd filing passes all ten requirements',
    skip: skipWithoutBd,
    () async {
      final store = await filingStore();
      await runBd(store, [
        'create',
        '--id',
        'filing-blocker',
        '--title',
        'blocker',
        '--type',
        'task',
        '--actor',
        'test',
      ]);
      await runBd(store, [
        'create',
        '--id',
        'filing-good',
        '--title',
        'good filing',
        '--type',
        'task',
        '--defer',
        '+1h',
        '--description',
        'Package: grid_assets',
        '--acceptance',
        '- [ ] dart test passes',
        '--metadata',
        '{"validation_plan":"dart test"}',
        '--actor',
        'test',
      ]);
      await runBd(store, [
        'dep',
        'add',
        'filing-good',
        'filing-blocker',
        '--actor',
        'test',
      ]);

      final h = harness(store);
      expect(
        await h.runner.run(['filing', '--json', 'filing-good']),
        0,
        reason: '${h.out}\n${h.err}',
      );
      final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
      final rows = (report['requirements'] as List)
          .cast<Map<String, dynamic>>();
      expect(report['passed'], isTrue);
      expect(rows, hasLength(11));
      expect(rows.every((row) => row['passed'] == true), isTrue);
    },
  );

  test(
    'reports every failed requirement and exits non-zero',
    skip: skipWithoutBd,
    () async {
      final store = await filingStore();
      await runBd(store, [
        'create',
        '--id',
        'filing-bad',
        '--title',
        'bad filing',
        '--type',
        'epic',
        '--description',
        'No plan, no acceptance, not driveable.',
        '--metadata',
        '{"validation_plan":" "}',
        '--actor',
        'test',
      ]);
      // The one row a bead's own TEXT can no longer fail: the dependency row
      // is a projection of the rows bd holds, and bd holds none.
      await runBd(store, [
        'dep',
        'add',
        'filing-bad',
        'external:nowhere:cap',
        '--actor',
        'test',
      ]);

      final h = harness(store, armed: const {'the_grid'});
      expect(await h.runner.run(['filing', '--json', 'filing-bad']), 1);
      final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
      final rows = (report['requirements'] as List)
          .cast<Map<String, dynamic>>();
      expect(report['passed'], isFalse);
      expect(rows, hasLength(11));
      // The four PRESENCE rows are what this bead fails; the six VIABILITY
      // rows and the content row have nothing to refuse, because a bead with
      // no plan, no acceptance and no citations carries no unviable text.
      expect(
        {
          for (final row in rows)
            if (row['passed'] == false) row['requirement'],
        },
        {
          'driveable_type',
          'validation_plan',
          'acceptance_criteria',
          'dependencies',
        },
      );
      expect(
        dependencyRow(h.out)['detail'],
        contains('external:nowhere:cap names "nowhere"'),
      );
    },
  );

  test(
    'AC-1 — over a REAL bd store, the two prose spellings agree',
    skip: skipWithoutBd,
    () async {
      final store = await filingStore();
      for (final (id, description) in const [
        ('filing-hyphen', 'Blocked-by: filing-x'),
        ('filing-spaced', 'Blocked by filing-x'),
      ]) {
        await runBd(store, [
          'create',
          '--id',
          id,
          '--title',
          'prose',
          '--type',
          'task',
          '--description',
          description,
          '--acceptance',
          '- [ ] dart test passes',
          '--metadata',
          '{"validation_plan":"dart test"}',
          '--actor',
          'test',
        ]);
      }

      final hyphen = harness(store);
      final spaced = harness(store);
      expect(await hyphen.runner.run(['filing', '--json', 'filing-hyphen']), 0);
      expect(await spaced.runner.run(['filing', '--json', 'filing-spaced']), 0);
      expect(dependencyRow(hyphen.out), dependencyRow(spaced.out));
      expect(
        dependencyRow(spaced.out)['detail'],
        'bd holds no blocking dependency rows',
      );
    },
  );

  test('usage and missing beads fail loudly', skip: skipWithoutBd, () async {
    final store = await filingStore();
    expect(await harness(store).runner.run(['filing']), 64);
    expect(
      await harness(store).runner.run(['filing', 'filing-a', 'filing-b']),
      64,
    );
    final missing = harness(store);
    expect(await missing.runner.run(['filing', '--json', 'filing-missing']), 1);
    final report = jsonDecode(missing.out.toString()) as Map<String, dynamic>;
    expect(report['passed'], isFalse);
    expect(report['requirements'], isEmpty);
    expect(report['error'], 'bead not found');
  });

  test('default bead catalog uses scoped all-status bd list reads', () async {
    // The scoped read is the ratified per-store mechanism
    // (power_station#the-per-store-bead-read-is-scoped-never-the-export-surface,
    // amending A11 clause (3)). `bd export` cannot answer this: it is refused
    // outright in proxied-server mode, and older bd builds returned an EMPTY
    // export for a NON-empty store — "this store has no beads" is the one
    // answer that must never reach the bead_references row, because an empty
    // catalog refuses every cited id.
    final bd = _RecordingBdRunner([
      {'id': 'pow-one', 'title': 'one', 'issue_type': 'task'},
      {'id': 'pow-two', 'title': 'two', 'issue_type': 'decision'},
    ]);
    final beads = await BdListAllStatusBeadSource(runnerFor: (_) => bd).read(
      const SubstationScope(
        name: 'power_station',
        root: '/w/power_station',
        prefix: 'pow',
      ),
    );

    expect(beads.map((bead) => bead.id).toSet(), {'pow-one', 'pow-two'});
    expect(bd.argvs, [
      for (final type in IssueType.coreTypes)
        ['list', '-t', type.wire, '--status', 'all', '--json', '--limit', '0'],
    ]);
    expect(bd.argvs.map((argv) => argv.first), everyElement(isNot('export')));
  });

  test(
    'default filing wiring resolves live bead and decision evidence',
    skip: skipWithoutBd,
    () async {
      final work = await bdStore(prefix: 'pow');
      final attached = await bdStore(prefix: 'tg');
      await runBd(attached, [
        'create',
        '--id',
        'tg-0b64',
        '--title',
        'the attached bead',
        '--type',
        'task',
        '--actor',
        'test',
      ]);

      // A real register directory: the index answers with a slug, and the
      // lookup resolves it to the entry file that carries it.
      const slug = 'adr-0004-station-throughput-outranks-staging-ceremony';
      final register = Directory.systemTemp.createTempSync('filing-register-');
      addTearDown(() => register.deleteSync(recursive: true));
      File(p.join(register.path, 'a.md')).writeAsStringSync(
        '---\nslug: $slug\nstatus: accepted\n---\n\nThroughput outranks '
        'ceremony.\n',
      );
      final shell = _CannedDecisionShell(
        jsonEncode({
          'spec': 2,
          'decisions': [
            {
              'slug': slug,
              'originRegister': 'power_station',
              'originPath': register.path,
              'status': 'accepted',
              'surfaces': <String>['packages/grid_assets/**'],
            },
          ],
        }),
      );

      Future<Map<String, dynamic>> file(String id, String description) async {
        await runBd(work, [
          'create',
          '--id',
          id,
          '--title',
          'wired filing',
          '--type',
          'task',
          '--description',
          description,
          '--acceptance',
          '- [ ] dart test passes',
          '--metadata',
          '{"validation_plan":"dart test"}',
          '--actor',
          'test',
        ]);
        final out = StringBuffer();
        final err = StringBuffer();
        final runner = CommandRunner<int>('space', 'test station')
          ..addCommand(
            FilingCommand(
              storeRoot: () => work.path,
              runnerFor: (root) => ProcessBdRunner(workspaceRoot: root),
              // This probe measures the LIVE mechanical evidence legs. The
              // advisory is an inference call and is scripted, so nothing here
              // reaches a model.
              advisory: FakeFilingAdvisory(),
              owningScope: SubstationScope(
                name: 'power_station',
                root: work.path,
                prefix: 'pow',
              ),
              attachedScopes: [
                SubstationScope(
                  name: 'the_grid',
                  root: attached.path,
                  prefix: 'tg',
                ),
              ],
              decisionShell: shell,
              decisionInvocation: 'space',
              decisionGridHome: work.path,
              out: out,
              err: err,
            ),
          );
        await runner.run(['filing', '--json', id]);
        return jsonDecode(out.toString()) as Map<String, dynamic>;
      }

      // An id only the ATTACHED store holds, and a decision the register does.
      final wired = await file(
        'pow-wired',
        'Follows tg-0b64 under power_station#$slug.',
      );
      expect(
        ((wired['requirements']! as List).cast<Map<String, dynamic>>())
            .where((row) => row['passed'] == false)
            .map((row) => '${row['requirement']}: ${row['detail']}'),
        isEmpty,
      );
      expect(wired['passed'], isTrue);
      expect(shell.commands, isNotEmpty);

      // Change ONLY the cited slug: the same wiring now refuses, and names it.
      final invented = await file(
        'pow-invents',
        'Follows tg-0b64 under power_station#a-rule-this-round-creates.',
      );
      final row =
          ((invented['requirements']! as List).cast<Map<String, dynamic>>())
              .singleWhere(
                (row) => row['requirement'] == 'decision_references',
              );
      expect(invented['passed'], isFalse);
      expect(row['passed'], isFalse);
      expect(row['detail'], contains('a-rule-this-round-creates'));
      expect(
        ((invented['requirements']! as List).cast<Map<String, dynamic>>())
            .singleWhere(
              (row) => row['requirement'] == 'bead_references',
            )['passed'],
        isTrue,
      );
    },
  );

  group('the filing verb runs the pre-stamp advisory after the mechanical '
      'rows', () {
    ({CommandRunner<int> runner, StringBuffer out, FakeFilingAdvisory advisory})
    verb(FilingAdvisoryVerdict verdict) {
      final out = StringBuffer();
      final advisory = FakeFilingAdvisory(verdict);
      return (
        runner: CommandRunner<int>('space', 'test station')
          ..addCommand(
            FilingCommand(
              service: FilingService(
                source: ExactSubstationBeadSource(
                  runnerFor: (_) => FakeExactBeadRunner(
                    const Bead(
                      id: 'pow-child',
                      title: 'child',
                      issueType: IssueType.task,
                    ).copyWith(
                      description: 'A real brief.',
                      acceptanceCriteria: '- [ ] checked',
                    ),
                  ),
                ),
                evidence: FakeFilingEvidenceSource(completeEmptyEvidence),
                advisory: advisory,
              ),
              storeRoot: () => '/work/power_station',
              out: out,
              err: StringBuffer(),
            ),
          ),
        out: out,
        advisory: advisory,
      );
    }

    test('--readiness defaults to run, and the advisory prints LAST', () async {
      final h = verb(const FilingAdvisoryPassed(readinessGrade: 'B'));
      expect(
        await h.runner.run(['filing', 'pow-child']),
        0,
        reason: '${h.out}',
      );
      expect(h.advisory.calls, hasLength(1));
      final plain = h.out.toString();
      expect(plain, contains('PASS advisory: bead-readiness B'));
      expect(
        plain.indexOf('PASS advisory'),
        greaterThan(plain.indexOf('decision_references')),
        reason: 'every mechanical row first, then the judgement',
      );
    });

    test('an advisory refusal exits non-zero and prints the lens\'s OWN fix '
        'text, unabridged', () async {
      final hold = renderRefinementAsk(
        grade: 'D',
        rationale: 'names no surface',
      );
      final h = verb(FilingAdvisoryRefused(rule: 'readiness', reason: hold));

      expect(await h.runner.run(['filing', 'pow-child']), 1);
      expect(h.out.toString(), contains('FAIL advisory (readiness):'));
      expect(h.out.toString(), contains(hold));
    });

    test(
      '--readiness=skip waives it: no ask, and the report says so',
      () async {
        final h = verb(const FilingAdvisoryPassed(readinessGrade: 'B'));
        expect(
          await h.runner.run([
            'filing',
            '--json',
            '--readiness=skip',
            'pow-child',
          ]),
          0,
          reason: '${h.out}',
        );
        expect(h.advisory.calls, isEmpty);
        final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
        expect(report['passed'], isTrue);
        expect(report['advisory'], {'outcome': 'skipped'});
        // The mechanical rows are untouched — the advisory is never one of
        // them. It rides its own member, so the lane counts exactly what the
        // contract evaluates and the waiver adds nothing to it.
        expect((report['requirements'] as List), hasLength(11));
      },
    );

    test('an unknown --readiness value is a usage refusal', () async {
      final h = verb(const FilingAdvisoryPassed(readinessGrade: 'B'));
      await expectLater(
        h.runner.run(['filing', '--readiness=maybe', 'pow-child']),
        throwsA(isA<UsageException>()),
      );
      expect(h.advisory.calls, isEmpty);
    });
  });
}
