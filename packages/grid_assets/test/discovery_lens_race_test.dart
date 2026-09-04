// The discovery-circuit twin of `committee_verdict_race_test.dart`. Discovery
// declares `validates: anchors`, so it carries the SAME engine-derived
// mixed-generation exposure the committee race exposed: the wave re-keys the
// gather closure node by node, so a re-keyed LENS can write THIS round's report
// before the re-keyed `anchors` sweep runs, and a lens the wave has not reached
// yet still holds LAST generation's report on disk.
//
// What this file pins:
//   1. a PRIOR generation's report never joins as current — the fence is both
//      stamps, and it rules the envelope fallback too;
//   2. the route never decides over a lane that is merely LATE: it WAITS, and
//      the report that lands mid-wait joins (no regather round spent);
//   3. a lane that FINISHED this round artifact-less is LOUD and IMMEDIATE —
//      named on the payload, never silently dropped;
//   4. the anchors SWEEP is round-aware: it keeps THIS round's reports and
//      deletes prior/foreign/unstamped/non-report files;
//   5. every lens result payload carries the round it was recorded against.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

const _parent = 'tg-1/spec_review/discovery';

/// Plants one lens report at the canonical path, stamped for [nodePath]
/// (default: THIS circuit's sibling lens node) and [round].
void _plantReport(
  String ws,
  String lens, {
  required int round,
  String? nodePath,
  String note = 'the lens angle',
}) {
  File(lensReportPath(ws, lens))
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode({
        'lens': lens,
        'version': 1,
        'nodePath': nodePath ?? '$_parent/$lens',
        kVerdictRoundKey: round,
        'context': [
          {'note': note, 'source': 'CLAUDE.md'},
        ],
        'violations': <Object?>[],
      }),
    );
}

/// The route over a LIVE workspace, with the lanes' recorded results as the
/// engine's [SiblingView] holds them (`{lens: round}`) — the wait/loud
/// evidence.
Future<RouteVerdict> _route(
  String ws, {
  Map<String, int> recorded = const {},
  Duration lanePoll = const Duration(milliseconds: 10),
  Duration laneWaitBudget = const Duration(seconds: 10),
  int round = 1,
}) =>
    DiscoveryRouteCapability(
      lanePoll: lanePoll,
      laneWaitBudget: laneWaitBudget,
    ).route(
      FakeTreeContext(
        values: {
          Bead: workBead('tg-1'),
          Workspace: testWorkspace('tg-1', workspaceDir: ws),
          SiblingView: SiblingView(
            results: {
              for (final entry in recorded.entries)
                '$_parent/${entry.key}': {kVerdictRoundKey: '${entry.value}'},
            },
          ),
        },
      ),
      stepArgs(
        '$_parent/$kDiscoveryRouteStep',
        params: {'lenses': kDiscoveryLenses.join(','), 'grid.round': '$round'},
      ),
    );

