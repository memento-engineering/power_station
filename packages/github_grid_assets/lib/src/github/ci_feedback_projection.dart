import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';

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

/// Projects normalized check results into the durable bead/control rails.
final class CiFeedbackProjection {
  CiFeedbackProjection({
    required this.bd,
    required this.commandSender,
    required this.gridRoot,
    required this.substation,
  });

  final BdRunner bd;
  final FeedbackCommandSender commandSender;
  final String gridRoot;
  final String substation;
  final Set<String> _handled = <String>{};

  Future<void> call(NormalizedGitHubEvent event) async {
    switch (event) {
      case IssueOpened() || PullRequestOpened():
        return;
      case CheckConcluded():
        await _projectCheck(event);
    }
  }

  Future<void> _projectCheck(CheckConcluded event) async {
    if (!event.headBranch.startsWith('grid/')) return;
    final records = await _exportAll();
    final workKeys = <String>[];
    final current = <Map<String, Object?>>[];
    final beadId = event.headBranch.substring('grid/'.length).trim();
    if (beadId.isEmpty) return;
    for (final record in records) {
      if (record['issue_type'] != 'session') continue;
      final metadata = _metadata(record);
      final workBead = metadata['work_bead'];
      if (workBead is String) {
        workKeys.add(workBead);
        if (workBead == beadId) current.add(record);
      }
    }
    if (current.length != 1) {
      throw StateError(
        'expected exactly one current session for $beadId; '
        'found ${current.length}',
      );
    }
    final sessionId = current.single['id'];
    if (sessionId is! String || sessionId.isEmpty) {
      throw StateError('current session for $beadId has no string id');
    }
    final decision = decideCiFeedback(event, sessionId, workKeys);
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

  Future<List<Map<String, Object?>>> _exportAll() async {
    final result = await bd.run(const ['export', '--all']);
    if (!result.ok) {
      throw StateError('bd export --all failed: ${result.stderr}');
    }
    try {
      Object? decoded;
      try {
        decoded = jsonDecode(result.stdout);
      } on FormatException {
        decoded = const LineSplitter()
            .convert(result.stdout)
            .where((line) => line.trim().isNotEmpty)
            .map(jsonDecode)
            .toList(growable: false);
      }
      if (decoded is Map && decoded.containsKey('data')) {
        decoded = decoded['data'];
      } else if (decoded is Map) {
        decoded = [decoded];
      }
      if (decoded is! List) throw const FormatException('export is not a list');
      return decoded
          .map((item) {
            if (item is! Map) {
              throw const FormatException('bead is not an object');
            }
            return item.cast<String, Object?>();
          })
          .toList(growable: false);
    } on Object catch (error) {
      throw StateError('malformed bd export --all output: $error');
    }
  }

  Map<String, Object?> _metadata(Map<String, Object?> record) {
    final raw = record['metadata'];
    if (raw == null) return const {};
    if (raw is Map) return raw.cast<String, Object?>();
    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, Object?>();
    }
    throw const FormatException('bead metadata is malformed');
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
