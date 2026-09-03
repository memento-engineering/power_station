// The DISCOVERY circuit, offline end-to-end.
//
// Drives the nested gather + CITE-THE-OFFENCE gate — the spec circuit's second
// head, between the readiness ladder and `specify` — through the REAL `runGrid`
// station root + CodeCircuitResolver + buildCodeRegistry, advancing the
// per-node cursor via the fake STATE source (the bridge re-projecting each
// chokepoint write). The worktree is a REAL temp dir, so the gather's
// `anchors.json`, the lenses' reports and the route's `dossier.json` are real
// files on disk; the lens PROCESSES are the fake runtime provider's recorded
// spawns.
//
// Four proofs — the bead's acceptance criteria:
//  - THE GATHER SPAWNS NOTHING: `anchors` is deterministic (ZERO agents) and its
//    output lands in the worktree; only then do the three READ-ONLY explorers fan
//    out IN PARALLEL, on the CHEAP tier.
//  - AN OFFENDER SPAWNS NO ARCHITECT: a lens reporting a CITED, unacknowledged
//    contradiction of a ratified decision GATES at `discovery-route` — the gate
//    NAMES the offence, and `specify` never mounts.
//  - A CLEAN BEAD ADVANCES: the curated dossier lands in the worktree, `specify`
//    spawns, and the architect's brief RENDERS the dossier — the rubrics it will
//    be graded by included.
//  - PRE-DISCOVERY (the MIGRATION negative control): a session minted under the
//    pre-discovery shape and surviving a station BOUNCE roots the FROZEN circuit
//    — the gather NEVER mounts, its three agents NEVER spawn, and its route can
//    never PARK a bead whose build is already running.
//
// Offline — FAKES, no live tg/gc/claude/bd/git/network.
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

class _PriorArtDelegate extends sdk.GridDelegate {
  @override
  Seed build(TreeContext context, sdk.GridConfiguration configuration) =>
      sdk.RawAssetGrid(
        root: '/grid/home',
        assets: [
          sdk.Station(
            name: 'station',
            assets: [
              sdk.Substations(
                substations: [
                  sdk.Substation('alpha', '/alpha', prefix: 'exact'),
                ],
              ),
            ],
          ),
        ],
      );
}

class _PriorArtSource implements SubstationBeadSource {
  static const exact = Bead(id: 'exact-id', title: 'Ratified decision');
  static const conceptual = Bead(
    id: 'exact-topic',
    title: 'conceptual wording precedent',
  );
  static const semanticOnly = Bead(
    id: 'exact-semantic',
    title: 'unrelated lexical text',
  );

  @override
  Future<List<Bead>> read(sdk.SubstationScope scope) async => const [
    exact,
    conceptual,
    semanticOnly,
  ];
}

class _PriorArtSemanticBackend implements SemanticSearchBackend {
  @override
  Future<List<double>> embedQuery(String query) async => const [1];

  @override
  Future<List<EmbeddingIndexedBead>> indexedBeads(String store) async => [
    for (final bead in const [
      _PriorArtSource.exact,
      _PriorArtSource.conceptual,
      _PriorArtSource.semanticOnly,
    ])
      EmbeddingIndexedBead(
        beadId: bead.id,
        changeKey: embeddingChangeKey(bead),
      ),
  ];

  @override
  Future<List<EmbeddingIndexHit>> nearest({
    required String store,
    required List<double> queryVector,
    required int limit,
  }) async => [
    EmbeddingIndexHit(
      row: EmbeddingIndexRow(
        store: store,
        beadId: _PriorArtSource.semanticOnly.id,
        field: 'description',
        chunkIx: 0,
        changeKey: embeddingChangeKey(_PriorArtSource.semanticOnly),
        chunkText: 'semantic-only conceptual match',
        vector: const [1],
      ),
      distance: 0.1,
    ),
  ];
}

GraphSnapshot _graph({required List<Bead> beads, required Set<String> ready}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime(2026),
    );