void main() {
  late Directory ws;
  setUp(() {
    ws = Directory.systemTemp.createTempSync('discovery-race-');
    // The route projects every lane off the canonical gather before it joins,
    // so the live posture needs the real round-1 artifact on disk.
    plantGather(ws.path, completeGather(bead: workBead('tg-1'), round: 1));
  });
  tearDown(() => ws.deleteSync(recursive: true));

  group('the lens-report freshness fence (the stamp discovery never had)', () {
    test('a PRIOR generation report is refused; THIS round\'s joins', () {
      _plantReport(ws.path, kCodeLens, round: 0);
      expect(
        readLensReport(ws.path, kCodeLens, '$_parent/$kCodeLens', round: 1),
        isNull,
        reason: 'round 0 is a prior generation — it must never join as current',
      );
      _plantReport(ws.path, kCodeLens, round: 1);
      expect(
        readLensReport(
          ws.path,
          kCodeLens,
          '$_parent/$kCodeLens',
          round: 1,
        )?.lens,
        kCodeLens,
      );
    });

    test('a FOREIGN node\'s report and an UNSTAMPED one are both refused', () {
      _plantReport(
        ws.path,
        kDecisionLens,
        round: 1,
        nodePath: 'OTHER-bead/spec_review/discovery/$kDecisionLens',
      );
      expect(
        readLensReport(
          ws.path,
          kDecisionLens,
          '$_parent/$kDecisionLens',
          round: 1,
        ),
        isNull,
      );
      File(lensReportPath(ws.path, kDecisionLens)).writeAsStringSync(
        jsonEncode({
          'lens': kDecisionLens,
          'version': 1,
          'nodePath': '$_parent/$kDecisionLens',
          'context': <Object?>[],
          'violations': <Object?>[],
        }),
      );
      expect(
        readLensReport(
          ws.path,
          kDecisionLens,
          '$_parent/$kDecisionLens',
          round: 1,
        ),
        isNull,
        reason: 'an absent round stamp is a MISS, exactly as a foreign one is',
      );
    });
  });

  group('the route join under the mixed-generation wave', () {
    test('a LATE lane is WAITED for, not decided over: the report that lands '
        'mid-wait joins and NO regather round is spent', () async {
      _plantReport(ws.path, kCodeLens, round: 1);
      _plantReport(ws.path, kPriorArtLens, round: 1);
      // The third lane still holds LAST generation's file and has recorded
      // nothing this round — the wave has not re-run it yet.
      _plantReport(ws.path, kDecisionLens, round: 0);
      Timer(
        const Duration(milliseconds: 120),
        () => _plantReport(ws.path, kDecisionLens, round: 1),
      );
      final out = await _route(
        ws.path,
        recorded: {kCodeLens: 1, kPriorArtLens: 1},
      );
      expect(out, isA<Advance>());
      final payload = (out as Advance).payload!;
      expect(payload['verdict'], 'advance');
      expect(
        payload.containsKey('grade'),
        isFalse,
        reason: 'a waited-for lane is not a regather — nothing is invalidated',
      );
      expect(payload['missing'], isEmpty);
      expect(readDiscoveryRegatherLedger(ws.path), isNull);
    });

    test('a lane that FINISHED this round artifact-less is LOUD and IMMEDIATE '
        '— named on the payload, never waited out and never dropped', () async {
      _plantReport(ws.path, kCodeLens, round: 1);
      _plantReport(ws.path, kPriorArtLens, round: 1);
      final watch = Stopwatch()..start();
      final out = await _route(
        ws.path,
        recorded: {kCodeLens: 1, kPriorArtLens: 1, kDecisionLens: 1},
        laneWaitBudget: const Duration(seconds: 30),
      );
      watch.stop();
      expect(
        watch.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason: 'a finished-this-round lane is LOUD now, never waited out',
      );
      final payload = (out as Advance).payload!;
      expect(payload['grade'], 'F');
      expect(payload['verdict'], 'regather');
      expect(payload['lenses'], kDecisionLens);
      expect(readDiscoveryRegatherLedger(ws.path)!.round, 1);
    });

    test('at the regather cap the miss ADVANCES, recorded LOUDLY — absence '
        'never holds the bead (A21(3))', () async {
      writeDiscoveryRegatherLedger(
        ws.path,
        const DiscoveryRegatherLedger(round: kMaxRegatherRounds),
      );
      _plantReport(ws.path, kCodeLens, round: 1);
      _plantReport(ws.path, kPriorArtLens, round: 1);
      final out = await _route(
        ws.path,
        recorded: {kCodeLens: 1, kPriorArtLens: 1, kDecisionLens: 1},
      );
      final payload = (out as Advance).payload!;
      expect(payload['verdict'], 'advance');
      expect(payload['missing'], kDecisionLens);
      expect(
        renderDiscoveryDossier(readDiscoveryDossier(ws.path)!),
        contains(kDecisionLens),
      );
    });
  });

  group('the round-aware anchors sweep (the wipe between lanes)', () {
    test(
      'a sweep landing AFTER a same-round lens already wrote KEEPS that '
      'report and deletes only stale/foreign/unstamped/non-report files',
      () async {
        _plantReport(ws.path, kCodeLens, round: 1); // this round's, already in.
        _plantReport(ws.path, kPriorArtLens, round: 0); // a prior generation's.
        _plantReport(
          ws.path,
          kDecisionLens,
          round: 1,
          nodePath: 'OTHER-bead/spec_review/discovery/$kDecisionLens',
        );
        File(
          p.join(discoveryDirPath(ws.path), 'dossier.json'),
        ).writeAsStringSync('{ not json');
        final outcome = await const AnchorsCapability().run(
          FakeTreeContext(
            values: {
              Bead: workBead('tg-1'),
              Workspace: testWorkspace('tg-1', workspaceDir: ws.path),
            },
          ),
          stepArgs('$_parent/$kAnchorsStep', params: const {'grid.round': '1'}),
        );
        expect(outcome, isA<Ok>());
        expect(
          Directory(
            discoveryDirPath(ws.path),
          ).listSync().map((e) => p.basename(e.path)).toList()..sort(),
          ['anchors.json', '$kCodeLens.json'],
          reason: 'this round\'s report survives; everything else is swept',
        );
      },
    );
  });

  group('the lens result payload carries its round', () {
    test(
      'a lens stamps the round it was recorded against, report or not',
      () async {
        final args = stepArgs(
          '$_parent/$kCodeLens',
          params: const {'lens': kCodeLens, 'grid.round': '2'},
        );
        final context = FakeTreeContext(
          values: {Workspace: testWorkspace('tg-1', workspaceDir: ws.path)},
        );
        final empty = await const DiscoveryLensCapability().result(
          context,
          args,
        );
        expect(empty![kVerdictRoundKey], '2');
        expect(empty.containsKey('lens'), isFalse);
        _plantReport(ws.path, kCodeLens, round: 2);
        final full = await const DiscoveryLensCapability().result(
          context,
          args,
        );
        expect(full![kVerdictRoundKey], '2');
        expect(full['lens'], kCodeLens);
        expect(full['transport'], 'file');
      },
    );
  });
  group('insufficient evidence regathers once then holds', () {
    /// Replaces the planted gather with one whose PRIOR-ART coverage carries
    /// [state] — the hole only the prior-art lane is handed.
    void plantHoledGather(EvidenceState state) {
      final complete = completeGather(bead: workBead('tg-1'), round: 1);
      plantGather(
        ws.path,
        DiscoveryAnchors(
          round: complete.round,
          workBeadId: complete.workBeadId,
          beadFields: complete.beadFields,
          priorArtQueries: [
            PriorArtQueryEvidence(
              id: 'prior-art-query:the-symbol@sha256:fake',
              query: 'the-symbol',
              state: state,
              error: 'the roster seat never answered',
            ),
          ],
          history: complete.history,
        ),
      );
    }

    for (final state in [
      EvidenceState.truncated,
      EvidenceState.unavailable,
      EvidenceState.failed,
    ]) {
      test('a ${state.name} record regathers at round 0 and ESCALATES at the '
          'cap', () async {
        plantHoledGather(state);
        for (final lens in kDiscoveryLenses) {
          _plantReport(ws.path, lens, round: 1);
        }
        final recorded = {for (final lens in kDiscoveryLenses) lens: 1};

        // Round 0: a deterministic hole is a BROKEN LANE — regather once.
        final first = await _route(ws.path, recorded: recorded);
        expect(first, isA<Advance>());
        final payload = (first as Advance).payload!;
        expect(payload['grade'], 'F');
        expect(payload['verdict'], 'regather');
        expect(payload['lenses'], kPriorArtLens);
        expect(readDiscoveryRegatherLedger(ws.path)!.round, 1);

        // Round 1 (the cap): the hole is still there and STATED — HOLD.
        final second = await _route(ws.path, recorded: recorded);
        expect(second, isA<Escalate>());
        final reason = (second as Escalate).reason;
        expect(reason, contains('DISCOVERY EVIDENCE HOLD'));
        expect(reason, contains(kPriorArtLens));
        expect(reason, contains('prior-art-query:the-symbol@sha256:fake'));
        expect(reason, contains('the roster seat never answered'));
        expect(
          reason,
          isNot(contains('DISCOVERY HOLD —')),
          reason: 'a known non-answer is NOT a cited offence',
        );
      });
    }

    test('the negative control: a merely ABSENT lens at the SAME cap still '
        'ADVANCES with the miss recorded (A21(3))', () async {
      writeDiscoveryRegatherLedger(
        ws.path,
        const DiscoveryRegatherLedger(round: kMaxRegatherRounds),
      );
      _plantReport(ws.path, kCodeLens, round: 1);
      _plantReport(ws.path, kPriorArtLens, round: 1);
      final out = await _route(
        ws.path,
        recorded: {for (final lens in kDiscoveryLenses) lens: 1},
      );
      expect(out, isA<Advance>());
      final payload = (out as Advance).payload!;
      expect(payload['verdict'], 'advance');
      expect(payload['missing'], kDecisionLens);
    });

    test('a lens that WRITES the typed insufficient result is read as one, and '
        'a model report can never hide a deterministic hole', () async {
      // The typed outcome decodes off the canonical file, under the same
      // dual-stamp fence a report rides.
      File(lensReportPath(ws.path, kCodeLens))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'outcome': 'insufficient-evidence',
            'lens': kCodeLens,
            'version': 2,
            'nodePath': '$_parent/$kCodeLens',
            kVerdictRoundKey: 1,
            'gaps': [
              {'evidenceId': 'code-anchor:lib@sha256:x', 'reason': 'CLIPPED'},
            ],
          }),
        );
      final outcome = readLensReport(
        ws.path,
        kCodeLens,
        '$_parent/$kCodeLens',
        round: 1,
      );
      expect(outcome, isA<InsufficientEvidenceReport>());
      expect((outcome! as InsufficientEvidenceReport).gaps, hasLength(1));

      // An insufficient report with NO named gap is not a statement at all.
      expect(
        DiscoveryLensOutcome.fromJson({
          'outcome': 'insufficient-evidence',
          'lens': kCodeLens,
          'gaps': <Object?>[],
        }),
        isNull,
      );

      // And a CLEAN model report over a holed gather is overridden.
      plantGather(
        ws.path,
        DiscoveryAnchors(
          round: 1,
          workBeadId: 'tg-1',
          beadFields: boundedBeadFields(workBead('tg-1')),
          history: HistoryEvidence(
            id: 'history:none@sha256:fake',
            paths: const [],
            command: '',
            state: EvidenceState.failed,
            error: 'git would not launch',
          ),
        ),
      );
      for (final lens in kDiscoveryLenses) {
        _plantReport(ws.path, lens, round: 1);
      }
      final overridden = await _route(
        ws.path,
        recorded: {for (final lens in kDiscoveryLenses) lens: 1},
      );
      expect((overridden as Advance).payload!['lenses'], kPriorArtLens);
      expect(overridden.payload!['grade'], 'F');
    });

    test('a live worktree whose gather is UNREADABLE is explicit insufficiency '
        'for every lane, never a clean empty', () async {
      File(anchorsPath(ws.path)).writeAsStringSync('{ not json');
      for (final lens in kDiscoveryLenses) {
        _plantReport(ws.path, lens, round: 1);
      }
      final out = await _route(
        ws.path,
        recorded: {for (final lens in kDiscoveryLenses) lens: 1},
      );
      expect(
        (out as Advance).payload!['lenses']!.split(',').toSet(),
        kDiscoveryLenses.toSet(),
      );
    });
  });
}
