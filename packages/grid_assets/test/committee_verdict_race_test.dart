// The 2026-07-24 committee-race regression (operator bridge; live incident
// tg-60t / pow-t2z, introduced by PR #65's join + ledger sequencing).
//
// THE OBSERVED RACE, reconstructed from the tg-60t worktree (all times CDT):
//   23:53:16  wave-1's four spec lanes spawn in parallel
//   23:57:56  route#1 → SpecRespec: ledger round=1 written, `grade: F` stamped
//   00:00:44  plan-completeness#2 spawns MID-WAVE (the engine's derived wave
//             re-keys the closure node-by-node; stale positive terminals of the
//             OLD lane incarnations kept the re-keyed route/lanes' deps
//             "satisfied" while specify#2 was still running)
//   00:04:15  route#2 runs over a PARTIAL join — one current-round artifact
//             (plan-completeness#2, round 1) + three STALE round-0 files — the
//             three stale lanes silently DON'T JOIN, the surviving vector is
//             all A–C ⇒ a FALSE SpecAdvance, and the advance arm DELETES the
//             respec ledger mid-wave (the counter is consumed)
//   00:12:50  clear-critique#2 finally runs (specify#2 completed 00:12:46) and
//             WIPES the same round's already-written verdicts
//   00:13/15  coherence#2 / acceptance#2 stamp round=0 (the ledger is gone)
//   00:20     the session dies breaker-exhausted; no gate is minted
//
// What this file pins:
//   1. the ROUTE never decides over a partial current-round join — a lane that
//      has not produced THIS round's artifact is WAITED for (and the ledger is
//      never consumed by a partial decision);
//   2. a lane that FINISHED this round without a canonical artifact
//      (envelope / fail-closed transports) fails LOUD, ONCE — an Escalate that
//      names the lane and cites NO grade for it;
//   3. the WIPE (ClearCritiqueCapability) is a ROUND-START sweep: it deletes
//      stale/foreign/unstamped files but never THIS round's verdicts, so a
//      wipe that lands between lanes (the mixed-generation wave) cannot orphan
//      an already-graded lane;
//   4. every critic result payload carries the ROUND it was recorded against,
//      so the route can tell "finished this round, artifact-less" (loud) from
//      "not finished this round yet" (wait).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

const _parent = 'tg-60t/spec_review';
const _gating = kSpecGatingRubric;
const _critics =
    'spec-validation,coherence,adr-alignment,acceptance-testability,'
    'plan-completeness';

/// Plants one canonical verdict artifact stamped for THIS node path + [round].
void _plantVerdict(
  String ws,
  String rubric, {
  required int round,
  String grade = 'A',
  String rationale = 'fine',
}) {
  File(p.join(ws, '.grid', 'critique', '$rubric.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode({
        'rubric': rubric,
        'version': 1,
        'grade': grade,
        'rationale': rationale,
        'nodePath': '$_parent/$rubric',
        'round': round,
      }),
    );
}

/// The SiblingView of a session whose five lanes are all POSITIVE-TERMINAL,
/// with per-lane result payloads ([results]) exactly as the lanes' `result()`
/// recorded them (grade/transport/round).
SiblingView _siblings(Map<String, Map<String, String>> results) => SiblingView(
  cursor: {
    for (final id in kSpecCommitteeRubrics)
      '$_parent/$id': const NodeCursor(state: StepState.complete),
    '$_parent/route': const NodeCursor(state: StepState.running),
  },
  results: {
    for (final entry in results.entries) '$_parent/${entry.key}': entry.value,
  },
);

FakeTreeContext _context(String ws, Map<String, Map<String, String>> results) =>
    FakeTreeContext(
      values: {
        SiblingView: _siblings(results),
        Workspace: testWorkspace(
          'tg-60t',
          workspaceDir: ws,
          branch: 'grid/tg-60t',
        ),
      },
    );

StepArgs _routeArgs({int round = 0}) => stepArgs(
  '$_parent/route',
  params: {'critics': _critics, 'gating': _gating, 'grid.round': '$round'},
);

/// The wave-1 lane results as the OLD incarnations recorded them: round 0,
/// transport file, a fixable D on plan-completeness (what triggered the
/// respec).
Map<String, Map<String, String>> _waveOneResults() => {
  _gating: {'grade': 'A', 'transport': 'structural', 'round': '1'},
  'coherence': {'grade': 'A', 'transport': 'file', 'round': '0'},
  'adr-alignment': {'grade': 'A', 'transport': 'file', 'round': '0'},
  'acceptance-testability': {'grade': 'B', 'transport': 'file', 'round': '0'},
  'plan-completeness': {'grade': 'D', 'transport': 'file', 'round': '0'},
};

