import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart' show GridIssueTypes;

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

/// The flare name carried by a check this leg declined to act on.
const String kCiFeedbackIgnoredFlare = 'reconciler.ciFeedbackIgnored';

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

/// Projects normalized check results into the durable bead/control rails.
final class CiFeedbackProjection {
  CiFeedbackProjection({
    required this.bd,
    required this.commandSender,
    required this.gridRoot,
    required this.substation,
  }) : _store = BdCliService(bd);

  final BdRunner bd;
  final FeedbackCommandSender commandSender;
  final String gridRoot;
  final String substation;

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
      case CheckConcluded():
        await _projectCheck(event);
    }
  }

  Future<void> _projectCheck(CheckConcluded event) async {
    if (!event.headBranch.startsWith('grid/')) return;
    final beadId = event.headBranch.substring('grid/'.length).trim();
    if (beadId.isEmpty) return;
    // ONE type-scoped read per projected check, widened past bd's open-only
    // default so a closed session still counts. The filtering happens HERE, in
    // Dart, and never as a `work_bead` metadata equality the store would apply:
    // the rework ledger `maxReworkRound` counts is the RETIRED `<bead>#r<N>`
    // keys, and an exact match would drop exactly those.
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
    final decision = decideCiFeedback(event, sessionId, workBeadKeys);
    if (decision == null || decision.action == CiFeedbackAction.ignore) return;
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
                'CI check ${event.checkName} (${event.observationId}) '
                'concluded ${event.conclusion}.',
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

  /// Flares that [beadId]'s check was ignored for [reason], and returns.
  ///
  /// A session count of zero or of two is a shape the state store LEGITIMATELY
  /// holds — a check arriving after its PR landed and its session closed and
  /// re-keyed is the ordinary case — so it can never be a throw. Throwing here
  /// wedged the reconciler permanently: the leg never acknowledged, the cycle
  /// aborted before the poll, and the seat re-drove that one observation
  /// forever while every newer issue, pull and check went unobserved.
  void _ignore(String beadId, String reason) {
    _reporter?.call(
      kCiFeedbackIgnoredFlare,
      'ignored a check for $beadId',
      StateError('CI feedback ignored for $beadId: $reason'),
      StackTrace.current,
    );
  }

  Future<void> _markLandingReady(CiFeedbackDecision decision) async {
    final result = await bd.run([
      'update',
      decision.beadId,
      '--actor',
      'github-feedback',
      '--set-metadata',
      'grid.landing_ready=true',
    ]);
    if (!result.ok) {
      throw StateError('landing-ready mutation failed: ${result.stderr}');
    }
  }

  Future<void> createCapGate(
    CiFeedbackDecision decision,
    CheckConcluded event,
  ) async {
    final result = await bd.run([
      'create',
      '--actor',
      'github-feedback',
      '--id',
      '${decision.beadId}-ci-rework-cap',
      '--title',
      'CI rework cap reached for ${decision.beadId}',
      '--type',
      'gate',
      '--metadata',
      jsonEncode({
        'rig': substation,
        'blocks': decision.sessionId,
        'node': '${decision.beadId}/ci-feedback',
        'reason':
            'CI rework cap reached after ${decision.round} retired rounds; '
            'check ${event.checkName} (${event.observationId}) requires '
            'adjudication.',
      }),
    ]);
    if (result.ok || _alreadyExists(result, decision.beadId)) return;
    throw StateError('cap gate mutation failed: ${result.stderr}');
  }

  bool _alreadyExists(BdResult result, String beadId) {
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    final gateId = '$beadId-ci-rework-cap'.toLowerCase();
    return output.contains(gateId) &&
        (output.contains('already exists') ||
            output.contains('issue_already_exists'));
  }
}
