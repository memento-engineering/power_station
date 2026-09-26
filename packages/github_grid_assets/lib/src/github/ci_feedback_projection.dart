import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show BeadOwnershipPredicate, GridIssueTypes;
import 'package:grid_sdk/grid_sdk.dart' show SubstationScope;

import 'ci_feedback.dart';
import 'reconciler_event.dart';
import 'resident_feedback_command.dart';

/// The delivery-leg name under which [CiFeedbackProjection] is registered.
///
/// The outbox records this leg against a pending observation once the
/// projection returns, so a replay after a crash does NOT re-drive it. That
/// matters because [CiFeedbackProjection]'s own `_handled` guard is in-memory
/// and a restart empties it, while its rework request is idempotent only within
/// one rework round: a successful rework increments the round `decideCiFeedback`
/// reads back, so a re-drive would mint a SECOND round for one CI failure.
const String kCiFeedbackDeliveryLeg = 'ci-feedback';

/// The flare name carried by an observation this leg declined to act on.
const String kCiFeedbackIgnoredFlare = 'reconciler.ciFeedbackIgnored';

/// The flare name carried by an open pull request this leg could not attribute
/// to a bead.
///
/// The DEGRADED event, never a dropped one. Silence about an open pull request
/// is the defect this leg exists to remove: a pull nobody can attribute still
/// reaches the reporter, weaker — it names no bead and mutates nothing — so a
/// human can see it rather than discover it after `main` moved underneath it.
const String kCiFeedbackUnattributedFlare = 'reconciler.ciFeedbackUnattributed';

/// The flare name carried by a merged pull request whose work bead the scoped
/// work store could not resolve.
///
/// The DEGRADED event, never a wedge. A bead the scoped store answers
/// `sql: no rows in result set` for — or one whose id prefix that scope
/// does not own at all — is a shape a store LEGITIMATELY holds, so by this
/// file's own rule (see [CiFeedbackProjection._ignore]) it can never be a
/// throw: a throw here aborts the cycle before the poll and re-drives the same
/// observation forever. The landing mark is lost, loudly, and the cycle
/// continues.
const String kCiFeedbackLandingUnresolvedFlare =
    'reconciler.ciFeedbackLandingUnresolved';

/// The flare name carried by a capped work bead whose ci-rework cap gate the
/// grid STATE store refused to mint.
///
/// The DEGRADED event, never a wedge. A cap-gate write is ONE bead's business:
/// letting its failure throw out of the delivery leg aborted the WHOLE
/// reconciliation cycle before the poll, and the shared obligation tick then
/// failed on every cycle for every substation while one red pull kept refusing
/// (observed on lunar epoch 98: `trajectory.obligationStuck` at streak 5 over
/// a single bead). The gate is lost, loudly, naming the bead, and the cycle
/// continues past it.
const String kCiFeedbackCapGateUnresolvedFlare =
    'reconciler.ciFeedbackCapGateUnresolved';

/// The `node` a ci-rework cap gate blocks, for [beadId]: the same
/// `<bead>/<leaf>` shape every engine-minted gate's `node` carries.
String ciReworkCapGateNode(String beadId) => '$beadId/ci-feedback';

/// Reports one CI-feedback outcome the leg declined to act on.
///
/// The SAME shape the reconciler asset already reports a failed cycle and a
/// malformed intake row with, because it IS that reporting: the asset that owns
/// the seat's `ExplorationTransport` binds a callback here (see
/// [CiFeedbackProjection.bindReporter]), so this leg needs no transport of its
/// own and there is no second reporting path to keep in step.
typedef CiFeedbackReporter =
    void Function(
      String flareName,
      String action,
      Object error,
      StackTrace stackTrace,
    );