GraphSnapshot _state(List<Bead> beads) => _graph(beads: beads, ready: const {});

const _sid = 'tgdog-sess1';
String _step(String relPath) => '$_sid/tg-1/$relPath';

/// The ADR clause the decision lens cites — a REAL clause of the live register,
/// so the proof can never pass on a fabricated citation.
const String _adr = 'docs/adr/ADR-0000-ai-decision-register.md A17(3)';

/// A session whose READINESS LADDER is complete and nothing else — the bead is
/// released into DISCOVERY, which is this suite's focus.
List<Bead> _ladderDone({Set<String> completed = const {}}) => committeeSession(
  id: _sid,
  completed: {...kReadinessLadderNodes, ...completed},
  grades: kReadinessGradeA,
);

/// A session minted under the PRE-DISCOVERY shape (`pow-q7n`): its cursor carries
/// the ladder AND `spec_review/specify`, but NO `spec_review/discovery/anchors`.
/// That absence IS the migration signal — `classifyCodeShape` reads it as
/// `laddered` and roots the FROZEN pre-discovery circuit. The bead is already past
/// the spec phase and into its build.
///
/// `omit: kDiscoveryNodes` is load-bearing, not cosmetic: [committeeSession]
/// stages a `type=step` bead for EVERY node in [kAllCodeCircuitNodes] by
/// default (`pending` unless named in `completed`/`gated`), so WITHOUT the
/// omission a survivor would present with a PENDING `anchors` step bead — a
/// staged, live discovery node, not an ABSENT one — and the resolver would
/// (correctly, given that shape) root the CURRENT circuit instead of the
/// frozen one this negative control exists to prove.
List<Bead> _preDiscoverySession() => committeeSession(
  id: _sid,
  completed: {
    ...kReadinessLadderNodes,
    kSpecifyNode,
    kSpecClearCritiqueNode,
    kSpecGateNode,
    ...kSpecCriticNodes,
    kSpecRouteNode,
  },
  grades: {
    ...kReadinessGradeA,
    kSpecGateNode: 'A',
    for (final n in kSpecCriticNodes) n: 'A',
  },
  omit: kDiscoveryNodes,
);

/// A [SourceControl] that hands every bead the SAME real temp worktree — the one
/// this suite plants lens reports into and reads the dossier back out of. NO
/// delivery method is bound on the bundle, so the terminal route advances bare and
/// no git is ever touched (Fakes, not mocks).
class _TempWorkspace implements SourceControl {
  const _TempWorkspace(this.dir);

  final String dir;

  @override
  String workspaceFor(String beadId) => dir;

  @override
  String branchFor(String beadId) => 'grid/$beadId';

  @override
  String get baseBranch => 'main';

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {}
}

MountedStation _buildStation(
  Fakes f,
  FakeSnapshotSource work,
  FakeSnapshotSource state,
  String workspaceDir, {
  PriorArtSource? priorArt,
}) {
  final bridge = StationJoinBridge(work: work, state: state);
  return MountedStation(
    bridge: bridge,
    stationServices: f.ctx,
    resolver: kCodeResolver,
    registry: buildCodeRegistry(
      rubrics: (id) => '($id rubric bands)',
      gitRunner: f.git,
      shellRunner: RecordingShellRunner(),
      // A no-op clearer: this suite PLANTS the lens reports the fake lens
      // processes would have written, so the round-freshness wipe must not race
      // them. The wipe's own contract is fenced in `discovery_test.dart`.
      critiqueDirClearer: (_) {},
      priorArt: priorArt,
    ),
    substations: [
      SubstationScope(
        configNotifier: SubstationConfigNotifier(
          const SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'}),
        ),
        services: ServiceBundle(sourceControl: _TempWorkspace(workspaceDir)),
        key: const ValueKey('scope.tg'),
      ),
    ],
  );
}