void main() {
  late Directory ws;
  setUp(() => ws = Directory.systemTemp.createTempSync('committee-race-'));
  tearDown(() => ws.deleteSync(recursive: true));

  group('the spec route under the mid-wave race (tg-60t 00:04:15)', () {
    // The disk exactly as route#2 found it: the respec wave is in flight
    // (ledger round=1), ONE lane has re-run and stamped round 1, the other
    // three judgement lanes still hold WAVE-1 round-0 files (clear-critique#2
    // has not run yet — specify#2 is still running).
    void plantMidWaveDisk() {
      writeRespecLedger(
        ws.path,
        const RespecLedger(
          round: 1,
          lanes: [
            RespecLane(
              rubric: 'plan-completeness',
              grade: 'D',
              rationale: 'step 3 names no test command',
            ),
          ],
        ),
      );
      _plantVerdict(ws.path, 'plan-completeness', round: 1, grade: 'C');
      _plantVerdict(ws.path, 'coherence', round: 0);
      _plantVerdict(ws.path, 'adr-alignment', round: 0);
      _plantVerdict(ws.path, 'acceptance-testability', round: 0, grade: 'B');
    }

    test('a PARTIAL current-round join is never decided: the route WAITS for '
        'the re-keyed lanes instead of advancing over the one lane that '
        'happened to finish first — the park is a VISIBLE Escalate gate '
        '(tg-q3q0) and the ledger is NOT consumed', () async {
      plantMidWaveDisk();
      await expectLater(
        const SpecRouteCapability(
          lanePoll: Duration(milliseconds: 10),
          laneWaitBudget: Duration(milliseconds: 200),
        ).route(_context(ws.path, _waveOneResults()), _routeArgs(round: 1)),
        completion(
          isA<Escalate>().having(
            (e) => e.reason,
            'reason',
            allOf(
              contains('coherence'),
              contains('adr-alignment'),
              contains('acceptance-testability'),
              contains('round 1'),
              // The refusal cites NO grade for the un-joined lanes (the
              // ratified pow-96s invariant, kept under refusal too).
              isNot(contains('=A')),
              isNot(contains('=B')),
              isNot(contains('=D')),
            ),
          ),
        ),
      );
      // The counter survives the refusal: the wave's round is still open.
      expect(readRespecLedger(ws.path)?.round, 1);
      // The one fresh verdict survives too — refusing never destroys work.
      expect(
        currentVerdictFromFile(
          workspaceDir: ws.path,
          rubric: 'plan-completeness',
          nodePath: '$_parent/plan-completeness',
          round: 1,
        ),
        isNotNull,
      );
    });

    test('the wait HEALS: when the re-keyed lanes land their current-round '
        'artifacts during the poll, the route decides over the FULL fresh '
        'vector', () async {
      plantMidWaveDisk();
      // The wave completes while the route polls: the three lanes re-run and
      // stamp round 1 (all passing — the respec corrected the spec).
      Timer(const Duration(milliseconds: 120), () {
        _plantVerdict(ws.path, 'coherence', round: 1);
        _plantVerdict(ws.path, 'adr-alignment', round: 1);
        _plantVerdict(ws.path, 'acceptance-testability', round: 1, grade: 'B');
      });
      final out = await const SpecRouteCapability(
        lanePoll: Duration(milliseconds: 15),
        laneWaitBudget: Duration(seconds: 10),
      ).route(_context(ws.path, _waveOneResults()), _routeArgs(round: 1));
      expect(out, isA<Advance>());
      final payload = (out as Advance).payload!;
      expect(payload['verdict'], 'advance');
      expect(payload['rule'], 'all-approve');
      // The full five-lane vector — including the mid-wave early finisher.
      expect(payload['grades'], contains('plan-completeness=C'));
      expect(payload['grades'], contains('coherence=A'));
      expect(payload['grades'], contains('adr-alignment=A'));
      expect(payload['grades'], contains('acceptance-testability=B'));
      // A REAL advance spends the counter — exactly as before.
      expect(readRespecLedger(ws.path), isNull);
    });

    test('a lane that FINISHED this round with no canonical artifact '
        '(envelope/fail-closed transport) fails LOUD, ONCE — an Escalate that '
        'names the lane and cites no grade for it', () async {
      // Round 0, no ledger. Three lanes wrote artifacts; `coherence` graded
      // through the stdout-envelope fallback (tg-291) — no file exists.
      _plantVerdict(ws.path, 'adr-alignment', round: 0);
      _plantVerdict(ws.path, 'acceptance-testability', round: 0, grade: 'B');
      _plantVerdict(ws.path, 'plan-completeness', round: 0, grade: 'C');
      final results = {
        _gating: {'grade': 'A', 'transport': 'structural', 'round': '0'},
        'coherence': {'grade': 'C', 'transport': 'envelope', 'round': '0'},
        'adr-alignment': {'grade': 'A', 'transport': 'file', 'round': '0'},
        'acceptance-testability': {
          'grade': 'B',
          'transport': 'file',
          'round': '0',
        },
        'plan-completeness': {'grade': 'C', 'transport': 'file', 'round': '0'},
      };
      final out = await const SpecRouteCapability(
        lanePoll: Duration(milliseconds: 10),
        laneWaitBudget: Duration(milliseconds: 200),
      ).route(_context(ws.path, results), _routeArgs());
      expect(out, isA<Escalate>());
      final reason = (out as Escalate).reason;
      expect(reason, contains('coherence'));
      expect(reason, contains('envelope'));
      // The ratified pow-96s invariant: no grade is ever cited for a lane with
      // no current-round artifact on disk.
      expect(reason, isNot(contains('coherence=C')));
    });
  });

  group('the round-start sweep (tg-60t 00:12:50 — the wipe between lanes)', () {
    test('ClearCritiqueCapability never destroys THIS round\'s verdicts: a '
        'wipe landing after a same-round lane already graded keeps that '
        'verdict and deletes only stale/foreign/unstamped files', () async {
      // The wave's round is 1 (the ledger the respec wrote is live).
      writeRespecLedger(
        ws.path,
        const RespecLedger(
          round: 1,
          lanes: [
            RespecLane(rubric: 'plan-completeness', grade: 'D', rationale: 'x'),
          ],
        ),
      );
      // A same-round verdict an early re-keyed lane already wrote…
      _plantVerdict(ws.path, 'plan-completeness', round: 1, grade: 'C');
      // …a stale wave-1 verdict, a foreign node's verdict, an unstamped file,
      // and the gating rc (never stamped — the wipe stays ITS fence).
      _plantVerdict(ws.path, 'coherence', round: 0);
      File(
        p.join(ws.path, '.grid', 'critique', 'adr-alignment.json'),
      ).writeAsStringSync(
        jsonEncode({
          'rubric': 'adr-alignment',
          'grade': 'A',
          'nodePath': 'OTHER-bead/spec_review/adr-alignment',
          'round': 1,
        }),
      );
      File(
        p.join(ws.path, '.grid', 'critique', 'acceptance-testability.json'),
      ).writeAsStringSync('{ not json');
      File(
        p.join(ws.path, '.grid', 'critique', 'spec-validation.rc'),
      ).writeAsStringSync('0\n');

      final outcome = await const ClearCritiqueCapability().run(
        FakeTreeContext(
          values: {
            Workspace: testWorkspace(
              'tg-60t',
              workspaceDir: ws.path,
              branch: 'grid/tg-60t',
            ),
          },
        ),
        stepArgs('$_parent/clear-critique', params: const {'grid.round': '1'}),
      );
      expect(outcome, isA<Ok>());
      final dir = Directory(p.join(ws.path, '.grid', 'critique'));
      expect(
        dir.listSync().map((e) => p.basename(e.path)).toList()..sort(),
        ['plan-completeness.json'],
        reason:
            'the current round\'s verdict survives; stale/foreign/unstamped '
            'files and the rc are swept',
      );
    });

    test('with no ledger (round 0) the sweep still clears a PRIOR session\'s '
        'differently-rounded leftovers and non-verdict files', () async {
      _plantVerdict(ws.path, 'coherence', round: 2); // a prior wave's.
      File(
        p.join(ws.path, '.grid', 'critique', 'pinned.diff'),
      ).writeAsStringSync('diff');
      final outcome = await const ClearCritiqueCapability().run(
        FakeTreeContext(
          values: {
            Workspace: testWorkspace(
              'tg-60t',
              workspaceDir: ws.path,
              branch: 'grid/tg-60t',
            ),
          },
        ),
        stepArgs('$_parent/clear-critique'),
      );
      expect(outcome, isA<Ok>());
      expect(
        Directory(p.join(ws.path, '.grid', 'critique')).listSync(),
        isEmpty,
      );
    });
  });

  group('the critic result payload carries its round (the route\'s '
      '"finished-this-round" evidence)', () {
    test('an accepted verdict file yields a payload stamped with the ledger '
        'round it was verified against', () async {
      File(p.join(ws.path, '.grid', 'critique', 'spec-adherence.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'rubric': 'spec-adherence',
            'version': 1,
            'grade': 'A',
            'rationale': 'clean',
            'nodePath': 'tg-60t/review/spec-adherence',
            'round': 2,
          }),
        );
      final out = await const CriticCapability().result(
        FakeTreeContext(
          values: {
            Workspace: testWorkspace(
              'tg-60t',
              workspaceDir: ws.path,
              branch: 'grid/tg-60t',
            ),
          },
        ),
        stepArgs(
          'tg-60t/review/spec-adherence',
          params: const {'rubric': 'spec-adherence', 'grid.round': '2'},
        ),
      );
      expect(out!['grade'], 'A');
      expect(out['transport'], 'file');
      expect(out['round'], '2');
    });

    test(
      'a fail-closed default carries the round too — the route must be '
      'able to tell a THIS-round transport miss from a not-yet-run lane',
      () async {
        final out = await const CriticCapability().result(
          FakeTreeContext(
            values: {
              Workspace: testWorkspace(
                'tg-60t',
                workspaceDir: ws.path,
                branch: 'grid/tg-60t',
              ),
            },
          ),
          stepArgs(
            'tg-60t/review/spec-adherence',
            params: const {'rubric': 'spec-adherence', 'grid.round': '0'},
          ),
        );
        expect(out!['grade'], 'F');
        expect(out['transport'], 'fail-closed-default');
        expect(out['round'], '0');
      },
    );
  });
}