/// Projects normalized pull-request feedback into the durable bead/control
/// rails.
///
/// ATTRIBUTION IS STATED, NEVER INFERRED. The leg used to parse `grid/<bead>`
/// out of a head ref, which is branch-name-as-database: it worked only for a
/// branch the station itself minted, so a pull request a seat opened reached no
/// projection at all. It now reads exactly one EXPLICIT reference — a `Refs:`
/// trailer in the pull body, else exactly one bead whose external ref is
/// `gh-<number>` — and no branch value participates in any decision here.
/// TWO STORES, NAMED SEPARATELY. A session bead and a rework-cap gate live in
/// the grid STATE store; the WORK bead a merged pull is landing lives in its
/// own substation's store, and no substation's work bead exists in the state
/// store. Running the landing-ready mutation through [bd] therefore resolved
/// every bead of every armed substation against a store that has never held
/// it. The two rails are now distinct constructor inputs, so the wrong one is
/// a compile error rather than a `sql: no rows in result set` on every tick.
final class CiFeedbackProjection {
  CiFeedbackProjection({
    required this.bd,
    required this.workBd,
    required this.scope,
    required this.commandSender,
    required this.gridRoot,
  }) : _store = BdCliService(bd),
       _ownership = BeadOwnershipPredicate(<String>[scope.prefix]);

  /// The grid STATE store runner: the session correlation read and the
  /// rework-cap gate, both of which ARE state-store beads.
  final BdRunner bd;

  /// The runner for [scope]'s OWN work store: the landing-ready mutation, and
  /// nothing else.
  ///
  /// There is no fallback to [bd]. A projection composed with one runner for
  /// both rails is exactly the defect this pair exists to make unrepresentable.
  final BdRunner workBd;

  /// The substation this projection is mounted under.
  ///
  /// Delivered by TREE POSITION — the enclosing `SubstationScope` the binding
  /// already watches — never by a bead-keyed roster lookup. It is the single
  /// source of both [workBd]'s store identity ([SubstationScope.root]) and the
  /// prefix a work bead must carry to be mutable from here.
  final SubstationScope scope;

  final FeedbackCommandSender commandSender;
  final String gridRoot;

  /// The substation name stamped on a minted cap gate.
  ///
  /// DERIVED from [scope], never passed beside it: a name that contradicted
  /// the scope whose store is being written would be unnoticeable.
  String get substation => scope.name;

  /// The complete-prefix guard over [scope]: whether [workBd]'s store is the
  /// one that mints a given bead id.
  final BeadOwnershipPredicate _ownership;

  /// The TYPE-SCOPED session read this leg correlates a check against.
  ///
  /// Composed over the SAME [bd] runner, so the store and its actor are
  /// unchanged; only the READ FORM moved. `bd export --all` — which this leg
  /// used to run — is refused outright by a proxied-server store ("export is
  /// not supported in proxied-server mode"), which failed the leg on every
  /// cycle and head-of-line blocked the seat's whole poll behind one pending
  /// observation. `bd list -t session --all` is the form such a store answers.
  final BdCliService _store;

  final Set<String> _handled = <String>{};
  CiFeedbackReporter? _reporter;

  /// Binds [reporter] as this leg's flare rail, replacing any previous binding.
  void bindReporter(CiFeedbackReporter reporter) => _reporter = reporter;

  /// Unbinds [reporter] when it is still the bound one, leaving a binding some
  /// other owner has since installed alone.
  void unbindReporter(CiFeedbackReporter reporter) {
    if (identical(_reporter, reporter)) _reporter = null;
  }

  Future<void> call(NormalizedGitHubEvent event) async {
    switch (event) {
      // A workflow run is NOT a `grid/` pull-request session check: it carries
      // no session to correlate, no rework round to increment and no landing
      // to mark. It belongs to intake, and this leg returns from it — the
      // arms are listed separately so the sealed union keeps that disjointness
      // a COMPILE error to break rather than a comment to forget.
      case IssueOpened() || PullRequestOpened():
        return;
      case WorkflowRunConcluded():
        return;
      // A watched OUTBOUND issue is not a session check either: it carries no
      // `grid/` head branch, no rework round and no landing. It belongs to the
      // issue-watch leg, and the arms stay listed separately so the sealed
      // union keeps that disjointness a COMPILE error to break.
      case IssueCommented() || WatchedIssueStateChanged():
        return;
      // The LEGACY per-check envelope. Nothing emits it any more, but a cursor
      // written before the feedback poll changed shape can still REPLAY one,
      // and it carries neither approved reference — only a head branch, which
      // is exactly what stopped being an attribution. It is reported and
      // acknowledged rather than acted on.
      case CheckConcluded():
        _flare(
          kCiFeedbackIgnoredFlare,
          'ignored a legacy check envelope on ${event.headBranch}',
          'a checkConcluded observation states no pull-request reference',
        );
        return;
      case PullRequestFeedback():
        await _projectPullFeedback(event);
    }
  }

