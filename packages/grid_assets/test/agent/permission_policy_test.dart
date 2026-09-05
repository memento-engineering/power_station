// The STATION's authorization boundary for agent channels: pure values in,
// one decision out. Every arm here is offline — no process, no protocol.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

const String _attempt = 'attempt-live';
const String _session = 'acp-session-live';

AgentPermissionRequest _request({
  String requestId = 'req-1',
  String attemptId = _attempt,
  String sessionId = _session,
  AgentPermissionCapability capability = AgentPermissionCapability.edit,
  List<AgentPermissionOutcome> offered = const <AgentPermissionOutcome>[
    AgentPermissionOutcome.rejectOnce,
    AgentPermissionOutcome.rejectAlways,
    AgentPermissionOutcome.allowOnce,
    AgentPermissionOutcome.allowAlways,
  ],
}) => AgentPermissionRequest(
  requestId: requestId,
  attemptId: attemptId,
  sessionId: sessionId,
  capability: capability,
  offered: offered,
);

AgentPermissionDecision _decide({
  required AgentPermissionPolicy policy,
  AgentPermissionRequest? request,
  String admittedAttemptId = _attempt,
  String? boundSessionId = _session,
  bool audited = true,
}) => decideAgentPermission(
  policy: policy,
  request: request ?? _request(),
  admittedAttemptId: admittedAttemptId,
  boundSessionId: boundSessionId,
  audited: audited,
);

const AgentPermissionPolicy _editOnce = AgentPermissionPolicy.scoped(
  id: 'station-edit-once',
  grants: <AgentPermissionCapability, AgentPermissionGrant>{
    AgentPermissionCapability.edit: AgentPermissionGrant.allowOnce,
    AgentPermissionCapability.read: AgentPermissionGrant.allowAlways,
    AgentPermissionCapability.delete: AgentPermissionGrant.deny,
  },
);

String _source(String relative) {
  final local = File(relative);
  if (local.existsSync()) return local.readAsStringSync();
  return File('packages/grid_assets/$relative').readAsStringSync();
}

