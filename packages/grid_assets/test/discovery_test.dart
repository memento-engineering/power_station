// The DISCOVERY circuit — the pure cite-the-offence matrix + the three capability
// seams + the READ-ONLY fence.
//
// Offline only: no live claude/git/bd/network. The lens-report reader is a Fake
// (Fakes, not mocks); the synthetic workspace dir never exists on disk.
import 'dart:convert';
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
  Map<String, DiscoveryLensOutcome?> lanes, {
  int priorRound = 0,
}) => decideDiscovery(
  lanes: lanes,
  anchors: const DiscoveryAnchors(),
  workBead: workBead('tg-1'),
  priorRound: priorRound,
);

/// A Fake [LensReportReader] over canned reports (Fakes, not mocks).
LensReportReader _reader(Map<String, DiscoveryLensOutcome?> canned) =>
    (_, lens, __, {required int round}) => canned[lens];

Future<RouteVerdict> _runRoute(Map<String, DiscoveryLensOutcome?> canned) =>
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
        params: {'lenses': kDiscoveryLenses.join(','), 'grid.round': '0'},
      ),
    );

/// The same route, over a workspace dir that EXISTS on disk — the live posture,
/// where the round ledger and the dossier actually land.
Future<RouteVerdict> _runRouteAt(
  Map<String, DiscoveryLensOutcome?> canned, {
  required String workspaceDir,
}) =>
    DiscoveryRouteCapability(
      reader: _reader(canned),
      // A canned-null lane has recorded no result either, so the live route
      // classifies it LATE and waits: millisecond tuning keeps the suite offline-fast.
      lanePoll: const Duration(milliseconds: 5),
      laneWaitBudget: const Duration(milliseconds: 50),
    ).route(
      FakeTreeContext(
        values: {
          Bead: workBead('tg-1'),
          Workspace: testWorkspace('tg-1', workspaceDir: workspaceDir),
          SiblingView: const SiblingView(),
        },
      ),
      stepArgs(
        'tg-1/spec_review/discovery/$kDiscoveryRouteStep',
        params: {'lenses': kDiscoveryLenses.join(','), 'grid.round': '0'},
      ),
    );

/// A COMPLETE canonical profile with every family populated — the fixture the
/// projection isolation proof reads. Its tokens are deliberately disjoint: the
/// code family names a path, the decision family an identity, the history
/// family a SHA, so a leak between lanes is visible as a substring.
DiscoveryAnchors _completeAnchors() => DiscoveryAnchors(
  round: 7,
  workBeadId: 'pow-x',
  beadFields: boundedBeadFields(
    bead('pow-x').copyWith(description: 'Extend the gather.'),
  ),
  rubrics: const {'coherence': 'the coherence bands'},
  rubricEvidence: rubricEvidenceOf(const {'coherence': 'the coherence bands'}),
  anchors: [
    ResolvedAnchor(
      anchor: 'lib/src/code/discovery.dart',
      resolved: true,
      contents: boundDiscoveryEvidence(
        kind: 'code-anchor',
        subject: 'lib/src/code/discovery.dart',
        source: '/w/lib/src/code/discovery.dart',
        fullText: 'class AnchorsCapability {}',
      ),
      neighbors: const ['lib/src/code/committee.dart'],
    ),
  ],
  symbols: const ['AnchorsCapability'],
  priorArtQueries: [
    PriorArtQueryEvidence(
      id: 'prior-art-query:AnchorsCapability@sha256:fake',
      query: 'AnchorsCapability',
      state: EvidenceState.complete,
      hits: [
        const PriorArt(
          beadId: 'pow-96y',
          store: 'power_station',
          status: 'closed',
          title: 'the discovery circuit',
          field: 'description',
          snippet: 'a nested read-only gather',
          query: 'AnchorsCapability',
          evidenceId: 'prior-art-hit:pow-96y@sha256:fake',
        ),
      ],
    ),
  ],
  decisionLookups: [
    DecisionSurfaceEvidence(
      id: 'decision-surface:power_station/lib@sha256:fake',
      surface: 'power_station/lib/src/code/discovery.dart',
      command: 'space decisions index --surface power_station/lib',
      state: EvidenceState.complete,
      decisions: [
        DecisionEntryEvidence(
          identity: 'power_station#a21',
          originRegister: 'power_station',
          originPath: 'docs/decisions',
          slug: 'a21',
          status: 'accepted',
          surfaces: const ['packages/**'],
          entryPath: 'docs/decisions/a21.md',
          body: boundDiscoveryEvidence(
            kind: 'decision-entry',
            subject: 'power_station#a21',
            source: 'docs/decisions/a21.md',
            fullText: 'a lens emits a REPORT, never a letter',
          ),
        ),
      ],
    ),
  ],
  history: HistoryEvidence(
    id: 'history:lib@sha256:fake',
    paths: const ['lib/src/code/discovery.dart'],
    command: 'git log --',
    state: EvidenceState.complete,
    commits: [
      const HistoryCommitEvidence(
        id: 'history-commit:abc123def@sha256:fake',
        sha: 'abc123def',
        authoredAt: '2026-09-01T00:00:00Z',
        subject: 'rework the gather',
      ),
    ],
  ),
);

DiscoveryEvidenceProjection _project(DiscoveryAnchors anchors, String lens) =>
    projectDiscoveryEvidence(
      anchors,
      lens: lens,
      round: 7,
      workBeadId: 'pow-x',
    );

String _promptFor(DiscoveryEvidenceProjection projection) =>
    const DiscoveryLensCapability().buildLensPrompt(
      lens: projection.lens,
      nodePath: 'pow-x/spec_review/discovery/${projection.lens}',
      round: projection.round,
      workspaceDir: '/w/pow-x',
      projection: projection,
    );