  /// The bead [event] is attributed to, or null once it has been REPORTED.
  ///
  /// One `Refs:` trailer wins outright and costs no read. With no trailer the
  /// pull's own number is looked up as bd's existing `gh-<number>` external
  /// ref. Anything ambiguous — two distinct trailers, or zero/many beads
  /// carrying the ref — is an event with no subject, so it degrades to
  /// [kCiFeedbackUnattributedFlare] and mutates nothing.
  Future<String?> _attribute(PullRequestFeedback event) async {
    final references = pullRequestBodyBeadReferences(event.body);
    if (references.length > 1) {
      _unattributed(
        event,
        'its body states ${references.length} distinct Refs: trailers '
        '(${references.join(', ')})',
      );
      return null;
    }
    if (references.length == 1) return references.single;
    final externalRef = 'gh-${event.number}';
    final matched = await _store.listScope(
      externalRef: externalRef,
      includeClosed: true,
    );
    final ids = <String>[
      for (final bead in matched.beads)
        if (bead.id.trim().isNotEmpty) bead.id.trim(),
    ];
    if (ids.length != 1) {
      _unattributed(
        event,
        'its body states no Refs: trailer and ${ids.length} beads carry '
        'external ref $externalRef',
      );
      return null;
    }
    return ids.single;
  }

  Future<void> _projectPullFeedback(PullRequestFeedback event) async {
    final beadId = await _attribute(event);
    if (beadId == null) return;
    // ONE type-scoped read per projected observation, widened past bd's
    // open-only default so a closed session still counts. The filtering happens
    // HERE, in Dart, and never as a `work_bead` metadata equality the store
    // would apply: the rework ledger `maxReworkRound` counts is the RETIRED
    // `<bead>#r<N>` keys, and an exact match would drop exactly those.
    final sessions = await _store.listScope(
      type: GridIssueTypes.session,
      includeClosed: true,
    );
    final workBeadKeys = <String>[];
    final current = <Bead>[];
    for (final session in sessions.beads) {
      final workBead = session.metadata['work_bead'];
      if (workBead is! String) continue;
      workBeadKeys.add(workBead);
      if (workBead == beadId) current.add(session);
    }
    if (current.length != 1) {
      _ignore(
        beadId,
        'expected exactly one current session; found ${current.length}',
      );
      return;
    }
    final sessionId = current.single.id.trim();
    if (sessionId.isEmpty) {
      _ignore(beadId, 'its current session carries no id');
      return;
    }
    final decision = decideCiFeedback(
      beadId: beadId,
      sessionId: sessionId,
      workBeadKeys: workBeadKeys,
      // The HEAD and its state, never the observation id: a pull's
      // `updated_at` moves on every comment, and keying the rework ledger off
      // that would mint a second round for one unchanged red. It also makes the
      // stall crossing a no-op here — same head, same state, same key — which
      // is exactly the "observation only" the bound promises.
      feedbackIdentity: '${event.headSha}:${event.checkState.name}',
      checkState: event.checkState,
    );
    if (decision.action == CiFeedbackAction.ignore) return;
    if (!_handled.add(decision.idempotencyKey)) return;
    try {
      switch (decision.action) {
        case CiFeedbackAction.ignore:
          return;
        case CiFeedbackAction.landingReady:
          await _markLandingReady(decision);
          return;
        case CiFeedbackAction.gate:
          await createCapGate(decision, event);
          return;
        case CiFeedbackAction.rework:
          final result = await commandSender.rework(
            gridRoot: gridRoot,
            beadId: decision.beadId,
            note:
                'Pull request #${event.number} on ${event.headBranch} '
                '(${event.headSha}) is failing its checks.',
            idempotencyKey: decision.idempotencyKey,
          );
          switch (result) {
            case FeedbackCommandCompleted():
              return;
            case FeedbackCommandRefused(code: 'rework_round_cap'):
              await createCapGate(decision, event);
              return;
            case FeedbackCommandRefused():
              throw StateError(
                'resident rework refused (${result.code}): ${result.message}',
              );
          }
      }
    } catch (_) {
      _handled.remove(decision.idempotencyKey);
      rethrow;
    }
  }