void main() {
  test('unknown unavailable stale and unaudited requests fail closed', () {
    // No policy at all — the DEFAULT posture.
    final unavailable = _decide(
      policy: const AgentPermissionPolicy.unavailable(),
    );
    expect(unavailable.outcome, AgentPermissionOutcome.rejectOnce);
    expect(unavailable.grants, isFalse);
    expect(unavailable.policyId, isEmpty);

    // A policy that cannot be NAMED cannot authorize: an unnameable grant is
    // unauditable, and this seam exists to make grants auditable.
    expect(
      _decide(
        policy: const AgentPermissionPolicy.scoped(
          id: '   ',
          grants: <AgentPermissionCapability, AgentPermissionGrant>{
            AgentPermissionCapability.edit: AgentPermissionGrant.allowAlways,
          },
        ),
      ).grants,
      isFalse,
    );

    // An UNKNOWN capability is refused even by the trusted-headless posture.
    const trusted = AgentPermissionPolicy.trustedHeadless(id: 'headless');
    expect(
      _decide(
        policy: trusted,
        request: _request(capability: AgentPermissionCapability.unknown),
      ).outcome,
      AgentPermissionOutcome.rejectOnce,
    );

    // STALE identities: no admitted attempt, the wrong attempt, no bound
    // session, a superseded session. None of them reaches the policy.
    for (final stale in <AgentPermissionDecision>[
      _decide(policy: trusted, admittedAttemptId: ''),
      _decide(policy: trusted, admittedAttemptId: '   '),
      _decide(
        policy: trusted,
        request: _request(attemptId: 'attempt-old'),
      ),
      _decide(policy: trusted, boundSessionId: null),
      _decide(policy: trusted, boundSessionId: ''),
      _decide(
        policy: trusted,
        request: _request(sessionId: 'acp-old'),
      ),
    ]) {
      expect(stale.grants, isFalse, reason: stale.reason);
      expect(stale.outcome, AgentPermissionOutcome.rejectOnce);
    }

    // NO DURABLE RECORD, no grant: without an audit carrier there is no such
    // thing as a recorded authorization, so there is no authorization.
    final unaudited = _decide(policy: trusted, audited: false);
    expect(unaudited.grants, isFalse);
    expect(unaudited.reason, contains('durable authorization record'));

    // A refusal takes the NARROWEST refusal on offer, and cancels when the
    // harness offers no refusal at all — never a grant.
    expect(
      _decide(
        policy: const AgentPermissionPolicy.unavailable(),
        request: _request(
          offered: const <AgentPermissionOutcome>[
            AgentPermissionOutcome.rejectAlways,
            AgentPermissionOutcome.allowAlways,
          ],
        ),
      ).outcome,
      AgentPermissionOutcome.rejectAlways,
    );
    expect(
      _decide(
        policy: const AgentPermissionPolicy.unavailable(),
        request: _request(
          offered: const <AgentPermissionOutcome>[
            AgentPermissionOutcome.allowOnce,
            AgentPermissionOutcome.allowAlways,
          ],
        ),
      ).outcome,
      AgentPermissionOutcome.cancelled,
    );
  });

  test('policy allows only explicit capability scope', () {
    // The listed capability, at exactly its configured scope.
    final once = _decide(policy: _editOnce);
    expect(once.outcome, AgentPermissionOutcome.allowOnce);
    expect(once.policyId, 'station-edit-once');

    // An allow-once rule is NEVER widened: with only the durable answer on
    // offer it cancels rather than upgrading itself.
    expect(
      _decide(
        policy: _editOnce,
        request: _request(
          offered: const <AgentPermissionOutcome>[
            AgentPermissionOutcome.allowAlways,
          ],
        ),
      ).outcome,
      AgentPermissionOutcome.cancelled,
    );

    // A durable rule takes the durable answer, and NARROWS to one-shot when
    // that is all the harness offers.
    expect(
      _decide(
        policy: _editOnce,
        request: _request(capability: AgentPermissionCapability.read),
      ).outcome,
      AgentPermissionOutcome.allowAlways,
    );
    expect(
      _decide(
        policy: _editOnce,
        request: _request(
          capability: AgentPermissionCapability.read,
          offered: const <AgentPermissionOutcome>[
            AgentPermissionOutcome.rejectOnce,
            AgentPermissionOutcome.allowOnce,
          ],
        ),
      ).outcome,
      AgentPermissionOutcome.allowOnce,
    );

    // An explicitly denied capability and an UNLISTED one are the same answer.
    for (final capability in <AgentPermissionCapability>[
      AgentPermissionCapability.delete,
      AgentPermissionCapability.execute,
      AgentPermissionCapability.fetch,
    ]) {
      final refused = _decide(
        policy: _editOnce,
        request: _request(capability: capability),
      );
      expect(refused.grants, isFalse, reason: capability.name);
      expect(refused.reason, contains('station-edit-once'));
    }

    // The trusted-headless posture is reachable ONLY by explicit
    // configuration, and then it is durable for every NAMED capability.
    const trusted = AgentPermissionPolicy.trustedHeadless(id: 'headless');
    for (final capability in AgentPermissionCapability.values) {
      final decision = _decide(
        policy: trusted,
        request: _request(capability: capability),
      );
      expect(
        decision.outcome,
        capability == AgentPermissionCapability.unknown
            ? AgentPermissionOutcome.rejectOnce
            : AgentPermissionOutcome.allowAlways,
        reason: capability.name,
      );
    }
    expect(
      const AgentPermissionPolicy.unavailable().isTrustedHeadless,
      isFalse,
    );
    expect(_editOnce.isTrustedHeadless, isFalse);
  });

  test('policy has no role axis and reserves the admission fence seam', () {
    // ADR-0006 D5 retired the role indirection and nothing at this seam
    // replaces it: the bind is attempt + protocol session + capability. The
    // model TIER is a spend axis and has no business in an authorization.
    for (final relative in const <String>[
      'lib/src/agent/permission_policy.dart',
      'lib/src/agent/acp_session_adapter.dart',
      'lib/src/agent/acp_bridge.dart',
      // The RESOLVER too: the seat rung is where a role indirection would be
      // most tempting to re-introduce, and it is the one place the derived
      // trusted-headless posture is minted.
      'lib/src/agent/seat_environments.dart',
    ]) {
      final source = _source(relative);
      expect(source, isNot(contains('AgentRole')), reason: relative);
      expect(source, isNot(contains('AgentTier')), reason: relative);
      expect(source, isNot(contains('ModelTiers')), reason: relative);
    }

    // The FENCE is deferred, not invented: Stage 3 (`tg-lt0s`) adds it to both
    // records and to the exact-match guard. Until then neither record carries
    // one, and the seam is documented where it will land.
    final policySource = _source('lib/src/agent/permission_policy.dart');
    expect(policySource, contains('tg-lt0s'));
    expect(policySource, isNot(contains('fence:')));
    expect(policySource, isNot(contains('.instanceFence')));

    // The wire forms carry identity, not a fence and not a role.
    const request = AgentPermissionRequest(
      requestId: 'req-1',
      attemptId: _attempt,
      sessionId: _session,
      capability: AgentPermissionCapability.execute,
      offered: <AgentPermissionOutcome>[AgentPermissionOutcome.allowOnce],
    );
    expect(request.toJson().keys, <String>[
      'requestId',
      'attemptId',
      'sessionId',
      'capability',
      'offered',
    ]);
    final decision = _decide(
      policy: const AgentPermissionPolicy.trustedHeadless(id: 'headless'),
      request: request,
    );
    expect(decision.toJson().keys, <String>[
      'requestId',
      'attemptId',
      'sessionId',
      'capability',
      'policyId',
      'outcome',
      'reason',
    ]);

    // Both wire forms ROUND-TRIP, so a decision cannot be widened in transit.
    final decoded = AgentPermissionDecision.fromJson(decision.toJson());
    expect(decoded.outcome, decision.outcome);
    expect(decoded.capability, AgentPermissionCapability.execute);
    final decodedRequest = AgentPermissionRequest.fromJson(request.toJson());
    expect(decodedRequest.offered, request.offered);
    // An unrecognized capability decodes to the non-grantable sentinel rather
    // than throwing — a harness that invents a kind is refused, not crashed.
    expect(
      AgentPermissionRequest.fromJson(<String, Object?>{
        ...request.toJson(),
        'capability': 'teleport',
      }).capability,
      AgentPermissionCapability.unknown,
    );
  });

  test('audit projections are redacted identity only', () {
    const request = AgentPermissionRequest(
      requestId: 'req-9',
      attemptId: _attempt,
      sessionId: _session,
      capability: AgentPermissionCapability.execute,
      offered: <AgentPermissionOutcome>[
        AgentPermissionOutcome.rejectOnce,
        AgentPermissionOutcome.allowOnce,
      ],
    );
    expect(request.auditFields(channelSessionId: 'sess/work-1/agent'), {
      'channelSessionId': 'sess/work-1/agent',
      'requestId': 'req-9',
      'attemptId': _attempt,
      'protocolSessionId': _session,
      'capability': 'execute',
    });

    final decision = _decide(policy: _editOnce, request: request);
    expect(decision.auditFields(channelSessionId: 'sess/work-1/agent'), {
      'channelSessionId': 'sess/work-1/agent',
      'requestId': 'req-9',
      'attemptId': _attempt,
      'protocolSessionId': _session,
      'capability': 'execute',
      'policyId': 'station-edit-once',
      'outcome': 'rejectOnce',
      'reason': isA<String>(),
    });
  });
}