/// A [ShellRunner] answering one canned (exitCode, output) for every call, and
/// recording each (workingDirectory, command) — Fakes, not mocks.
class _CannedShellRunner implements ShellRunner {
  _CannedShellRunner({this.exitCode = 0, this.output = ''});

  final int exitCode;
  final String output;
  final List<({String workingDirectory, String command})> calls = [];

  /// The command text of every recorded call, in order.
  List<String> get commands => [for (final call in calls) call.command];

  @override
  Future<ShellRunResult> run({
    required String workingDirectory,
    required String command,
  }) async {
    calls.add((workingDirectory: workingDirectory, command: command));
    return ShellRunResult(exitCode: exitCode, output: output);
  }
}

/// A [GitRunner] answering one canned (exitCode, output) and recording argv.
class _CannedLogRunner implements GitRunner {
  _CannedLogRunner({this.exitCode = 0, this.output = ''});

  final int exitCode;
  final String output;
  final List<List<String>> calls = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add(List.unmodifiable(args));
    return GitRunResult(exitCode: exitCode, output: output);
  }
}

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
          evidenceId: 'prior-art-hit:tg-b@sha256:fake',
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
          evidenceId: 'prior-art-hit:tg-b@sha256:fake',
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
          anchors: const DiscoveryAnchors(
            priorArtQueries: [
              PriorArtQueryEvidence(
                id: 'prior-art-query:command rename@sha256:fake',
                query: 'command rename',
                state: EvidenceState.complete,
                hits: [hit],
              ),
            ],
          ),
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
            resolver: (_, paths) => [
              for (final anchor in paths)
                ResolvedAnchor(
                  anchor: anchor,
                  resolved: true,
                  contents: boundDiscoveryEvidence(
                    kind: 'code-anchor',
                    subject: anchor,
                    source: anchor,
                    fullText: 'class Fake {}',
                  ),
                  neighbors: const ['lib/src/code/committee.dart'],
                ),
            ],
            priorArt: (queries) async {
              queried.addAll(queries);
              return [
                for (final query in queries)
                  PriorArtQueryEvidence(
                    id: 'prior-art-query:$query@sha256:fake',
                    query: query,
                    state: EvidenceState.complete,
                    hits: [
                      PriorArt(
                        beadId: 'pow-q7n',
                        store: 'power_station',
                        status: 'closed',
                        title: 'the readiness ladder',
                        field: 'description',
                        snippet: 'buildSpecifyBrief',
                        query: query,
                        evidenceId: 'prior-art-hit:pow-q7n@sha256:fake',
                      ),
                    ],
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

    test('ambient SubstationConfig qualifies decision surfaces without bead '
        'rig', () async {
      final shell = _CannedShellRunner(
        output: jsonEncode({'spec': 1, 'decisions': <Object?>[]}),
      );
      final gathered = <DecisionSurfaceEvidence>[];
      final source = commandDecisionIndexSource(
        shell,
        runnerInvocation: 'dart run lunar:lunar',
        gridHome: '/grid/lunar',
      );
      final outcome =
          await AnchorsCapability(
            decisions: (workspaceDir, surfaces) async {
              final records = await source(workspaceDir, surfaces);
              gathered.addAll(records);
              return records;
            },
            clearer: (_) {},
          ).run(
            FakeTreeContext(
              values: {
                // A WORK bead — `rig` is a SESSION-bead field, so it has none.
                Bead: bead('space-31x').copyWith(
                  description:
                      'Touch `apps/space/lib/prime_seat.dart` and '
                      '`apps/space/test/prime_seat_cli_smoke_test.dart`.',
                ),
                Workspace: testWorkspace(
                  'space-31x',
                  workspaceDir: '/w/space-31x',
                ),
                SubstationConfig: const SubstationConfig(
                  substationId: 'space_station',
                ),
              },
            ),
            stepArgs('space-31x/spec_review/discovery/$kAnchorsStep'),
          );
      expect(outcome, isA<Ok>());
      expect(
        shell.commands,
        [
          'dart run lunar:lunar decisions index --surface '
              'space_station/apps/space/lib/prime_seat.dart',
          'dart run lunar:lunar decisions index --surface '
              'space_station/apps/space/test/prime_seat_cli_smoke_test.dart',
        ],
        reason:
            'the SESSION\'s substation qualifies every surface, so the shell '
            'never parses `<repo>` as an input redirect',
      );
      expect(
        shell.commands.every((command) => !command.contains('<repo>')),
        isTrue,
      );
      expect(
        shell.calls.map((call) => call.workingDirectory).toSet(),
        {'/grid/lunar'},
        reason: 'the composing station\'s grid home is the ONLY cwd',
      );
      expect(gathered, hasLength(2));
      expect(
        gathered.every((record) => record.state == EvidenceState.complete),
        isTrue,
      );
    });

    test('unknown substation records decision surfaces unavailable without '
        'shell', () async {
      final never = _CannedShellRunner(
        output: jsonEncode({'spec': 1, 'decisions': <Object?>[]}),
      );
      final gathered = <DecisionSurfaceEvidence>[];
      final source = commandDecisionIndexSource(
        never,
        runnerInvocation: 'dart run lunar:lunar',
        gridHome: '/grid/lunar',
      );
      final outcome =
          await AnchorsCapability(
            decisions: (workspaceDir, surfaces) async {
              final records = await source(workspaceDir, surfaces);
              gathered.addAll(records);
              return records;
            },
            clearer: (_) {},
          ).run(
            FakeTreeContext(
              values: {
                // No bead `rig` AND no ambient session config: nobody can name
                // the substation, so nobody looks.
                Bead: bead('space-31x').copyWith(
                  description:
                      'Touch `apps/space/lib/prime_seat.dart` and '
                      '`apps/space/lib/prime_seat.dart` again.',
                ),
                Workspace: testWorkspace(
                  'space-31x',
                  workspaceDir: '/w/space-31x',
                ),
              },
            ),
            stepArgs('space-31x/spec_review/discovery/$kAnchorsStep'),
          );
      expect(outcome, isA<Ok>());
      expect(
        never.calls,
        isEmpty,
        reason: 'a `<repo>`-prefixed surface is NEVER handed to a shell',
      );
      expect(gathered, hasLength(1), reason: 'one record per DEDUP surface');
      expect(
        gathered.single.surface,
        '$kUnknownSubstationPrefix/apps/space/lib/prime_seat.dart',
      );
      expect(gathered.single.state, EvidenceState.unavailable);
      expect(
        gathered.single.command,
        isEmpty,
        reason: 'a command this pack never ran is never stamped as provenance',
      );
      expect(
        gathered.single.error,
        'substation unknown — no roster-qualified surface',
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

  group('the lenses are READ-ONLY (A37) and CHEAP (the gather lane)', () {
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
          lens: kDecisionLens,
          nodePath: 'tg-1/spec_review/discovery/$kDecisionLens',
          round: 0,
          workspaceDir: '/w/tg-1',
          projection: projectDiscoveryEvidence(
            completeGather(bead: workBead('tg-1'), round: 0),
            lens: kDecisionLens,
            round: 0,
            workBeadId: 'tg-1',
          ),
        );
        expect(prompt, contains('A DECISION ENTRY BINDS'));
        expect(prompt, contains('A BEAD IS NOT A DECISION'));
        expect(prompt, contains('INTENT, NOT PRESENCE'));
        expect(prompt, contains('"ratified":false'));
        expect(prompt, contains('"removesOffence":false'));
        for (final token in kLocalOnlyTokens) {
          expect(prompt, isNot(contains(token)));
        }
        expect(prompt, contains('the_grid#admission-authority-boundary'));
        expect(prompt, isNot(contains('amendments BIND too')));
      },
    );
  });

  group('the route STAMPS the invalidating grade (no Rewind is emitted)', () {
    late Directory ws;
    setUp(() {
      ws = Directory.systemTemp.createTempSync('discovery-regather');
      // The route refuses to advance over a gather whose evidence is known
      // incomplete, so the live posture needs the real artifact on disk.
      plantGather(ws.path, completeGather(bead: workBead('tg-1'), round: 0));
    });
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
      'the regather ledger OUTLIVES the anchors sweep (sibling of the dir)',
      () {
        expect(
          p.isWithin(discoveryDirPath('/w'), discoveryRegatherLedgerPath('/w')),
          isFalse,
          reason:
              'AnchorsCapability SWEEPS the gather dir at the head of every '
              'round — a counter kept inside it is unstamped, so the sweep '
              'deletes it and the bound restarts at 0 forever',
        );
      },
    );
  });

  group('round-stamped canonical evidence', () {
    test('every family and every state round-trips through schema v2', () {
      final anchors = _completeAnchors();
      final back = DiscoveryAnchors.fromJson(
        jsonDecode(jsonEncode(anchors.toJson())),
      )!;
      expect(back.round, 7);
      expect(back.workBeadId, 'pow-x');
      expect(back.beadFields, hasLength(BeadCitationField.values.length));
      expect(back.rubrics['coherence'], 'the coherence bands');
      expect(back.anchors.single.contents.digest, isNotEmpty);
      expect(back.anchors.single.contents.state, EvidenceState.complete);
      expect(back.priorArtQueries.single.hits.single.beadId, 'pow-96y');
      expect(
        back.decisionLookups.single.decisions.single.identity,
        'power_station#a21',
      );
      expect(back.history!.commits.single.sha, 'abc123def');
      expect(back.evidenceIds, anchors.evidenceIds);
      expect(back.priorArtWired, isTrue);
      // Each state survives the wire, and each is DISTINCT from the others.
      for (final state in EvidenceState.values) {
        final wired = BoundedEvidence.fromJson({
          'id': 'x:y@sha256:z',
          'source': 's',
          'snippet': '',
          'digest': 'z',
          'state': state.name,
          'error': 'a recorded reason',
        });
        expect(wired!.state, state);
      }
      expect(EvidenceState.fromWire('elsewhere'), isNull);
    });

    test('a decode is REFUSED, never emptied, on any malformed record', () {
      final wire =
          jsonDecode(jsonEncode(_completeAnchors().toJson()))
              as Map<String, Object?>;
      expect(DiscoveryAnchors.fromJson({...wire, 'version': 1}), isNull);
      expect(DiscoveryAnchors.fromJson({...wire, 'round': -1}), isNull);
      expect(DiscoveryAnchors.fromJson({...wire, 'round': '7'}), isNull);
      expect(DiscoveryAnchors.fromJson({...wire, 'workBeadId': ''}), isNull);
      expect(
        DiscoveryAnchors.fromJson({
          ...wire,
          'beadFields': [
            ...(wire['beadFields']! as List),
            {'beadId': 'pow-x', 'field': 'priority'},
          ],
        }),
        isNull,
        reason: 'a garbled entry is never silently dropped',
      );
      expect(
        DiscoveryAnchors.fromJson({
          ...wire,
          'anchors': [
            {
              'anchor': 'a.dart',
              'resolved': true,
              'contents': {
                'id': 'x@sha256:y',
                'digest': 'y',
                'state': 'nowhere',
              },
            },
          ],
        }),
        isNull,
        reason: 'an unknown evidence state is refused',
      );
      expect(
        DiscoveryAnchors.fromJson({
          ...wire,
          'anchors': [
            {
              'anchor': 'a.dart',
              'resolved': true,
              'contents': {
                'id': 'x@sha256:y',
                'digest': 'y',
                'state': 'failed',
                'error': '',
              },
            },
          ],
        }),
        isNull,
        reason: 'a FAILED record with no recorded error is refused',
      );
      final duplicated = wire['beadFields']! as List;
      expect(
        DiscoveryAnchors.fromJson({
          ...wire,
          'beadFields': [...duplicated, duplicated.first],
        }),
        isNull,
        reason: 'a duplicate evidence id would break the citation profile',
      );
    });

    test('a body over the snippet bound is TRUNCATED, hashed whole', () {
      final long = 'x' * (kMaxDiscoverySnippetChars + 500);
      final bounded = boundDiscoveryEvidence(
        kind: 'code-anchor',
        subject: 'lib/big.dart',
        source: 'lib/big.dart',
        fullText: long,
      );
      expect(bounded.state, EvidenceState.truncated);
      expect(bounded.snippet, hasLength(kMaxDiscoverySnippetChars));
      expect(
        bounded.digest,
        boundDiscoveryEvidence(
          kind: 'other',
          subject: 'elsewhere',
          source: '',
          fullText: long,
        ).digest,
        reason: 'the digest is over the COMPLETE text, not the snippet',
      );
      expect(bounded.id, contains('sha256:${bounded.digest}'));
    });

    test('a resolved anchor carries bounded contents; a missing one is a '
        'COMPLETE negative lookup', () {
      final dir = Directory.systemTemp.createTempSync('anchors-disk');
      addTearDown(() => dir.deleteSync(recursive: true));
      final nested = Directory(p.join(dir.path, 'lib'))..createSync();
      File(p.join(nested.path, 'a.dart')).writeAsStringSync('class A {}');
      for (var i = 0; i < kMaxNeighbors + 3; i++) {
        File(p.join(nested.path, 'n$i.dart')).writeAsStringSync('//');
      }
      final resolved = resolveAnchorsOnDisk(dir.path, [
        'lib/a.dart',
        'lib/missing.dart',
      ]);
      expect(resolved, hasLength(2));
      expect(resolved.first.resolved, isTrue);
      expect(resolved.first.contents.snippet, 'class A {}');
      expect(resolved.first.neighbors, hasLength(kMaxNeighbors));
      expect(resolved.first.neighborsTruncated, isTrue);
      expect(resolved.first.contents.state, EvidenceState.truncated);
      expect(resolved.last.resolved, isFalse);
      expect(resolved.last.contents.state, EvidenceState.complete);
      expect(resolved.last.contents.snippet, isEmpty);
    });

    test('an ABSENT source is UNAVAILABLE per query/surface, never an empty '
        'result', () async {
      expect(
        (await gatherPriorArt(null, ['q'])).single.state,
        EvidenceState.unavailable,
      );
      expect(
        (await gatherDecisions(null, '/w', ['repo/a.dart'])).single.state,
        EvidenceState.unavailable,
      );
      expect(
        (await gatherHistory(null, '/w', const [])).state,
        EvidenceState.unavailable,
      );
      // An EMPTY resolved path list never reaches the source (bead
      // `pow-gcx9`): a whole-repository log is not surface history.
      var invoked = 0;
      final overEmpty = await gatherHistory(
        (_, _) async {
          invoked++;
          throw StateError('must not run');
        },
        '/w',
        const [],
      );
      expect(invoked, 0);
      expect(overEmpty.state, EvidenceState.unavailable);
      expect(overEmpty.error, contains('no anchor resolved'));
      // A source that THROWS is FAILED, per requested unit, with its reason.
      final thrown = await gatherPriorArt(
        (_) async => throw StateError('store is down'),
        ['q'],
      );
      expect(thrown.single.state, EvidenceState.failed);
      expect(thrown.single.error, contains('store is down'));
    });

    test('a spec-2 decision-index envelope parses complete despite '
        'diagnostics, keeps every originRegister, resolves each slug, and '
        'FAILS loud on a crashed or malformed lookup', () async {
      final dir = Directory.systemTemp.createTempSync('decisions-index');
      addTearDown(() => dir.deleteSync(recursive: true));
      final register = Directory(p.join(dir.path, 'docs', 'decisions'))
        ..createSync(recursive: true);
      final entryFile =
          File(p.join(register.path, '2026-09-04-discovery-evidence.md'))
            ..writeAsStringSync(
              '---\nstatus: accepted\nregister:\n  spec: 1\n'
              '  slug: discovery-evidence-is-gathered-once-and-projected\n'
              '---\nthe gather is deterministic',
            );
      const surface =
          'power_station/packages/grid_assets/lib/src/code/discovery.dart';
      const slug = 'discovery-evidence-is-gathered-once-and-projected';
      const declared = [
        'packages/grid_assets/lib/src/code/discovery.dart',
        'packages/grid_assets/lib/src/code/code_capabilities.dart',
        'packages/grid_assets/extension/prompts/discovery.md',
      ];
      // Copied from a live `decisions index --surface` answer: the register
      // publishes OUTPUT schema 2 — `edges` on every decision, `diagnostics`
      // riding beside them — while entries stay at format `spec: 1`.
      final ok = _CannedShellRunner(
        output: jsonEncode({
          'spec': 2,
          'decisions': [
            {
              'originRegister': 'power_station',
              'originPath': register.path,
              'slug': slug,
              'status': 'accepted',
              'surfaces': declared,
              'edges': [
                {
                  'kind': 'updates',
                  'reference':
                      'a21-bead-pow-96y-the-discovery-circuit-a-nested-read-'
                      'only-ga',
                  'resolution': 'resolved',
                  'targetRegister': 'power_station',
                  'targetSlug':
                      'a21-bead-pow-96y-the-discovery-circuit-a-nested-read-'
                      'only-ga',
                },
                {
                  'kind': 'updates',
                  'reference':
                      'a23-bead-pow-kzx-the-station-overlay-delivery-lib-'
                      'renders-an',
                  'resolution': 'resolved',
                  'targetRegister': 'power_station',
                  'targetSlug':
                      'a23-bead-pow-kzx-the-station-overlay-delivery-lib-'
                      'renders-an',
                },
                {
                  'kind': 'updates',
                  'reference':
                      'the-spec-decision-lane-queries-the-roster-union',
                  'resolution': 'resolved',
                  'targetRegister': 'power_station',
                  'targetSlug':
                      'the-spec-decision-lane-queries-the-roster-union',
                },
              ],
            },
          ],
          'diagnostics': [
            {
              'ruleId': 'entry-schema',
              'file': 'docs/decisions/2026-01-01-unparsed.md',
              'message': 'missing `register.slug`',
            },
          ],
        }),
      );
      final surfaced = await commandDecisionIndexSource(
        ok,
        runnerInvocation: 'dart run lunar:lunar',
        gridHome: '/grid/lunar',
      )(dir.path, [surface, surface]);
      expect(
        ok.commands,
        ['dart run lunar:lunar decisions index --surface $surface'],
        reason:
            'one call per DEDUPLICATED surface, rendered from the COMPOSING '
            'station\'s invocation and never a literal binary name, with no '
            'register-dir argument',
      );
      expect(
        ok.calls.single.workingDirectory,
        '/grid/lunar',
        reason:
            'the station\'s JIT verb runs at ITS grid home, never at the '
            'work worktree (${dir.path}) where the package does not resolve',
      );
      final record = surfaced.single;
      expect(record.surface, surface);
      expect(record.command, ok.commands.single);
      expect(
        record.state,
        EvidenceState.complete,
        reason:
            'a producer-owned `diagnostics` array is CONTEXT — it never '
            'downgrades the union this consumer read: ${record.error}',
      );
      expect(record.error, isEmpty);
      expect(record.truncated, isFalse);
      final entry = record.decisions.single;
      expect(entry.identity, 'power_station#$slug');
      expect(entry.originRegister, 'power_station');
      expect(entry.originPath, register.path);
      expect(entry.slug, slug);
      expect(entry.status, 'accepted');
      expect(entry.surfaces, declared);
      expect(entry.entryPath, entryFile.path);
      expect(entry.body.state, EvidenceState.complete);
      expect(entry.body.snippet, contains('the gather is deterministic'));

      // Malformed JSON and a non-zero exit are BOTH loud failures.
      final malformed = await commandDecisionIndexSource(
        _CannedShellRunner(output: 'not json'),
        runnerInvocation: 'dart run lunar:lunar',
        gridHome: '/grid/lunar',
      )(dir.path, [surface]);
      expect(malformed.single.state, EvidenceState.failed);
      expect(malformed.single.error, contains('malformed index JSON'));

      final crashed = await commandDecisionIndexSource(
        _CannedShellRunner(exitCode: 127, output: 'command not found: lunar'),
        runnerInvocation: 'dart run lunar:lunar',
        gridHome: '/grid/lunar',
      )(dir.path, [surface]);
      expect(crashed.single.state, EvidenceState.failed);
      expect(crashed.single.error, contains('command not found'));

      // A slug the register cannot resolve is a failure, never a quiet skip.
      final unresolvable = await commandDecisionIndexSource(
        _CannedShellRunner(
          output: jsonEncode({
            'spec': 2,
            'decisions': [
              {
                'slug': 'no-such-entry',
                'originRegister': 'power_station',
                'originPath': 'docs/decisions',
                'status': 'accepted',
                'surfaces': <String>[],
                'edges': <Object?>[],
              },
            ],
            'diagnostics': <Object?>[],
          }),
        ),
        runnerInvocation: 'dart run lunar:lunar',
        gridHome: '/grid/lunar',
      )(dir.path, [surface]);
      expect(unresolvable.single.state, EvidenceState.failed);
      expect(unresolvable.single.error, contains('no-such-entry'));
    });

    test('a spec-1 decision-index envelope remains compatible — the legacy '
        'output any older composed CLI still emits is read, and its EMPTY '
        'union at exit 0 is a REAL result', () async {
      final empty = await commandDecisionIndexSource(
        _CannedShellRunner(
          output: jsonEncode({'spec': 1, 'decisions': <Object?>[]}),
        ),
        runnerInvocation: 'dart run lunar:lunar',
        gridHome: '/grid/lunar',
      )('/w', ['power_station/lib/a.dart']);
      expect(empty.single.state, EvidenceState.complete);
      expect(empty.single.decisions, isEmpty);
      expect(empty.single.error, isEmpty);
    });

    test(
      'unsupported decision-index specs fail and name the seen value',
      () async {
        for (final seen in <Object?>[0, 3, '2', null]) {
          final records = await commandDecisionIndexSource(
            _CannedShellRunner(
              output: jsonEncode({'spec': seen, 'decisions': <Object?>[]}),
            ),
            runnerInvocation: 'dart run lunar:lunar',
            gridHome: '/grid/lunar',
          )('/w', ['power_station/lib/a.dart']);
          expect(records.single.state, EvidenceState.failed, reason: '$seen');
          expect(records.single.decisions, isEmpty, reason: '$seen');
          expect(
            records.single.error,
            'index answered unsupported `spec`: ${jsonEncode(seen)}; '
            'accepted specs are 1 and 2',
            reason: 'the record names the exact value the index answered',
          );
        }
      },
    );

    test('an ABSENT station runner records UNAVAILABLE and never reaches the '
        'shell — this pack names no decisions binary', () async {
      final never = _CannedShellRunner(output: '{}');
      for (final invocation in [null, '', '   ']) {
        final records = await commandDecisionIndexSource(
          never,
          runnerInvocation: invocation,
        )('/w', ['power_station/lib/a.dart', 'power_station/lib/a.dart']);
        expect(never.commands, isEmpty, reason: 'no shell call is made at all');
        expect(records, hasLength(1), reason: 'one record per DEDUP surface');
        expect(records.single.state, EvidenceState.unavailable);
        expect(records.single.surface, 'power_station/lib/a.dart');
        expect(
          records.single.command,
          isEmpty,
          reason:
              'a command this pack never ran is never stamped as provenance',
        );
        expect(records.single.error, contains('no composing station runner'));
      }
      // A composed runner with NO grid home is the same honest absence: the
      // work worktree is never substituted as a place to run the verb.
      final unbound = _CannedShellRunner(output: '{}');
      for (final home in [null, '', '   ']) {
        final records = await commandDecisionIndexSource(
          unbound,
          runnerInvocation: 'dart run lunar:lunar',
          gridHome: home,
        )('/w', ['power_station/lib/a.dart', 'power_station/lib/a.dart']);
        expect(unbound.calls, isEmpty, reason: 'no shell call is made at all');
        expect(records, hasLength(1), reason: 'one record per DEDUP surface');
        expect(records.single.state, EvidenceState.unavailable);
        expect(records.single.command, isEmpty);
        expect(records.single.error, 'no composing grid home is bound');
      }

      // The unwired-SOURCE arm records the same shape, with its own reason —
      // and likewise invents no command.
      final unwired = await gatherDecisions(null, '/w', [
        'power_station/lib/a.dart',
      ]);
      expect(unwired.single.state, EvidenceState.unavailable);
      expect(unwired.single.command, isEmpty);
      expect(unwired.single.error, contains('no decision-index source'));
    });

    test('the history source batches ONE log; an empty log is COMPLETE and an '
        'unparseable record FAILS', () async {
      final runner = _CannedLogRunner();
      final empty = await gitHistorySource(runner)('/w', ['lib/a.dart']);
      expect(runner.calls, hasLength(1));
      expect(runner.calls.single, [
        'log',
        '--max-count=${kMaxHistoryCommits + 1}',
        '--format=%H%x09%aI%x09%s',
        '--',
        'lib/a.dart',
      ]);
      expect(empty.state, EvidenceState.complete);
      expect(empty.commits, isEmpty);

      final many = List.generate(
        kMaxHistoryCommits + 1,
        (i) => 'sha$i\t2026-09-0${i % 9}T00:00:00Z\tsubject $i',
      ).join('\n');
      final capped = await gitHistorySource(_CannedLogRunner(output: many))(
        '/w',
        ['lib/a.dart'],
      );
      expect(capped.commits, hasLength(kMaxHistoryCommits));
      expect(capped.state, EvidenceState.truncated);

      final garbled = await gitHistorySource(
        _CannedLogRunner(output: 'not-a-record'),
      )('/w', ['lib/a.dart']);
      expect(garbled.state, EvidenceState.failed);
      expect(garbled.error, contains('unparseable log record'));

      final crashed = await gitHistorySource(
        _CannedLogRunner(exitCode: 128, output: 'fatal: bad revision'),
      )('/w', ['lib/a.dart']);
      expect(crashed.state, EvidenceState.failed);
      expect(crashed.error, contains('bad revision'));
    });

    test(
      'the gather stamps the round and the work bead onto its artifact',
      () async {
        final dir = Directory.systemTemp.createTempSync('anchors-round');
        addTearDown(() => dir.deleteSync(recursive: true));
        final outcome =
            await AnchorsCapability(
              rubricIds: const ['coherence'],
              rubrics: (id) => '($id bands)',
              resolver: (_, paths) => [
                for (final path in paths) unresolvedAnchor(path, source: '/w'),
              ],
              priorArt: (queries) async => [
                for (final query in queries)
                  PriorArtQueryEvidence(
                    id: 'prior-art-query:$query@sha256:fake',
                    query: query,
                    state: EvidenceState.complete,
                  ),
              ],
              decisions: (_, surfaces) async => const [],
              history: (_, __) async => completeHistory(),
            ).run(
              FakeTreeContext(
                values: {
                  Bead: bead('tg-1').copyWith(
                    description:
                        'Extend `buildSpecifyBrief` in `lib/src/x.dart`.',
                  ),
                  Workspace: testWorkspace('tg-1', workspaceDir: dir.path),
                },
              ),
              stepArgs(
                'tg-1/spec_review/discovery/$kAnchorsStep',
                params: const {'grid.round': '3'},
              ),
            );
        expect(outcome, isA<Ok>());
        expect((outcome as Ok).payload![kVerdictRoundKey], '3');
        final written = readDiscoveryAnchors(dir.path)!;
        expect(written.round, 3);
        expect(written.workBeadId, 'tg-1');
        expect(written.anchors.single.anchor, 'lib/src/x.dart');
        expect(written.evidenceIds, isNotEmpty);
        expect((outcome).payload!['evidence'], '${written.evidenceIds.length}');
      },
    );
  });

  group('capability-specific projection', () {
    test('is isolated and command-free', () {
      final anchors = _completeAnchors();
      final code = _project(anchors, kCodeLens);
      final decision = _project(anchors, kDecisionLens);
      final prior = _project(anchors, kPriorArtLens);

      expect(code.renderedEvidence, contains('lib/src/code/discovery.dart'));
      expect(code.renderedEvidence, isNot(contains('power_station#a21')));
      expect(code.renderedEvidence, isNot(contains('abc123def')));
      expect(code.renderedEvidence, isNot(contains('pow-96y')));

      expect(decision.renderedEvidence, contains('power_station#a21'));
      expect(decision.renderedEvidence, isNot(contains('abc123def')));
      expect(decision.renderedEvidence, isNot(contains('pow-96y')));
      expect(
        decision.renderedEvidence,
        isNot(contains('class AnchorsCapability {}')),
      );

      expect(prior.renderedEvidence, contains('abc123def'));
      expect(prior.renderedEvidence, contains('pow-96y'));
      expect(prior.renderedEvidence, isNot(contains('power_station#a21')));
      expect(
        prior.renderedEvidence,
        isNot(contains('class AnchorsCapability {}')),
      );

      // No rubric prose reaches ANY lens — the architect is graded by it, the
      // explorers are not.
      for (final projection in [code, decision, prior]) {
        expect(
          projection.renderedEvidence,
          isNot(contains('the coherence bands')),
        );
        expect(projection.isSufficient, isTrue);
        expect(projection.evidenceIds, isNotEmpty);
        final sorted = [...projection.evidenceIds]..sort();
        expect(projection.evidenceIds, sorted);
        final prompt = _promptFor(projection);
        for (final id in projection.evidenceIds) {
          expect(prompt, contains(id));
        }
        for (final command in ['space decisions index', 'git log', 'grep -']) {
          expect(prompt, isNot(contains(command)));
        }
      }
    });

    test('an unknown lens gets NO bundle, only a named gap', () {
      final unknown = _project(_completeAnchors(), 'explore-nothing');
      expect(unknown.evidenceIds, isEmpty);
      expect(unknown.isSufficient, isFalse);
      expect(unknown.gaps.single.evidenceId, 'gather:lens');
    });

    test('a wrong round or a foreign work bead is a GAP, never a bundle', () {
      final anchors = _completeAnchors();
      final staleRound = projectDiscoveryEvidence(
        anchors,
        lens: kCodeLens,
        round: 8,
        workBeadId: 'pow-x',
      );
      expect(
        staleRound.gaps.map((g) => g.evidenceId),
        contains('gather:round'),
      );
      final foreign = projectDiscoveryEvidence(
        anchors,
        lens: kCodeLens,
        round: 7,
        workBeadId: 'pow-other',
      );
      expect(
        foreign.gaps.map((g) => g.evidenceId),
        contains('gather:workBeadId'),
      );
    });

    test('a CRASHED state becomes a gap carrying its recorded reason', () {
      for (final state in [EvidenceState.failed]) {
        final base = _completeAnchors();
        final holed = DiscoveryAnchors(
          round: base.round,
          workBeadId: base.workBeadId,
          beadFields: base.beadFields,
          anchors: base.anchors,
          symbols: base.symbols,
          priorArtQueries: [
            PriorArtQueryEvidence(
              id: base.priorArtQueries.single.id,
              query: 'AnchorsCapability',
              state: state,
              error: 'the store never answered',
            ),
          ],
          decisionLookups: base.decisionLookups,
          history: base.history,
        );
        final prior = _project(holed, kPriorArtLens);
        expect(prior.isSufficient, isFalse);
        expect(prior.gaps.single.evidenceId, base.priorArtQueries.single.id);
        expect(prior.gaps.single.reason, contains('the store never answered'));
        // The SAME hole is invisible to the lanes that were not handed it.
        expect(_project(holed, kCodeLens).isSufficient, isTrue);
        expect(_project(holed, kDecisionLens).isSufficient, isTrue);
      }
    });

    test('truncated is bounded context and never a deterministic gap', () {
      // bead `pow-gcx9`: a record clipped at a DECLARED bound is a bounded
      // answer. Every mature surface exceeds the snippet and history bounds, so
      // treating the clip as a broken promise held every real bead at
      // discovery-route; only the lens's own insufficient-evidence outcome may.
      final base = _completeAnchors();
      final clipped = DiscoveryAnchors(
        round: base.round,
        workBeadId: base.workBeadId,
        beadFields: base.beadFields,
        anchors: base.anchors,
        symbols: base.symbols,
        priorArtQueries: [
          PriorArtQueryEvidence(
            id: base.priorArtQueries.single.id,
            query: 'AnchorsCapability',
            state: EvidenceState.truncated,
            truncated: true,
          ),
        ],
        decisionLookups: base.decisionLookups,
        history: base.history,
      );
      final prior = _project(clipped, kPriorArtLens);
      expect(prior.isSufficient, isTrue);
      expect(prior.gaps, isEmpty);
      // The clip stays VISIBLE so the lens narrates it.
      expect(prior.renderedEvidence, contains('TRUNCATED'));
    });

    test('unavailable is explicit context and never a deterministic gap', () {
      final base = _completeAnchors();
      final projection = _project(
        DiscoveryAnchors(
          round: base.round,
          workBeadId: base.workBeadId,
          beadFields: base.beadFields,
          decisionLookups: [
            DecisionSurfaceEvidence(
              id: base.decisionLookups.single.id,
              surface: 'power_station/lib/a.dart',
              command: '',
              state: EvidenceState.unavailable,
              error: 'no composing station runner is configured',
            ),
          ],
          history: base.history,
        ),
        kDecisionLens,
      );
      // A source NOBODY COMPOSED is A21(5)'s "nobody looked" line: the lens is
      // told, and narrates around it. It never overrides the lens's report.
      expect(projection.isSufficient, isTrue);
      expect(projection.evidenceIds, contains(base.decisionLookups.single.id));
      expect(projection.renderedEvidence, contains('UNAVAILABLE'));
      expect(
        projection.renderedEvidence,
        contains('no composing station runner'),
      );
      // The prior-art lane's own optional source behaves identically.
      final noPriorArt = _project(
        DiscoveryAnchors(
          round: base.round,
          workBeadId: base.workBeadId,
          beadFields: base.beadFields,
          priorArtQueries: [
            PriorArtQueryEvidence(
              id: base.priorArtQueries.single.id,
              query: 'AnchorsCapability',
              state: EvidenceState.unavailable,
            ),
          ],
          history: base.history,
        ),
        kPriorArtLens,
      );
      expect(noPriorArt.isSufficient, isTrue);
      expect(noPriorArt.renderedEvidence, contains('UNAVAILABLE'));
    });

    test('a clipped extraction is named, so a short list is never silent', () {
      final base = _completeAnchors();
      final clipped = DiscoveryAnchors(
        round: base.round,
        workBeadId: base.workBeadId,
        beadFields: base.beadFields,
        anchors: base.anchors,
        symbols: base.symbols,
        anchorsTruncated: true,
        symbolsTruncated: true,
        priorArtQueries: base.priorArtQueries,
        decisionLookups: base.decisionLookups,
        history: base.history,
      );
      // bead `pow-gcx9`: a clipped extraction is NAMED, never a gap.
      final code = _project(clipped, kCodeLens);
      expect(code.isSufficient, isTrue);
      expect(code.gaps, isEmpty);
      expect(code.renderedEvidence, contains('MORE code surfaces'));
      expect(code.renderedEvidence, contains('MORE symbols'));
    });

    test('an empty successful lookup reads differently from a missing one', () {
      final base = _completeAnchors();
      final empties = DiscoveryAnchors(
        round: base.round,
        workBeadId: base.workBeadId,
        beadFields: base.beadFields,
        priorArtQueries: [
          PriorArtQueryEvidence(
            id: base.priorArtQueries.single.id,
            query: 'AnchorsCapability',
            state: EvidenceState.complete,
          ),
        ],
        decisionLookups: [
          DecisionSurfaceEvidence(
            id: base.decisionLookups.single.id,
            surface: 'power_station/lib/a.dart',
            command: 'space decisions index --surface power_station/lib/a.dart',
            state: EvidenceState.complete,
          ),
        ],
        history: completeHistory(),
      );
      expect(
        _project(empties, kPriorArtLens).renderedEvidence,
        contains('searched, NO hits — a real result'),
      );
      expect(
        _project(empties, kDecisionLens).renderedEvidence,
        contains('the union is EMPTY for this surface — a real result'),
      );
      expect(_project(empties, kPriorArtLens).isSufficient, isTrue);
      expect(_project(empties, kDecisionLens).isSufficient, isTrue);
    });

    test('the runtime prompt forbids the lookups the gather already ran', () {
      final prompt = _promptFor(_project(_completeAnchors(), kDecisionLens));
      expect(prompt, contains('Canonical evidence projection'));
      expect(prompt, contains('do NOT run a decision-index'));
      expect(prompt, contains('insufficient-evidence'));
      expect(prompt, isNot(contains(kDecisionLookupRule)));
    });
  });

  group('dossier cites canonical evidence identities', () {
    test('a clean advance persists and renders the sorted profile', () {
      final anchors = _completeAnchors();
      final verdict = decideDiscovery(
        lanes: {
          for (final lens in kDiscoveryLenses) lens: LensReport(lens: lens),
        },
        anchors: anchors,
        workBead: bead('pow-x'),
        priorRound: 0,
      );
      final dossier = (verdict as DiscoveryAdvance).dossier;
      expect(dossier.evidenceIds, anchors.evidenceIds.toList()..sort());
      final back = DiscoveryDossier.fromJson(
        jsonDecode(jsonEncode(dossier.toJson())),
      )!;
      expect(back.evidenceIds, dossier.evidenceIds);
      final rendered = renderDiscoveryDossier(back);
      expect(rendered, contains('Canonical evidence identities'));
      for (final id in dossier.evidenceIds) {
        expect(rendered, contains('`$id`'));
      }
    });

    test(
      'an UNAVAILABLE or FAILED query never prints as "searched, no hits"',
      () {
        const unavailable = DiscoveryDossier(
          anchors: DiscoveryAnchors(
            priorArtQueries: [
              PriorArtQueryEvidence(
                id: 'prior-art-query:q@sha256:fake',
                query: 'q',
                state: EvidenceState.unavailable,
                error: 'no prior-art source is composed',
              ),
            ],
          ),
        );
        final rendered = renderDiscoveryDossier(unavailable);
        expect(rendered, contains('nobody looked'));
        expect(rendered, isNot(contains('searched, no hits')));

        const failed = DiscoveryDossier(
          anchors: DiscoveryAnchors(
            priorArtQueries: [
              PriorArtQueryEvidence(
                id: 'prior-art-query:q@sha256:fake',
                query: 'q',
                state: EvidenceState.failed,
                error: 'absent alpha: no work store',
              ),
            ],
          ),
        );
        final failedText = renderDiscoveryDossier(failed);
        expect(failedText, contains('the search FAILED'));
        expect(failedText, contains('absent alpha'));
        expect(failedText, isNot(contains('searched, no hits')));
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