  /// Flares that [beadId]'s feedback was ignored for [reason], and returns.
  ///
  /// A session count of zero or of two is a shape the state store LEGITIMATELY
  /// holds — feedback arriving after its PR landed and its session closed and
  /// re-keyed is the ordinary case — so it can never be a throw. Throwing here
  /// wedged the reconciler permanently: the leg never acknowledged, the cycle
  /// aborted before the poll, and the seat re-drove that one observation
  /// forever while every newer issue, pull and check went unobserved.
  void _ignore(String beadId, String reason) => _flare(
    kCiFeedbackIgnoredFlare,
    'ignored feedback for $beadId',
    'CI feedback ignored for $beadId: $reason',
  );

  /// Flares that [beadId] could not be marked landing-ready, for [detail], and
  /// returns.
  ///
  /// The message names all three facts a human needs to tell a lost landing
  /// mark from a mis-scoped seat: the bead, the store root that was attempted,
  /// and what that store said.
  void _landingUnresolved(String beadId, String detail) => _flare(
    kCiFeedbackLandingUnresolvedFlare,
    'left $beadId unmarked after a landing-ready decision',
    'landing-ready mutation for $beadId could not be resolved in the work '
        'store at ${scope.root}: $detail',
  );

  /// Flares that [event] names no bead, for [reason], and returns.
  void _unattributed(PullRequestFeedback event, String reason) => _flare(
    kCiFeedbackUnattributedFlare,
    'reported an unattributed pull request #${event.number}',
    'pull request #${event.number} on ${event.repository} could not be '
        'attributed: $reason',
  );

  /// Reports [message] under [flareName] on the bound rail, if there is one.
  void _flare(String flareName, String action, String message) => _reporter
      ?.call(flareName, action, StateError(message), StackTrace.current);

  /// Marks [decision]'s work bead landing-ready in [scope]'s OWN store.
  ///
  /// A bead this scope does not own, and a bead its store cannot resolve, are
  /// both FLARED and returned from — never thrown. Returning normally leaves
  /// [CiFeedbackDecision.idempotencyKey] in `_handled`, so the flare fires once
  /// per decision rather than once per cycle, and the cycle reaches its poll.
  Future<void> _markLandingReady(CiFeedbackDecision decision) async {
    if (!_ownership.ownsTarget(id: decision.beadId)) {
      _landingUnresolved(
        decision.beadId,
        'its id prefix is not owned by substation ${scope.name} '
        '(prefix ${scope.prefix})',
      );
      return;
    }
    final result = await workBd.run([
      'update',
      decision.beadId,
      '--actor',
      'github-feedback',
      '--set-metadata',
      'grid.landing_ready=true',
    ]);
    if (!result.ok) {
      _landingUnresolved(decision.beadId, result.stderr);
    }
  }

  /// Flares that [beadId]'s ci-rework cap gate could not be minted, for
  /// [detail], and returns.
  ///
  /// Names the bead, the store that was written (the grid STATE store, never
  /// the work store) and what that store said, so a human can tell a lost gate
  /// from a mis-composed seat.
  void _capGateUnresolved(String beadId, String detail) => _flare(
    kCiFeedbackCapGateUnresolvedFlare,
    'left $beadId ungated after a rework-cap decision',
    'ci-rework cap gate for $beadId could not be minted in the grid state '
        'store: $detail',
  );