/// True iff some chokepoint `update` targeting [relPath]'s OWN `type=step`
/// bead (id `'$_sid-${relPath with dashes}'`, [stepBead]'s shape) wrote
/// `grid.step.state` == [stateName] — the molecule model's per-node cursor
/// write (tg-eli phase 2): NO `{nodePath}` infix (the bead IS the node), so
/// this checks the TARGET bead id, not a nodePath-keyed metadata field, unlike
/// the retired flat model's `grid.cursor.<nodePath>.state`.
bool _wroteCursor(Fakes f, String relPath, String stateName) {
  final targetId = '$_sid-${relPath.replaceAll('/', '-')}';
  return f.runner.callsFor('update').any((c) {
    if (c.length < 2 || c[1] != targetId) return false;
    return callMetadata(c)[MoleculeStepKeys.state] == stateName;
  });
}

/// The `reason` the chokepoint stamped on the minted gate bead.
String? _gateReason(Fakes f) {
  for (final c in f.runner.callsFor('update')) {
    final reason = callMetadata(c)['reason'];
    if (reason is String) return reason;
  }
  return null;
}

Iterable<String> _spawned(Fakes f) => f.provider.started.map((s) => s.name);

/// Writes the report a lens process would have written — at the canonical
/// absolute path its own prompt names, stamped with its own `nodePath`.
void _plantReport(String dir, String lens, LensReport report) {
  final json = {
    ...report.toJson(),
    'nodePath': 'tg-1/spec_review/discovery/$lens',
  };
  File(lensReportPath(dir, lens))
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(json));
}

/// Pumps the event queue until the fake harness reaches a FIXED POINT — no new
/// provider spawn/exit AND no new bd runner call across [stableRounds]
/// CONSECUTIVE checks — or [maxPumps] pumps have run, whichever comes first.
/// Built on the shared bounded [settle] helper (`asset_fakes.dart`).
///
/// The molecule model's per-push reconcile is a materially LONGER async chain
/// than the retired flat cursor's single write (tg-eli phase 2): a fresh
/// mint's own pour (`create --graph`) can sit through many consecutive
/// no-visible-change pumps before its reply lands and the cascade resumes, so
/// a single quiet pump is NOT proof of quiescence — [stableRounds] guards
/// against declaring victory on a plateau that is still mid-flight. Still
/// fails a genuine regression (it never quiesces, so it exhausts [maxPumps]).
Future<void> _settle(
  Fakes f, {
  int maxPumps = 1000,
  int stableRounds = 50,
}) async {
  var stable = 0;
  var prevStarted = -1;
  var prevCalls = -1;
  await settle(() {
    final started = f.provider.started.length;
    final calls = f.runner.calls.length;
    if (started == prevStarted && calls == prevCalls) {
      stable++;
    } else {
      stable = 0;
    }
    prevStarted = started;
    prevCalls = calls;
    return stable >= stableRounds;
  }, maxPumps: maxPumps);
}

/// Marks [name] STARTED before this drive emits its `Exited` — the
/// completion-fence contract (`270f9c6`, "prove inferred exits before
/// advancing"): an `Exited` for a name the allocation never observed
/// `SessionStarted` for is a STALE/unproven exit and is correctly dropped,
/// never advancing the step. Mirrors `invariant_4_a37_pristine_source_test
/// .dart`'s own `SessionStarted` emission ahead of its `Exited`.
Future<void> _markStarted(Fakes f, String name) async {
  f.provider.emit(SessionStarted(name: name, pid: 1, pgid: 1));
  await pumpEventQueue();
}

