// The DISCOVERY circuit — the pure cite-the-offence matrix + the three capability
// seams + the READ-ONLY fence.
//
// Offline only: no live claude/git/bd/network. The lens-report reader is a Fake
// (Fakes, not mocks); the synthetic workspace dir never exists on disk.
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/asset_fakes.dart';

const String _adr = 'docs/adr/ADR-0000-ai-decision-register.md A17(4)';

DiscoveryFinding _cited({
  ViolationKind kind = ViolationKind.decision,
  String standard = _adr,
  bool contradicts = true,
  String contradiction =
      'this bead adds a deterministic quality bar on human prose',
  bool acknowledged = false,
  bool ratified = true,
  bool removesOffence = false,
  String precedent = '',
}) => DiscoveryFinding(
  kind: kind,
  standard: standard,
  quote: 'determinism is confined to the tier where a hold is NEVER wrong',
  contradiction: contradiction,
  contradicts: contradicts,
  acknowledged: acknowledged,
  ratified: ratified,
  removesOffence: removesOffence,
  precedent: precedent,
);

LensReport _report({
  String lens = kDecisionLens,
  List<DiscoveryFinding> violations = const [],
  List<ContextNote> context = const [],
}) => LensReport(lens: lens, violations: violations, context: context);

DiscoveryVerdict _decide(
  Map<String, LensReport?> lanes, {
  int priorRound = 0,
}) => decideDiscovery(
  lanes: lanes,
  anchors: const DiscoveryAnchors(),
  workBead: workBead('tg-1'),
  priorRound: priorRound,
);

/// A Fake [LensReportReader] over canned reports (Fakes, not mocks).
LensReportReader _reader(Map<String, LensReport?> canned) =>
    (_, lens, __) => canned[lens];

Future<RouteVerdict> _runRoute(Map<String, LensReport?> canned) =>
    DiscoveryRouteCapability(reader: _reader(canned)).route(
      FakeTreeContext(
        values: {
          Bead: workBead('tg-1'),
          Workspace: testWorkspace('tg-1', workspaceDir: '/w/tg-1'),
          SiblingView: const SiblingView(),
        },
      ),
      stepArgs(
        'tg-1/spec_review/discovery/$kDiscoveryRouteStep',
        params: {'lenses': kDiscoveryLenses.join(',')},
      ),
    );

/// The same route, over a workspace dir that EXISTS on disk — the live posture,
/// where the round ledger and the dossier actually land.
Future<RouteVerdict> _runRouteAt(
  Map<String, LensReport?> canned, {
  required String workspaceDir,
}) => DiscoveryRouteCapability(reader: _reader(canned)).route(
  FakeTreeContext(
    values: {
      Bead: workBead('tg-1'),
      Workspace: testWorkspace('tg-1', workspaceDir: workspaceDir),
      SiblingView: const SiblingView(),
    },
  ),
  stepArgs(
    'tg-1/spec_review/discovery/$kDiscoveryRouteStep',
    params: {'lenses': kDiscoveryLenses.join(',')},
  ),
);

