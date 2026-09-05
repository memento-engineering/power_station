/// The STATION's authorization boundary for a long-lived agent channel.
///
/// A channel harness asks its client for permission mid-turn — to edit a file,
/// run a command, fetch a URL — and the answer can be DURABLE ("allow always"),
/// outliving the request that provoked it. Before this seam the grid answered
/// every such ask with the widest grant on offer, so an agent acquired whatever
/// standing permission it asked for, independently of the bead approval and the
/// admission authority that let it run at all.
///
/// This library is the protocol-neutral vocabulary that replaces that blanket
/// answer. It is pure: values in, one [AgentPermissionDecision] out, no IO and
/// no protocol types. The ACP wire lives in `acp_session_adapter.dart`, the
/// channel plumbing in `agent_session.dart`, and the station configuration is a
/// VALUE mounted by `HarnessProvider` (ADR-0008: config = values in the tree).
///
/// **Fail closed.** Every unknown — no policy, an unrecognized capability, an
/// unadmitted attempt, an unbound or stale protocol session, no durable audit
/// carrier — refuses. A grant happens only when a station explicitly configured
/// one for exactly that capability.
library;

/// The protocol-neutral kind of action one permission request asks for.
///
/// These are the categories a harness classifies its own tool calls into; the
/// adapter that speaks a wire protocol normalizes onto them. Anything the
/// adapter cannot classify — including a request that names no kind at all —
/// normalizes to [unknown], which is never grantable.
enum AgentPermissionCapability {
  /// Reads or otherwise accesses data without modifying it.
  read,

  /// Modifies existing files or data.
  edit,

  /// Removes files or data.
  delete,

  /// Relocates files or data.
  move,

  /// Searches for information.
  search,

  /// Executes a command or runs a process.
  execute,

  /// Performs internal reasoning.
  think,

  /// Retrieves data from an external source.
  fetch,

  /// Changes the harness's operational mode.
  switchMode,

  /// The NON-GRANTABLE sentinel: an unclassified or unrecognized capability.
  ///
  /// A station cannot configure a grant for it — [AgentPermissionPolicy] denies
  /// it whatever it was asked to allow — because an unnamed action cannot be
  /// scoped, and an unscoped durable grant is the exact hole this seam closes.
  unknown,
}

/// The widest scope a station's policy is willing to give one capability.
enum AgentPermissionGrant {
  /// No scope at all: the request is refused.
  deny,

  /// One-shot: this request only, never a standing permission.
  allowOnce,

  /// Durable: a standing permission the harness may reuse this session.
  allowAlways,
}

/// The answer actually returned to the harness for one permission request.
///
/// The four non-[cancelled] members are the answers a harness OFFERS; a request
/// carries whichever subset it supports. [cancelled] is never offered — it is
/// what the grid falls back to when no offered answer is compliant, and it is
/// always non-granting.
enum AgentPermissionOutcome {
  /// Refuse this request.
  rejectOnce,

  /// Refuse this request and every later one like it.
  rejectAlways,

  /// Allow this request only.
  allowOnce,

  /// Allow this request and later ones like it.
  allowAlways,

  /// Answer nothing: the request is abandoned without an authorization.
  cancelled,
}

/// The station's authorization configuration for agent channels — a VALUE.
///
/// Mounted by `HarnessProvider` as `InheritedSeed<AgentPermissionPolicy>` and
/// read at a capability's effect edge, never cached. A nested provider shadows
/// it by exact type, so a substation can narrow (or widen) its own subtree.
///
/// [AgentPermissionPolicy.unavailable] is the default and the safe floor: it
/// grants nothing. A station opts in per capability with
/// [AgentPermissionPolicy.scoped], or reinstates the whole pre-boundary
/// posture — explicitly, and only explicitly — with
/// [AgentPermissionPolicy.trustedHeadless].
class AgentPermissionPolicy {
  /// The default: no policy is in effect, so nothing is authorized.
  const AgentPermissionPolicy.unavailable()
    : id = '',
      grants = const <AgentPermissionCapability, AgentPermissionGrant>{},
      isTrustedHeadless = false;

  /// A policy identified by [id] that grants exactly the capabilities named in
  /// [grants], each to at most the scope its entry names.
  ///
  /// A capability with no entry is denied. A blank [id] makes the whole policy
  /// non-granting: an authorization record whose policy cannot be named is not
  /// auditable, and an unauditable grant is not a grant.
  const AgentPermissionPolicy.scoped({required this.id, required this.grants})
    : isTrustedHeadless = false;