void main() {
  test(
    'stationPriorArt preserves query provenance and remains lexical-only',
    () async {
      final service = StationSearchService(
        source: _PriorArtSource(),
        dirExists: (_) => true,
        semanticBackendMount: (_) async => _PriorArtSemanticBackend(),
      );
      final priorArt = await stationPriorArt(
        _PriorArtDelegate.new,
        gridHome: '/grid/home',
        service: service,
      )(['conceptual wording', 'exact-id']);

      expect(priorArt.map((hit) => hit.query), [
        'conceptual wording',
        'exact-id',
      ]);
      expect(priorArt.map((hit) => hit.beadId), ['exact-topic', 'exact-id']);
      expect(priorArt.last.field, 'id');
      expect(
        priorArt.every((hit) => !hit.snippet.contains('semantic-only')),
        isTrue,
      );
    },
  );

  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('discovery-acc');
    // A bare `.git` marker — the molecule model's live ProcessLeaseVendor
    // allocation now runs `assertProvisionedCheckout` (ADR-0009 D3, bead
    // `tg-6jn`) before EVERY agent spawn (the three explorer lenses here),
    // which fail-closed REFUSES a workspace with no on-disk `.git` — a real
    // check the retired flat model's capability mount never performed. No
    // real git init needed: the lenses never shell git themselves, only read
    // plain files under this dir.
    Directory('${tmp.path}/.git').createSync(recursive: true);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Drives the kernel to the point where the three lenses have spawned and
  /// exited, with [reports] planted in the worktree — leaving the route as the
  /// next thing to mount.
  Future<Fakes> driveToRoute(
    Map<String, LensReport> reports, {
    PriorArtSource? priorArt,
  }) async {
    final f = buildFakes(createdId: _sid);
    final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
    final state = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
    final station = _buildStation(f, work, state, tmp.path, priorArt: priorArt);
    addTearDown(station.dispose);
    addTearDown(f.provider.close);
    addTearDown(work.close);
    addTearDown(state.close);

    await station.start();
    await _settle(f);

    // The ladder is fast-forwarded (its own choreography is
    // `readiness_acceptance_test.dart`) → the bead is released into DISCOVERY.
    work.push(_graph(beads: [workBead('tg-1')], ready: {'tg-1'}));
    await _settle(f);
    state.push(_state(_ladderDone()));
    await _settle(f);

    // TIER 1: the deterministic gather ran, spawned NOTHING, and left its output
    // in the worktree for every lens to read.
    expect(_wroteCursor(f, kAnchorsNode, 'complete'), isTrue);
    expect(
      _spawned(f),
      isEmpty,
      reason: 'the gather is a ServiceCapability — ZERO agents',
    );
    expect(File(anchorsPath(tmp.path)).existsSync(), isTrue);

    // TIER 2: the three READ-ONLY explorers fan out IN PARALLEL, on the CHEAP
    // tier — and the architect is still withheld.
    state.push(_state(_ladderDone(completed: {kAnchorsNode})));
    await _settle(f);
    expect(_spawned(f).toSet(), kDiscoveryLensNodes.map(_step).toSet());
    for (final spawn in f.provider.started) {
      final args = spawn.config.args;
      expect(args[args.indexOf('--model') + 1], kCheapModelDefault);
      expect(args.join('\n'), contains('You are READ-ONLY'));
    }
    expect(
      _spawned(f),
      isNot(contains(_step(kSpecifyNode))),
      reason: 'the architect is withheld behind the violation gate',
    );

    // Each lens writes its report and exits clean.
    for (final entry in reports.entries) {
      _plantReport(tmp.path, entry.key, entry.value);
    }
    for (final lens in kDiscoveryLensNodes) {
      await _markStarted(f, _step(lens));
      f.provider.emit(Exited(name: _step(lens), exitCode: 0));
    }
    await _settle(f);
    state.push(
      _state(_ladderDone(completed: {kAnchorsNode, ...kDiscoveryLensNodes})),
    );
    await _settle(f);
    return f;
  }

  group('the discovery circuit — an OFFENDER spawns NO architect', () {
    test(
      'a CITED, unacknowledged contradiction of a ratified decision GATES at '
      'discovery-route with the offence NAMED, and specify NEVER spawns',
      () async {
        final f = await driveToRoute({
          for (final lens in kDiscoveryLenses)
            lens: LensReport(
              lens: lens,
              violations: lens == kDecisionLens
                  ? const [
                      DiscoveryFinding(
                        kind: ViolationKind.decision,
                        standard: _adr,
                        ratified: true,
                        contradicts: true,
                        quote:
                            'a false HOLD STALLS the governance track itself',
                        contradiction:
                            'this bead gates the track on an absent verdict',
                      ),
                    ]
                  : const [],
            ),
        });

        // The HOLD: parked at the route, CITING the standard it offends.
        expect(_wroteCursor(f, kDiscoveryRouteNode, 'gated'), isTrue);
        final reason = _gateReason(f);
        expect(reason, isNotNull);
        expect(reason, contains('DISCOVERY HOLD'));
        expect(
          reason,
          contains(_adr),
          reason:
              'the gate CITES the offence — a hold with no citation is '
              'exactly what this circuit forbids',
        );
        expect(
          reason,
          contains('DECLARE the departure'),
          reason: 'the ask states both exits — revise, or declare',
        );

        // The saving, asserted: the expensive fan-out never happened.
        final started = _spawned(f);
        expect(
          started,
          isNot(contains(_step(kSpecifyNode))),
          reason: 'an offending bead must not reach the specify architect',
        );
        for (final critic in kSpecCriticNodes) {
          expect(started, isNot(contains(_step(critic))));
        }
        expect(
          started.toSet(),
          kDiscoveryLensNodes.map(_step).toSet(),
          reason: 'exactly THREE cheap agents ran — the explorers themselves',
        );
      },
    );
  });

  group('the discovery circuit — a CLEAN bead advances with its dossier', () {
    test(
      'clean bead A plus urgent sibling B keeps B FOREIGN in the written dossier',
      () async {
        const sibling = PriorArt(
          beadId: 'tg-b',
          store: 'the_grid',
          status: 'open',
          title: 'urgent approved rename',
          field: 'notes',
          snippet: 'Approved with Nico',
          query: 'work bead',
        );
        final f = await driveToRoute({
          for (final lens in kDiscoveryLenses)
            lens: LensReport(
              lens: lens,
              context: lens == kPriorArtLens
                  ? const [
                      ContextNote(
                        note: 'the sibling has human approval',
                        beadCitation: BeadFieldCitation(
                          beadId: 'tg-b',
                          field: BeadCitationField.notes,
                          excerpt: 'Approved with Nico',
                        ),
                      ),
                      ContextNote(
                        note: 'the work bead has human approval',
                        beadCitation: BeadFieldCitation(
                          beadId: 'tg-1',
                          field: BeadCitationField.notes,
                          excerpt: 'Approved with Nico',
                        ),
                      ),
                    ]
                  : const [],
            ),
        }, priorArt: (_) async => const [sibling]);

        expect(_wroteCursor(f, kDiscoveryRouteNode, 'complete'), isTrue);
        final dossier = readDiscoveryDossier(tmp.path)!;
        final rendered = renderDiscoveryDossier(dossier);
        expect(rendered, contains('FOREIGN tg-b.notes'));
        expect(rendered, contains('Approved with Nico'));
        expect(rendered, isNot(contains('SELF tg-1.notes')));
        expect(dossier.context, hasLength(1));
      },
    );

    test('the route ADVANCES, the curated dossier lands in the worktree, and the '
        'architect brief RENDERS it — the grading rubrics included', () async {
      final f = await driveToRoute({
        for (final lens in kDiscoveryLenses)
          lens: LensReport(
            lens: lens,
            context: [
              ContextNote(
                note: 'the $lens angle: this pack is a genesis_tree consumer',
                source: 'CLAUDE.md',
              ),
            ],
            // A concern the lens could NOT cite: it rides as a FLAG, and it
            // must NOT hold the bead.
            violations: lens == kCodeLens
                ? const [
                    DiscoveryFinding(
                      kind: ViolationKind.pattern,
                      standard: '',
                      quote: '',
                      contradiction: 'this feels like it duplicates the route',
                    ),
                  ]
                : const [],
          ),
      });

      expect(_wroteCursor(f, kDiscoveryRouteNode, 'complete'), isTrue);
      expect(
        _wroteCursor(f, kDiscoveryRouteNode, 'gated'),
        isFalse,
        reason: 'an UNCITED concern is a vibe — it can never hold a bead',
      );

      // The dossier is REAL: the route wrote it into the worktree.
      expect(File(discoveryDossierPath(tmp.path)).existsSync(), isTrue);
      final dossier = readDiscoveryDossier(tmp.path);
      expect(dossier, isNotNull);
      expect(dossier!.context, hasLength(3));
      expect(dossier.flags, hasLength(1));
      expect(dossier.anchors.rubrics.keys, containsAll(kSpecCommitteeRubrics));

      // And the ARCHITECT reads it: the brief the specify stage builds renders
      // the dossier — the rubrics its spec is graded by FIRST (the whole point
      // of the gather).
      final brief = buildSpecifyBrief(
        workBead('tg-1'),
        testWorkspace('tg-1', workspaceDir: tmp.path),
        dossier: dossier,
      );
      expect(brief.task, contains('Discovery dossier'));
      expect(brief.task, contains('How your spec will be graded'));
      for (final rubric in kSpecCommitteeRubrics) {
        expect(brief.task, contains('($rubric rubric bands)'));
      }
      expect(brief.task, contains('genesis_tree consumer'));
      expect(brief.task, contains('Flags — ANSWER these'));
    });

    test('with discovery complete, the architect finally spawns', () async {
      final f = buildFakes(createdId: _sid);
      final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
      final state = FakeSnapshotSource(
        _graph(beads: const [], ready: const {}),
      );
      final station = _buildStation(f, work, state, tmp.path);
      addTearDown(station.dispose);
      addTearDown(f.provider.close);
      addTearDown(work.close);
      addTearDown(state.close);

      await station.start();
      await _settle(f);
      work.push(_graph(beads: [workBead('tg-1')], ready: {'tg-1'}));
      await _settle(f);
      state.push(_state(ladderDoneSession(id: _sid)));
      await _settle(f);

      expect(
        _spawned(f),
        [_step(kSpecifyNode)],
        reason: 'the gather cleared the bead — ONLY THEN the architect',
      );
    });
  });

  group('the discovery circuit — the MIGRATION negative control', () {
    test(
      'a PRE-DISCOVERY in-flight session surviving a bounce roots the FROZEN '
      'circuit: the gather never mounts, its three explorers never spawn, and '
      'the route can never park a bead that is already building',
      () async {
        final f = buildFakes(createdId: _sid);
        final work = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        // The BOUNCE: the station restarts and ADOPTS an in-flight session whose
        // cursor was minted under the pre-discovery shape (no `anchors` key).
        final state = FakeSnapshotSource(_state(_preDiscoverySession()));
        final station = _buildStation(f, work, state, tmp.path);
        addTearDown(station.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        await station.start();
        await _settle(f);
        work.push(_graph(beads: [workBead('tg-1')], ready: {'tg-1'}));
        await _settle(f);

        final started = _spawned(f);

        // The gather NEVER mounts for a survivor — the three agents that would
        // have been spawned (and billed) never are.
        expect(
          started.where((s) => s.contains('/discovery/')),
          isEmpty,
          reason: 'a pre-discovery survivor must NEVER spawn an explorer',
        );
        expect(_wroteCursor(f, kAnchorsNode, 'complete'), isFalse);
        expect(
          _wroteCursor(f, kDiscoveryRouteNode, 'gated'),
          isFalse,
          reason: 'the gate can never PARK a bead that is already building',
        );
        expect(File(anchorsPath(tmp.path)).existsSync(), isFalse);

        // Non-vacuous: the session CONTINUES where it left off — the frozen
        // circuit's spec phase is complete, so the BUILD agent is what mounts.
        expect(
          started,
          contains(_step(kAgentNode)),
          reason: 'the survivor resumes its build, proving the kernel is live',
        );
      },
    );
  });
}