void main() {
  group('the CITE-THE-OFFENCE gate (a vibe can never hold a bead)', () {
    test('a CITED, unacknowledged contradiction of a decision HOLDS', () {
      final verdict = _decide({
        kDecisionLens: _report(violations: [_cited()]),
      });
      expect(verdict, isA<DiscoveryHold>());
      final hold = verdict as DiscoveryHold;
      expect(hold.offenses, hasLength(1));
      expect(hold.reason, contains(_adr));
      expect(hold.reason, contains('DECLARE the departure'));
    });

    test('a finding that asserts NO contradiction cannot gate — even cited + '
        'ratified (pow-hf2: the "None identified" false-hold)', () {
      // The flaky lens named a ratified standard and wrote a NON-empty
      // "no conflict" explanation into `contradiction`, but did not assert
      // `contradicts`. It must NEVER hold the bead (fails open).
      expect(
        gatesTheBead(
          _cited(
            contradicts: false,
            contradiction:
                'None identified. The bead correctly references the ADR and '
                'is aligned with its design.',
          ),
        ),
        isFalse,
      );
      // The positive control: the SAME citation WITH an asserted
      // contradiction still holds.
      expect(gatesTheBead(_cited(contradicts: true)), isTrue);
    });

    test('a violation with NO citation cannot gate — it is a FLAG', () {
      final verdict = _decide({
        kDecisionLens: _report(violations: [_cited(standard: '')]),
      });
      expect(verdict, isA<DiscoveryAdvance>());
      expect((verdict as DiscoveryAdvance).dossier.flags, hasLength(1));
      expect(gatesTheBead(_cited(standard: '')), isFalse);
    });

    test(
      'THE DEPARTURE CLAUSE: the SAME cited finding, acknowledged, ADVANCES and '
      'rides the dossier as a declared departure',
      () {
        final verdict = _decide({
          kDecisionLens: _report(violations: [_cited(acknowledged: true)]),
        });
        expect(verdict, isA<DiscoveryAdvance>());
        final dossier = (verdict as DiscoveryAdvance).dossier;
        expect(dossier.departures, hasLength(1));
        expect(dossier.flags, isEmpty);
        expect(
          renderDiscoveryDossier(dossier),
          contains('Declared departures'),
        );
      },
    );

    test(
      'a SKILL is a citable standard (skills teach how; ADRs ratify the specific)',
      () {
        final verdict = _decide({
          kDecisionLens: _report(
            violations: [
              _cited(
                kind: ViolationKind.skill,
                standard: 'skills/predictable_flutter',
              ),
            ],
          ),
        });
        expect(verdict, isA<DiscoveryHold>());
      },
    );

    test(
      'a PATTERN deviation with NO named precedent is a FLAG, not a hold; with '
      'one, it HOLDS',
      () {
        final unnamed = _decide({
          kCodeLens: _report(
            lens: kCodeLens,
            violations: [
              _cited(kind: ViolationKind.pattern, standard: 'the D-H doctrine'),
            ],
          ),
        });
        expect(unnamed, isA<DiscoveryAdvance>());
        expect((unnamed as DiscoveryAdvance).dossier.flags, hasLength(1));

        final named = _decide({
          kCodeLens: _report(
            lens: kCodeLens,
            violations: [
              _cited(
                kind: ViolationKind.pattern,
                standard: 'the D-H doctrine',
                precedent: 'lib/src/code/committee.dart:CriticCapability',
              ),
            ],
          ),
        });
        expect(named, isA<DiscoveryHold>());
      },
    );

    test(
      'A RECORDED ENTRY HOLDS: a cited contradiction of something that is NOT a '
      'recorded decision entry does NOT hold — it rides as a FLAG (the CLASS-2 '
      'false-positive fix)',
      () {
        final verdict = _decide({
          kDecisionLens: _report(violations: [_cited(ratified: false)]),
        });
        expect(verdict, isA<DiscoveryAdvance>());
        expect((verdict as DiscoveryAdvance).dossier.flags, hasLength(1));
        expect(gatesTheBead(_cited(ratified: false)), isFalse);
        expect(gatesTheBead(_cited(ratified: true)), isTrue);
      },
    );

    test(
      'INTENT, NOT PRESENCE: a fix-the-violation finding (the bead REMOVES the '
      'cited offence) does NOT hold, even on a RATIFIED standard (CLASS-1)',
      () {
        final verdict = _decide({
          kDecisionLens: _report(
            violations: [_cited(ratified: true, removesOffence: true)],
          ),
        });
        expect(verdict, isA<DiscoveryAdvance>());
        expect(gatesTheBead(_cited(removesOffence: true)), isFalse);
      },
    );

    test(
      'a PERPETUATE finding (ratified, not fixed, not acknowledged) HOLDS',
      () {
        final verdict = _decide({
          kDecisionLens: _report(
            violations: [_cited(ratified: true, removesOffence: false)],
          ),
        });
        expect(verdict, isA<DiscoveryHold>());
      },
    );

    test('the two new gate fields round-trip through the wire', () {
      final back = DiscoveryFinding.fromJson(
        _cited(ratified: true, removesOffence: true).toJson(),
      )!;
      expect(back.ratified, isTrue);
      expect(back.removesOffence, isTrue);
      final bare = DiscoveryFinding.fromJson({
        'kind': 'decision',
        'standard': _adr,
        'contradiction': 'x',
      })!;
      expect(bare.ratified, isFalse, reason: 'fail-open on holds');
      expect(bare.removesOffence, isFalse);
    });
  });

  group('the route (a broken LANE is never a verdict)', () {
    test(
      'a MISSING report STAMPS an invalidating grade:F (verdict regather) — NOT '
      'a Rewind; the engine derives the wave off the validates edge',
      () async {
        final outcome = await _runRoute({
          kCodeLens: _report(lens: kCodeLens),
          kDecisionLens: null,
          kPriorArtLens: _report(lens: kPriorArtLens),
        });
        expect(outcome, isA<Advance>());
        final payload = (outcome as Advance).payload!;
        expect(payload['grade'], 'F');
        expect(payload['verdict'], 'regather');
        expect(payload['lenses'], kDecisionLens);
        expect(payload['round'], '1');
      },
    );

    test(
      'at the cap, a still-missing lens ADVANCES with the miss recorded LOUDLY '
      '— the gate NEVER fires on absence',
      () {
        final verdict = _decide({
          kCodeLens: _report(lens: kCodeLens),
          kDecisionLens: null,
        }, priorRound: kMaxRegatherRounds);
        expect(verdict, isA<DiscoveryAdvance>());
        final dossier = (verdict as DiscoveryAdvance).dossier;
        expect(dossier.missingLenses, [kDecisionLens]);
        expect(renderDiscoveryDossier(dossier), contains('did NOT report'));
      },
    );

    test(
      'a clean sweep ADVANCES, and the route names what it decided over',
      () async {
        final outcome = await _runRoute({
          for (final lens in kDiscoveryLenses)
            lens: _report(
              lens: lens,
              context: [
                const ContextNote(note: 'the pack is a genesis_tree consumer'),
              ],
            ),
        });
        expect(outcome, isA<Advance>());
        final payload = (outcome as Advance).payload!;
        expect(payload['verdict'], 'advance');
        expect(payload['rule'], 'no-cited-offence');
        expect(payload['lenses'], kDiscoveryLenses.join(','));
        expect(payload['context'], '3');
      },
    );

    test('a CITED offence GATES — and the gate cites it', () async {
      final outcome = await _runRoute({
        for (final lens in kDiscoveryLenses)
          lens: _report(
            lens: lens,
            violations: lens == kDecisionLens ? [_cited()] : const [],
          ),
      });
      expect(outcome, isA<Escalate>());
      expect((outcome as Escalate).reason, contains(_adr));
      expect((outcome).reason, contains('DISCOVERY HOLD'));
    });
  });

  group('the deterministic gather (ZERO agents)', () {
    test(
      'bead-field citation wire shape is strict and prior art preserves search '
      'provenance',
      () {
        const citation = BeadFieldCitation(
          beadId: 'tg-b',
          field: BeadCitationField.notes,
          excerpt: 'Approved with Nico',
        );
        final citationBack = BeadFieldCitation.fromJson(citation.toJson())!;
        expect(citationBack.beadId, 'tg-b');
        expect(citationBack.field, BeadCitationField.notes);
        expect(citationBack.excerpt, 'Approved with Nico');
        expect(
          BeadFieldCitation.fromJson({
            'beadId': 'tg-b',
            'field': 'notes',
            'excerpt': '',
          }),
          isNull,
        );
        expect(
          BeadFieldCitation.fromJson({
            'beadId': 'tg-b',
            'field': 'priority',
            'excerpt': 'urgent',
          }),
          isNull,
        );

        const note = ContextNote(
          note: 'the sibling was approved',
          beadCitation: citation,
        );
        final noteBack = ContextNote.fromJson(note.toJson())!;
        expect(noteBack.beadCitation!.beadId, 'tg-b');
        expect(noteBack.beadCitation!.field, BeadCitationField.notes);
        expect(noteBack.beadCitation!.excerpt, 'Approved with Nico');

        const hit = PriorArt(
          beadId: 'tg-b',
          store: 'the_grid',
          status: 'open',
          title: 'rename the command',
          field: 'notes',
          snippet: 'Approved with Nico',
          query: 'command rename',
        );
        final hitBack = PriorArt.fromJson(hit.toJson())!;
        expect(hitBack.field, 'notes');
        expect(hitBack.snippet, 'Approved with Nico');
        expect(
          PriorArt.fromJson({...hit.toJson(), 'field': 'priority'}),
          isNull,
        );
        expect(PriorArt.fromJson({...hit.toJson(), 'snippet': ''}), isNull);
      },
    );

    test(
      'dossier assembly verifies bead fields and marks sibling citations FOREIGN',
      () {
        final work = workBead('tg-a').copyWith(
          description: 'Build the circuit step.',
          notes: 'Circuit work only.',
        );
        const hit = PriorArt(
          beadId: 'tg-b',
          store: 'the_grid',
          status: 'open',
          title: 'rename the command',
          field: 'notes',
          snippet: 'Approved with Nico',
          query: 'command rename',
        );
        final notes = verifiedContextNotes(
          workBead: work,
          priorArt: const [hit],
          notes: const [
            ContextNote(
              note: 'the work builds a circuit step',
              beadCitation: BeadFieldCitation(
                beadId: 'tg-a',
                field: BeadCitationField.description,
                excerpt: 'circuit step',
              ),
            ),
            ContextNote(
              note: 'the work was approved',
              beadCitation: BeadFieldCitation(
                beadId: 'tg-a',
                field: BeadCitationField.notes,
                excerpt: 'Approved with Nico',
              ),
            ),
            ContextNote(
              note: 'legacy fabricated attribution',
              source: 'tg-a notes',
            ),
            ContextNote(
              note: 'the sibling was approved',
              beadCitation: BeadFieldCitation(
                beadId: 'tg-b',
                field: BeadCitationField.notes,
                excerpt: 'Approved with Nico',
              ),
            ),
            ContextNote(
              note: 'wrong sibling field',
              beadCitation: BeadFieldCitation(
                beadId: 'tg-b',
                field: BeadCitationField.description,
                excerpt: 'Approved with Nico',
              ),
            ),
          ],
        );
        expect(notes, hasLength(2));
        final dossier = DiscoveryDossier(
          anchors: const DiscoveryAnchors(priorArt: [hit]),
          workBeadId: 'tg-a',
          context: notes,
        );
        final rendered = renderDiscoveryDossier(dossier);
        expect(rendered, contains('SELF tg-a.description'));
        expect(rendered, contains('FOREIGN tg-b.notes'));
        expect(rendered, isNot(contains('SELF tg-a.notes')));
      },
    );

    test('the bead PATH + SYMBOL anchors are extracted, deduped and bounded', () {
      final b = bead('tg-1').copyWith(
        description:
            'Touch `lib/src/code/specify.dart` and `lib/src/code/specify.dart` '
            'again; call `buildSpecifyBrief` and `Heartbeat`; run `bd` in '
            '`main`.',
      );
      final anchors = beadAnchors(b);
      expect(anchors.paths, ['lib/src/code/specify.dart']);
      expect(anchors.symbols, ['buildSpecifyBrief', 'Heartbeat']);
    });

    test('the gather pulls the committee RUBRICS, resolves the anchors and runs '
        'the prior-art search through its seams', () async {
      final queried = <String>[];
      final outcome =
          await AnchorsCapability(
            rubricIds: kSpecCommitteeRubrics,
            rubrics: (id) => '($id bands)',
            resolver: (_, anchor) => ResolvedAnchor(
              anchor: anchor,
              resolved: true,
              neighbors: const ['lib/src/code/committee.dart'],
            ),
            priorArt: (queries) async {
              queried.addAll(queries);
              return [
                const PriorArt(
                  beadId: 'pow-q7n',
                  store: 'power_station',
                  status: 'closed',
                  title: 'the readiness ladder',
                  field: 'description',
                  snippet: 'buildSpecifyBrief',
                  query: 'buildSpecifyBrief',
                ),
              ];
            },
            clearer: (_) {},
          ).run(
            FakeTreeContext(
              values: {
                Bead: bead('tg-1').copyWith(
                  description:
                      'Extend `buildSpecifyBrief` in `lib/src/code/specify.dart`.',
                ),
                Workspace: testWorkspace('tg-1', workspaceDir: '/w/tg-1'),
              },
            ),
            stepArgs('tg-1/spec_review/discovery/$kAnchorsStep'),
          );
      expect(outcome, isA<Ok>());
      final payload = (outcome as Ok).payload!;
      expect(payload['rubrics'], '${kSpecCommitteeRubrics.length}');
      expect(payload['anchors'], '1');
      expect(payload['priorArt'], '1');
      expect(
        queried,
        ['buildSpecifyBrief'],
        reason: 'a SYMBOL is the high-signal prior-art query, not the title',
      );
    });

    test(
      'an UNWIRED prior-art source is reported LOUDLY, never as "no hits"',
      () {
        const dossier = DiscoveryDossier(anchors: DiscoveryAnchors());
        expect(renderDiscoveryDossier(dossier), contains('NOT WIRED'));
        expect(renderDiscoveryDossier(dossier), contains('nobody looked'));
      },
    );
  });

  group('the lenses are READ-ONLY (A37) and CHEAP (the `gather` role)', () {
    RuntimeConfig spawnLens(String lens) =>
        const DiscoveryLensCapability().spawn(
          FakeTreeContext(
            values: {
              Bead: workBead('tg-1'),
              Workspace: testWorkspace('tg-1', workspaceDir: '/w/tg-1'),
              AgentConfig: const AgentConfig(),
            },
          ),
          stepArgs('tg-1/spec_review/discovery/$lens', params: {'lens': lens}),
        );

    test(
      'a lens spawns on the CHEAP tier — --model haiku at the claude argv',
      () {
        final cfg = spawnLens(kCodeLens);
        final i = cfg.args.indexOf('--model');
        expect(i, greaterThanOrEqualTo(0), reason: 'the lens named NO --model');
        expect(cfg.args[i + 1], kCheapModelDefault);
        expect(tierFor(AgentRole.gather), AgentTier.cheap);
      },
    );

    test(
      'every lens rides the READ-ONLY working agreement — no bd mutation, no '
      'edit, no commit — and DECIDES nothing',
      () {
        for (final lens in kDiscoveryLenses) {
          final rendered = spawnLens(lens).args.join('\n');
          expect(rendered, contains('You are READ-ONLY'));
          expect(rendered, contains('no `bd update`'));
          expect(rendered, contains('You DECIDE nothing'));
          // No letter grade anywhere: a lens REPORTS, it does not grade.
          expect(rendered, isNot(contains('"grade"')));
        }
      },
    );

    test('the circuit has NO write path to the bead — the fence is STRUCTURAL, not '
        'a runtime check (A11(3): there is nothing to refuse)', () {
      final source = File(
        p.join(_libSrc(), 'code', 'discovery.dart'),
      ).readAsStringSync();
      // 1. It constructs NO process invocation of its own (unlike the gating
      //    critic's `sh -c`): every spawn is delegated to the resolved harness,
      //    which runs the read-only agent. So no bd/git argv can exist here.
      expect(
        source.contains('RuntimeConfig('),
        isFalse,
        reason:
            'the discovery circuit builds no invocation of its own — the '
            'harness owns the spawn',
      );
      // 2. It holds NO bd client, so no bd write path exists to refuse (A37 by
      //    construction — the A11(3) posture).
      for (final client in ['BdCliService', 'BdRunner']) {
        expect(source.contains(client), isFalse, reason: 'no bd client here');
      }
      // 3. It has exactly ONE writer (`_writeJson`), and every path handed to
      //    it (`anchorsPath` / `lensReportPath` / `discoveryDossierPath`, plus
      //    the round ledger that must OUTLIVE the gather-dir wipe) is one of
      //    this circuit's own derived paths under `.grid/`: its whole write
      //    surface is its own artifacts.
      expect(RegExp('writeAsStringSync').allMatches(source), hasLength(1));
    });

    test(
      'the lens prompt teaches that a decision entry binds and a bead is not a '
      'decision, plus INTENT-NOT-PRESENCE and both JSON fields',
      () {
        final prompt = const DiscoveryLensCapability().buildLensPrompt(
          bead: workBead('tg-1'),
          lens: kDecisionLens,
          nodePath: 'tg-1/spec_review/discovery/$kDecisionLens',
          workspaceDir: '/w/tg-1',
        );
        expect(prompt, contains('A DECISION ENTRY BINDS'));
        expect(prompt, contains('A BEAD IS NOT A DECISION'));
        expect(prompt, contains('INTENT, NOT PRESENCE'));
        expect(prompt, contains('"ratified":false'));
        expect(prompt, contains('"removesOffence":false'));
        expect(prompt, contains(localDecisionRegisterListCommand()));
        expect(
          prompt,
          contains(
            localDecisionRegisterGrepCommand(
              r'<keyword1>\|<keyword2>\|<keyword3>',
            ),
          ),
        );
        for (final directory in kLocalDecisionRegisterDirectories) {
          expect(prompt, contains(directory));
        }
        expect(prompt, contains('the_grid#admission-authority-boundary'));
        expect(prompt, isNot(contains('amendments BIND too')));
      },
    );
  });

  group('the route STAMPS the invalidating grade (no Rewind is emitted)', () {
    late Directory ws;
    setUp(() => ws = Directory.systemTemp.createTempSync('discovery-regather'));
    tearDown(() => ws.deleteSync(recursive: true));

    test(
      'the clean arm ADVANCES with NO grade key + writes the dossier',
      () async {
        final outcome = await _runRouteAt({
          for (final lens in kDiscoveryLenses) lens: _report(lens: lens),
        }, workspaceDir: ws.path);
        expect(outcome, isA<Advance>());
        final payload = (outcome as Advance).payload!;
        expect(payload['verdict'], 'advance');
        expect(
          payload.containsKey('grade'),
          isFalse,
          reason: 'a PASSING round must invalidate nothing',
        );
        expect(File(discoveryDossierPath(ws.path)).existsSync(), isTrue);
      },
    );

    test('the hold arm ESCALATES — a human park, never a stamp', () async {
      final outcome = await _runRouteAt({
        for (final lens in kDiscoveryLenses)
          lens: _report(
            lens: lens,
            violations: lens == kDecisionLens ? [_cited()] : const [],
          ),
      }, workspaceDir: ws.path);
      expect(outcome, isA<Escalate>());
      expect(outcome, isNot(isA<Advance>()));
    });

    test(
      'the round counter is the REGATHER LEDGER own round — bounded at '
      'kMaxRegatherRounds, then ADVANCES with the miss noted and clears it',
      () async {
        final canned = <String, LensReport?>{
          kCodeLens: _report(lens: kCodeLens),
          kDecisionLens: null,
          kPriorArtLens: _report(lens: kPriorArtLens),
        };
        final r1 = await _runRouteAt(canned, workspaceDir: ws.path);
        expect((r1 as Advance).payload!['grade'], 'F');
        expect(readDiscoveryRegatherLedger(ws.path)!.round, 1);

        final r2 = await _runRouteAt(canned, workspaceDir: ws.path);
        expect(r2, isA<Advance>());
        expect((r2 as Advance).payload!.containsKey('grade'), isFalse);
        expect(r2.payload!['missing'], kDecisionLens);
        expect(readDiscoveryRegatherLedger(ws.path), isNull);
        expect(kMaxRegatherRounds, lessThan(kMaxReworkRounds));
      },
    );

    test('kDiscoveryCircuit route step declares validates:anchors — a dangling '
        'target silently disarms the loop (one-definition discipline)', () {
      expect(
        (kDiscoveryCircuit.stepById(kDiscoveryRouteStep)! as CapabilityStep)
            .params[kValidatesParamKey],
        kAnchorsStep,
      );
      expect(kValidatesParamKey, 'validates');
      expect(
        kDiscoveryCircuit.steps.map((s) => s.stepId),
        contains(kAnchorsStep),
      );
    });

    test(
      'the regather ledger OUTLIVES the anchors wipe (sibling of the dir)',
      () {
        expect(
          p.isWithin(discoveryDirPath('/w'), discoveryRegatherLedgerPath('/w')),
          isFalse,
          reason:
              'AnchorsCapability WIPES the gather dir at the head of every '
              'round — a counter kept inside it restarts the bound at 0 forever',
        );
      },
    );
  });
}

/// This package's `lib/src` dir (the structural fence's walk).
String _libSrc() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    for (final rel in ['lib', p.join('packages', 'grid_assets', 'lib')]) {
      final probe = Directory(p.join(dir.path, rel));
      if (File(p.join(probe.path, 'grid_assets.dart')).existsSync()) {
        return p.join(probe.path, 'src');
      }
    }
    dir = dir.parent;
  }
  fail('could not locate packages/grid_assets/lib');
}