  /// Mints [decision]'s ci-rework cap gate in the grid STATE store, or refreshes
  /// the one already open, and NEVER throws.
  ///
  /// THE ID IS THE STORE'S. The gate used to be created as
  /// `--id <workBead>-ci-rework-cap`, which carries the WORK bead's prefix into
  /// a store that mints its own: bd refuses every such create with `prefix
  /// mismatch: database uses 'tranquility-' but ID 'tg-…-ci-rework-cap' doesn't
  /// match (use --force to override)`. `--force` is NOT the fix — it would
  /// write a foreign-prefixed id into the state store. The gate is minted the
  /// way every engine gate and session bead is minted: `bd create -t gate` with
  /// no `--id`, so the state store stamps its own prefix, and the work bead
  /// rides in the title and in metadata (`work_bead`, and `node` as
  /// `<bead>/ci-feedback`) exactly as a session bead carries its `work_bead`.
  ///
  /// DEDUP IS A READ, NOT A COLLISION, AND IT IS PER WORK BEAD. With no fixed
  /// id there is no `already exists` to lean on, so this probes the state store
  /// for an OPEN cap gate at the work bead's own [ciReworkCapGateNode] first and
  /// refreshes it instead of piling up a duplicate. The key is the WORK BEAD,
  /// exactly as the retired `<beadId>-ci-rework-cap` id keyed it — never the
  /// session: a re-keyed or superseded session on the same capped bead meets
  /// the gate its predecessor left and refreshes THAT one, so one capped bead
  /// holds at most one open cap gate. The refresh also re-points the gate's
  /// `blocks` at the CURRENT session, because the engine's join resolves a
  /// gate to its work bead only through the session that bead currently maps
  /// to; a gate still blocking a superseded session would be open yet unseen.
  /// The probe is best-effort: a read error falls through to a fresh mint,
  /// because a duplicate gate is inert and a missing one is not.
  ///
  /// A WRITE FAILURE IS ONE BEAD'S. It is flared under
  /// [kCiFeedbackCapGateUnresolvedFlare] and returned from, never thrown, so
  /// the delivery leg acknowledges the observation and the cycle reaches its
  /// poll and every other bead's feedback. The decision's idempotency key is
  /// released on failure, which is what lets a LATER, DISTINCT observation of
  /// the same red head retry the mint. That is all it guarantees: the
  /// acknowledged observation is never re-driven, and the reconciler
  /// deduplicates observations by id — built from the pull's head, check
  /// state, `updated_at` and mergeability — so an UNCHANGED red pull produces
  /// no new observation and its refused gate stays unminted, reported by the
  /// one flare, until something about that pull moves.
  Future<void> createCapGate(
    CiFeedbackDecision decision,
    PullRequestFeedback event,
  ) async {
    final beadId = decision.beadId;
    final node = ciReworkCapGateNode(beadId);
    final reason =
        'CI rework cap reached after ${decision.round} retired rounds; '
        'pull request #${event.number} (${event.headSha}) is '
        '${event.checkState.name} and requires adjudication.';
    final existing = await _findOpenCapGate(beadId: beadId, node: node);
    final BdResult result;
    if (existing != null) {
      result = await bd.run([
        'update',
        existing.id.trim(),
        '--actor',
        'github-feedback',
        '--set-metadata',
        'blocks=${decision.sessionId}',
        '--set-metadata',
        'reason=$reason',
      ]);
    } else {
      result = await bd.run([
        'create',
        '--actor',
        'github-feedback',
        '--title',
        'CI rework cap reached for $beadId',
        '--type',
        'gate',
        '--metadata',
        jsonEncode({
          'rig': substation,
          'blocks': decision.sessionId,
          'node': node,
          'work_bead': beadId,
          'reason': reason,
        }),
      ]);
    }
    if (result.ok) return;
    _handled.remove(decision.idempotencyKey);
    _capGateUnresolved(beadId, result.stderr);
  }

  /// The OPEN ci-rework cap gate in the state store for work bead [beadId] —
  /// the `type=gate` bead at [node] — whichever session it blocks, or null
  /// when there is none or the probe could not read.
  ///
  /// The store is asked with a type scope AND the `node` equality; the match is
  /// then re-checked HERE, because a store that ignored a filter would
  /// otherwise hand back a foreign gate to refresh. A gate that states a
  /// `work_bead` must state [beadId]; one that states none is matched on its
  /// bead-derived [node] alone.
  Future<Bead?> _findOpenCapGate({
    required String beadId,
    required String node,
  }) async {
    final ({List<Bead> beads, List<BeadDependency> dependencies}) listed;
    try {
      listed = await _store.listScope(
        type: GridIssueTypes.gate,
        metadataFields: <String, String>{'node': node},
      );
    } on Object {
      return null;
    }
    for (final bead in listed.beads) {
      if (bead.issueType != GridIssueTypes.gate) continue;
      if (bead.isClosed) continue;
      if (bead.metadata['node'] != node) continue;
      final workBead = bead.metadata['work_bead'];
      if (workBead != null && workBead != beadId) continue;
      if (bead.id.trim().isEmpty) continue;
      return bead;
    }
    return null;
  }
}