  /// The pre-boundary posture, reachable ONLY by explicit configuration: every
  /// NAMED capability may be granted durably.
  ///
  /// [AgentPermissionCapability.unknown] stays refused even here — a trusted
  /// station still cannot authorize an action nobody can name.
  const AgentPermissionPolicy.trustedHeadless({required this.id})
    : grants = const <AgentPermissionCapability, AgentPermissionGrant>{},
      isTrustedHeadless = true;

  /// The station's name for this policy, stamped onto every decision it makes.
  /// Blank ⇒ non-granting.
  final String id;

  /// The per-capability scope ceiling. Absent ⇒ [AgentPermissionGrant.deny].
  final Map<AgentPermissionCapability, AgentPermissionGrant> grants;

  /// Whether this is the explicitly configured trusted-headless posture.
  final bool isTrustedHeadless;

  /// The widest scope this policy allows for [capability].
  ///
  /// Denies for a blank [id] and for [AgentPermissionCapability.unknown], both
  /// unconditionally.
  AgentPermissionGrant grantFor(AgentPermissionCapability capability) {
    if (id.trim().isEmpty) return AgentPermissionGrant.deny;
    if (capability == AgentPermissionCapability.unknown) {
      return AgentPermissionGrant.deny;
    }
    if (isTrustedHeadless) return AgentPermissionGrant.allowAlways;
    return grants[capability] ?? AgentPermissionGrant.deny;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AgentPermissionPolicy) return false;
    if (other.id != id || other.isTrustedHeadless != isTrustedHeadless) {
      return false;
    }
    if (other.grants.length != grants.length) return false;
    for (final entry in grants.entries) {
      if (other.grants[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    isTrustedHeadless,
    Object.hashAllUnordered(
      grants.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() => isTrustedHeadless
      ? 'AgentPermissionPolicy.trustedHeadless($id)'
      : id.isEmpty
      ? 'AgentPermissionPolicy.unavailable()'
      : 'AgentPermissionPolicy.scoped($id, ${grants.length} capabilities)';
}

/// One harness permission ask, normalized off the wire.
///
/// It carries only IDENTITY and SHAPE: which bridge-local request it is, which
/// admitted attempt and protocol session it arose under, what kind of action it
/// wants, and which answers the harness will accept. Everything a harness sends
/// alongside — the tool title, its raw input and output, its metadata, the
/// option labels — is dropped by the adapter and never reaches this record, so
/// an authorization audit can never leak the work.
///
/// **Deferred fence (Stage 3, the_grid bead `tg-lt0s`).** The Stage 3 admission
/// grant introduces a fencing token; when it lands, that token becomes a field
/// on this record and on [AgentPermissionDecision], and joins the exact-match
/// guard in [decideAgentPermission] beside the attempt and the session. No
/// fence exists at this seam today and none is invented here.
class AgentPermissionRequest {
  /// Creates a normalized permission ask.
  const AgentPermissionRequest({
    required this.requestId,
    required this.attemptId,
    required this.sessionId,
    required this.capability,
    required this.offered,
  });

  /// Decodes a request from its wire form.
  factory AgentPermissionRequest.fromJson(Map<String, Object?> json) =>
      AgentPermissionRequest(
        requestId: json['requestId']! as String,
        attemptId: json['attemptId']! as String,
        sessionId: json['sessionId']! as String,
        capability: _capabilityByName(json['capability']),
        offered: _outcomesByName(json['offered']),
      );

  /// The bridge-local id of this ask; a response must name it back exactly.
  final String requestId;

  /// The admitted attempt the asking incarnation was spawned under.
  final String attemptId;

  /// The harness protocol session the ask arose in.
  final String sessionId;

  /// The normalized kind of action asked for.
  final AgentPermissionCapability capability;

  /// The answers the harness offers, deduplicated and in wire order.
  final List<AgentPermissionOutcome> offered;

  /// Encodes this request for the private bridge wire.
  Map<String, Object?> toJson() => <String, Object?>{
    'requestId': requestId,
    'attemptId': attemptId,
    'sessionId': sessionId,
    'capability': capability.name,
    'offered': offered.map((outcome) => outcome.name).toList(growable: false),
  };

  /// The REDACTED audit projection: identities only, plus the caller's
  /// [channelSessionId] (the grid's own name for the supervised incarnation).
  Map<String, String> auditFields({required String channelSessionId}) =>
      <String, String>{
        'channelSessionId': channelSessionId,
        'requestId': requestId,
        'attemptId': attemptId,
        'protocolSessionId': sessionId,
        'capability': capability.name,
      };
}

/// The station's answer to one [AgentPermissionRequest] — the durable
/// authorization record.
///
/// It names the request it answers so a response can be matched exactly, the
/// policy that produced it so an operator can see WHICH configuration
/// authorized, and a reason so a refusal explains itself. Like the request, it
/// carries no harness content and reserves the Stage 3 (`tg-lt0s`) fence field.
class AgentPermissionDecision {
  /// Creates a decision.
  const AgentPermissionDecision({
    required this.requestId,
    required this.attemptId,
    required this.sessionId,
    required this.capability,
    required this.policyId,
    required this.outcome,
    required this.reason,
  });

  /// The non-granting answer for [request] when no authorization can be
  /// produced at all — the bridge-local fallback, and the shape every
  /// fail-closed path lands on.
  factory AgentPermissionDecision.cancelled({
    required AgentPermissionRequest request,
    required String policyId,
    required String reason,
  }) => AgentPermissionDecision(
    requestId: request.requestId,
    attemptId: request.attemptId,
    sessionId: request.sessionId,
    capability: request.capability,
    policyId: policyId,
    outcome: AgentPermissionOutcome.cancelled,
    reason: reason,
  );

  /// Decodes a decision from its wire form.
  factory AgentPermissionDecision.fromJson(Map<String, Object?> json) =>
      AgentPermissionDecision(
        requestId: json['requestId']! as String,
        attemptId: json['attemptId']! as String,
        sessionId: json['sessionId']! as String,
        capability: _capabilityByName(json['capability']),
        policyId: json['policyId']! as String,
        outcome: _outcomeByName(json['outcome']),
        reason: json['reason']! as String,
      );

  /// The [AgentPermissionRequest.requestId] this answers.
  final String requestId;

  /// The attempt identity carried through from the request.
  final String attemptId;

  /// The protocol session identity carried through from the request.
  final String sessionId;

  /// The normalized capability carried through from the request.
  final AgentPermissionCapability capability;

  /// The station policy that produced this answer; blank ⇒ no policy did.
  final String policyId;

  /// The answer itself.
  final AgentPermissionOutcome outcome;

  /// Why this answer, in the grid's own words — never the harness's.
  final String reason;

  /// Whether this decision authorizes anything at all.
  bool get grants =>
      outcome == AgentPermissionOutcome.allowOnce ||
      outcome == AgentPermissionOutcome.allowAlways;

  /// Encodes this decision for the private bridge wire.
  Map<String, Object?> toJson() => <String, Object?>{
    'requestId': requestId,
    'attemptId': attemptId,
    'sessionId': sessionId,
    'capability': capability.name,
    'policyId': policyId,
    'outcome': outcome.name,
    'reason': reason,
  };

  /// The REDACTED audit projection: the request identities, the deciding
  /// policy, the answer and its reason, plus the caller's [channelSessionId].
  Map<String, String> auditFields({required String channelSessionId}) =>
      <String, String>{
        'channelSessionId': channelSessionId,
        'requestId': requestId,
        'attemptId': attemptId,
        'protocolSessionId': sessionId,
        'capability': capability.name,
        'policyId': policyId,
        'outcome': outcome.name,
        'reason': reason,
      };
}

/// Decides ONE permission request against the station's [policy] — the whole
/// authorization rule, pure and total.
///
/// [admittedAttemptId] is the attempt the supervised incarnation was actually
/// admitted under and [boundSessionId] is the protocol session currently bound
/// to it (null before a binding, and rebound on reconnect). Both are compared
/// EXACTLY, before the policy is consulted at all: a request from a stale
/// attempt or a superseded session is refused whatever the policy says.
/// [audited] states whether a durable authorization record can actually be
/// emitted; without one there is no such thing as a recorded grant, so there is
/// no grant.
///
/// The answer is always one the harness offered, or [AgentPermissionOutcome
/// .cancelled] when none of them is compliant. A refusal prefers the narrow
/// [AgentPermissionOutcome.rejectOnce] over [AgentPermissionOutcome
/// .rejectAlways]; a durable grant falls back to the NARROWER
/// [AgentPermissionOutcome.allowOnce] rather than cancelling, and an
/// [AgentPermissionGrant.allowOnce] rule is never widened into a durable one.
///
/// **No role axis.** The bind is attempt + protocol session + capability.
/// ADR-0006 D5 retired the role indirection and nothing at this seam replaces
/// it; a station- or session-scoped role, if one is ever introduced, binds here
/// through its own bead.
AgentPermissionDecision decideAgentPermission({
  required AgentPermissionPolicy policy,
  required AgentPermissionRequest request,
  required String admittedAttemptId,
  required String? boundSessionId,
  required bool audited,
}) {
  AgentPermissionDecision refuse(String reason) => AgentPermissionDecision(
    requestId: request.requestId,
    attemptId: request.attemptId,
    sessionId: request.sessionId,
    capability: request.capability,
    policyId: policy.id,
    outcome: _refusalOutcome(request.offered),
    reason: reason,
  );

  if (admittedAttemptId.trim().isEmpty) {
    return refuse('the channel carries no admitted attempt');
  }
  if (request.attemptId != admittedAttemptId) {
    return refuse(
      'the request names an attempt this channel was not admitted '
      'under',
    );
  }
  if (boundSessionId == null || boundSessionId.trim().isEmpty) {
    return refuse('no protocol session is bound to the admitted attempt');
  }
  if (request.sessionId != boundSessionId) {
    return refuse('the request names a superseded protocol session');
  }
  if (!audited) {
    return refuse('no durable authorization record can be emitted');
  }

  final grant = policy.grantFor(request.capability);
  return switch (grant) {
    AgentPermissionGrant.deny => refuse(
      policy.id.trim().isEmpty
          ? 'no station permission policy is in effect'
          : 'policy "${policy.id}" grants no ${request.capability.name} scope',
    ),
    AgentPermissionGrant.allowOnce => _allow(
      request: request,
      policy: policy,
      // NEVER widened: an allow-once rule that cannot be answered one-shot is
      // cancelled, not upgraded to the durable option the harness offered.
      preferred: const <AgentPermissionOutcome>[
        AgentPermissionOutcome.allowOnce,
      ],
      reason: 'policy "${policy.id}" allows ${request.capability.name} once',
    ),
    AgentPermissionGrant.allowAlways => _allow(
      request: request,
      policy: policy,
      preferred: const <AgentPermissionOutcome>[
        AgentPermissionOutcome.allowAlways,
        AgentPermissionOutcome.allowOnce,
      ],
      reason: 'policy "${policy.id}" allows ${request.capability.name} durably',
    ),
  };
}

AgentPermissionDecision _allow({
  required AgentPermissionRequest request,
  required AgentPermissionPolicy policy,
  required List<AgentPermissionOutcome> preferred,
  required String reason,
}) {
  for (final outcome in preferred) {
    if (request.offered.contains(outcome)) {
      return AgentPermissionDecision(
        requestId: request.requestId,
        attemptId: request.attemptId,
        sessionId: request.sessionId,
        capability: request.capability,
        policyId: policy.id,
        outcome: outcome,
        reason: reason,
      );
    }
  }
  return AgentPermissionDecision.cancelled(
    request: request,
    policyId: policy.id,
    reason: 'the harness offered no answer this policy permits',
  );
}

/// A refusal takes the NARROWEST refusal offered, and cancels when none is.
AgentPermissionOutcome _refusalOutcome(List<AgentPermissionOutcome> offered) {
  if (offered.contains(AgentPermissionOutcome.rejectOnce)) {
    return AgentPermissionOutcome.rejectOnce;
  }
  if (offered.contains(AgentPermissionOutcome.rejectAlways)) {
    return AgentPermissionOutcome.rejectAlways;
  }
  return AgentPermissionOutcome.cancelled;
}

AgentPermissionCapability _capabilityByName(Object? name) {
  for (final capability in AgentPermissionCapability.values) {
    if (capability.name == name) return capability;
  }
  return AgentPermissionCapability.unknown;
}

AgentPermissionOutcome _outcomeByName(Object? name) {
  for (final outcome in AgentPermissionOutcome.values) {
    if (outcome.name == name) return outcome;
  }
  throw FormatException('unknown agent permission outcome: $name');
}

List<AgentPermissionOutcome> _outcomesByName(Object? raw) {
  if (raw is! List<Object?>) {
    throw FormatException('agent permission offers must be a list: $raw');
  }
  final offered = <AgentPermissionOutcome>[];
  for (final name in raw) {
    final outcome = _outcomeByName(name);
    // `cancelled` is the grid's own fallback, never something a harness offers.
    if (outcome == AgentPermissionOutcome.cancelled) continue;
    if (!offered.contains(outcome)) offered.add(outcome);
  }
  return List<AgentPermissionOutcome>.unmodifiable(offered);
}
