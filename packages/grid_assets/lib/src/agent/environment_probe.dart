/// The environment PROBE seam (ADR-0006 D3, bead `pow-n6n.3`) — what makes an
/// environment PRESENT on this box right now: its harness binary is on `PATH`,
/// its target endpoint answers, and (where the provider exposes a models list)
/// its pinned model is listed.
///
/// A pure DI seam: the availability seed (`availability_assets.dart`) TAKES an
/// [EnvironmentProbe] and never constructs one, so a test drives presence with
/// a Fake and lib code touches no machine (the `BdRunner` / injected-runner
/// precedent — power_station CLAUDE.md "config = VALUES in the tree; impls are
/// DI").
library;

import 'dart:convert';
import 'dart:io';

import 'acp_session_adapter.dart';
import 'agent_environment.dart';
import 'lane_environment_health.dart';
import 'model_tier.dart';

/// The per-check IO budget for [ProcessEnvironmentProbe]'s defaults. BOUNDED on
/// purpose: a wedged local server must leave the presence set, not stall the
/// probe pass.
const Duration kEnvironmentProbeTimeout = Duration(seconds: 2);

/// ONE environment's probe input: its registry [name], the FLATTENED
/// [environment] the registry resolved for it, and the [endpoint] the site
/// binding bound on this box (null when the target is provider-managed and
/// needs no machine fact).
class EnvironmentProbeRequest {
  /// Creates the request over [name], [environment] and its optional [endpoint].
  const EnvironmentProbeRequest({
    required this.name,
    required this.environment,
    this.endpoint,
  });

  /// The armed registry name (the key `SiteBinding` and the transport read).
  final String name;

  /// The flattened environment armed under [name].
  final AgentEnvironment environment;

  /// The site-bound inference endpoint, or null for a provider-managed target.
  final Uri? endpoint;

  @override
  String toString() => 'EnvironmentProbeRequest($name, $endpoint)';
}

/// Whether [request]'s environment is PRESENT on this box right now.
///
/// A BOOLEAN by design: presence is set membership (ADR-0006 D3 — availability
/// is PRESENCE IN THE TREE), so a refusal reason no rung reads would be a dead
/// field. A probe that THROWS counts as absent; the seed catches it.
typedef EnvironmentProbe =
    Future<bool> Function(EnvironmentProbeRequest request);

/// The REAL probe: D3's three checks, composed over three injected IO
/// primitives so the COMPOSITION (which check runs for which
/// [InferenceTarget]) is pure and unit-testable while only the defaults touch
/// the machine (pure logic tested before IO is wired — the house set).
///
/// A station arms it as `const ProcessEnvironmentProbe().call`.
class ProcessEnvironmentProbe {
  /// Creates the probe; each primitive defaults to its real implementation.
  const ProcessEnvironmentProbe({
    Future<bool> Function(String command) binaryPresent = commandOnPath,
    Future<bool> Function(Uri endpoint) endpointReachable = socketReachable,
    Future<Set<String>> Function(Uri endpoint) listModels = listedModels,
  }) : _binaryPresent = binaryPresent,
       _endpointReachable = endpointReachable,
       _listModels = listModels;

  final Future<bool> Function(String command) _binaryPresent;
  final Future<bool> Function(Uri endpoint) _endpointReachable;
  final Future<Set<String>> Function(Uri endpoint) _listModels;

  /// Probes [request] — the [EnvironmentProbe] shape.
  Future<bool> call(EnvironmentProbeRequest request) async {
    final command = inspectedBinaryOf(request.environment);
    if (command == null || !await _binaryPresent(command)) return false;
    final target =
        request.environment.target ?? InferenceTarget.providerManaged;
    return switch (target) {
      // The tool owns its own auth/routing (claude via keychain, copilot via
      // `gh`): the binary IS the presence test.
      InferenceTarget.providerManaged => true,
      InferenceTarget.openAiCompatible ||
      InferenceTarget.swiftInfer => _reachesModel(request),
    };
  }

  Future<bool> _reachesModel(EnvironmentProbeRequest request) async {
    final endpoint = request.endpoint;
    // Unbound HERE means unreachable HERE — presence is per-box.
    if (endpoint == null) return false;
    if (!await _endpointReachable(endpoint)) return false;
    final model = request.environment.model;
    // Nothing pinned ⇒ nothing to list; reachability is the whole test.
    if (model == null) return true;
    return (await _listModels(endpoint)).contains(model);
  }
}

/// Whether [command] resolves to a file on this box: a path as written when it
/// carries a separator, else each `PATH` entry in order.
///
/// A PATH WALK, not a subprocess: it is deterministic and costs no fork per
/// probe, and the probe pass runs on a bounded interval forever.
Future<bool> commandOnPath(String command) async {
  if (command.contains(Platform.pathSeparator)) {
    return File(command).existsSync();
  }
  final separator = Platform.isWindows ? ';' : ':';
  for (final dir in (Platform.environment['PATH'] ?? '').split(separator)) {
    if (dir.isEmpty) continue;
    if (File('$dir${Platform.pathSeparator}$command').existsSync()) return true;
  }
  return false;
}

/// Whether a TCP connection to [endpoint] completes inside
/// [kEnvironmentProbeTimeout]. A dead local server refuses at once and a wedged
/// one times out — either way the environment leaves the presence set.
Future<bool> socketReachable(Uri endpoint) async {
  final port = endpoint.hasPort
      ? endpoint.port
      : (endpoint.scheme == 'https' ? 443 : 80);
  try {
    final socket = await Socket.connect(
      endpoint.host,
      port,
      timeout: kEnvironmentProbeTimeout,
    );
    socket.destroy();
    return true;
  } on Object {
    return false;
  }
}

/// The model ids [endpoint] lists at `GET /v1/models` (the OpenAI-compatible
/// shape both swift-infer and a llama.cpp server answer), or the EMPTY set when
/// the provider exposes no list or answers unparseably.
///
/// The empty set makes a PINNED model absent — the fail-closed reading of
/// "model listed" (ADR-0000 A8 guards LOUD or GONE: the loud half is the
/// environment vanishing from the tree, never a silent spawn against a model
/// the server does not serve).
Future<Set<String>> listedModels(Uri endpoint) async {
  final client = HttpClient()..connectionTimeout = kEnvironmentProbeTimeout;
  try {
    final response = await (await client.getUrl(
      endpoint.resolve('/v1/models'),
    )).close();
    if (response.statusCode != 200) return const <String>{};
    final decoded = jsonDecode(await response.transform(utf8.decoder).join());
    if (decoded is! Map) return const <String>{};
    final data = decoded['data'];
    if (data is! List) return const <String>{};
    return <String>{
      for (final entry in data)
        if (entry is Map && entry['id'] is String) entry['id']! as String,
    };
  } on Object {
    return const <String>{};
  } finally {
    client.close(force: true);
  }
}

/// WHICH binary an environment's presence is actually about.
///
/// [AgentEnvironment.pathCheck] when declared (gc's shell-wrapper case),
/// else [AgentEnvironment.command]. The codex lane is exactly why this matters:
/// its command is `npx`, which is present on every box that has node, so
/// checking `command` proved nothing about the agent — the thing that moved to
/// 0.155.1 and started refusing every pin is `codex`.
String? inspectedBinaryOf(AgentEnvironment environment) =>
    environment.pathCheck ?? environment.command;

/// The REAL lane diagnostic (bead `pow-u1bi`): what the agent binary IS right
/// now, and what the resolver says about the pin against the catalog the agent
/// offered.
///
/// Four injected IO primitives plus the resolver tear-off, so the COMPOSITION —
/// which fact decides a pass — is pure and unit-testable while only the
/// defaults touch the machine ([ProcessEnvironmentProbe]'s own precedent, and
/// A38(7)'s rule for the boolean probe).
///
/// THE PASS RULE, one sentence for both legs: the lane passes when the resolver
/// accepts the catalog under test, or — on the SCHEDULED leg only — when the
/// binary has been REPLACED since the lane went down. The replacement clause is
/// what re-admits exactly one handshake after a rollback: the catalog on file is
/// the old binary's, so only the live agent can say whether the replacement is
/// good, and two fresh refusals re-park it if it is not.
class ProcessLaneEnvironmentProbe {
  /// Creates the probe; each primitive defaults to its real implementation.
  const ProcessLaneEnvironmentProbe({
    Future<String?> Function(String command) locateBinary = resolveBinaryPath,
    Future<String?> Function(String path) readVersion = readBinaryVersion,
    Future<DateTime?> Function(String path) readMtime = readBinaryMtime,
    AcpModelResolver resolveModelId = resolveAcpModelId,
    DateTime Function() now = _utcNow,
  }) : _locateBinary = locateBinary,
       _readVersion = readVersion,
       _readMtime = readMtime,
       _resolveModelId = resolveModelId,
       _now = now;

  final Future<String?> Function(String command) _locateBinary;
  final Future<String?> Function(String path) _readVersion;
  final Future<DateTime?> Function(String path) _readMtime;
  final AcpModelResolver _resolveModelId;
  final DateTime Function() _now;

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// Diagnoses [request] — the [LaneEnvironmentDiagnosticProbe] shape.
  Future<LaneEnvironmentDiagnosis> call(
    LaneEnvironmentProbeRequest request,
  ) async {
    final binary = await _inspect(request.target.environment);
    final pin = request.pin ?? request.target.pin;
    final bool accepts;
    final String verdict;
    if (pin == null) {
      // NOTHING PINNED. There is no resolver question to ask, so the scheduled
      // leg's own gate (the boolean presence probe the coordinator already
      // required) is the whole test — the same fail-open reading
      // `ProcessEnvironmentProbe._reachesModel` takes for an unpinned model. A
      // TARGETED refusal with no pin is still a refusal, and stays one.
      accepts = request.scheduled;
      verdict = request.scheduled
          ? 'no model is pinned for this lane; presence is the whole test'
          : 'no model is pinned for this lane, so the setup refusal names no '
                'resolvable pin';
    } else {
      final resolved = _resolveModelId(
        want: pin,
        available: request.offered,
        tier: request.target.tier,
      );
      accepts = resolved != null;
      verdict = resolved != null
          ? 'the pinned model resolves to "$resolved"'
          : acpModelRefusal(
              want: pin,
              available: request.offered,
              tier: request.target.tier,
            );
    }
    final replaced =
        request.priorBinary != null && binary != request.priorBinary;
    return LaneEnvironmentDiagnosis(
      lane: request.target.lane,
      observedAt: _now(),
      binary: binary,
      pin: pin,
      offered: List<String>.unmodifiable(request.offered),
      resolverVerdict: verdict,
      passed: accepts || (request.scheduled && replaced),
    );
  }

  Future<LaneBinaryFingerprint> _inspect(AgentEnvironment environment) async {
    final command = inspectedBinaryOf(environment);
    if (command == null) return LaneBinaryFingerprint.unknown;
    final String? path;
    try {
      path = await _locateBinary(command);
    } on Object {
      return LaneBinaryFingerprint.unknown;
    }
    if (path == null) return LaneBinaryFingerprint.unknown;
    String? version;
    DateTime? mtime;
    try {
      version = await _readVersion(path);
    } on Object {
      version = null; // an unreadable version is a FACT, never a throw.
    }
    try {
      mtime = await _readMtime(path);
    } on Object {
      mtime = null;
    }
    return LaneBinaryFingerprint(path: path, version: version, mtime: mtime);
  }
}

/// The signature of [resolveAcpModelId], so the resolver can be injected as a
/// tear-off and a test composes the probe without a live catalog.
typedef AcpModelResolver =
    String? Function({
      required String want,
      required List<String> available,
      required AgentTier tier,
      String? current,
    });

/// The ABSOLUTE file [command] runs as on this box, with symlinks resolved, or
/// null when it resolves to nothing.
///
/// The symlink resolution is the point: a Homebrew or npm-global CLI is a link
/// into a versioned directory, and the LINK's mtime is when the link was made,
/// not when the binary changed. Following it is what made `0.155.1, written at
/// 23:22Z` readable at all.
Future<String?> resolveBinaryPath(String command) async {
  String? candidate;
  if (command.contains(Platform.pathSeparator)) {
    candidate = File(command).existsSync() ? command : null;
  } else {
    final separator = Platform.isWindows ? ';' : ':';
    for (final dir in (Platform.environment['PATH'] ?? '').split(separator)) {
      if (dir.isEmpty) continue;
      final entry = '$dir${Platform.pathSeparator}$command';
      if (File(entry).existsSync()) {
        candidate = entry;
        break;
      }
    }
  }
  if (candidate == null) return null;
  try {
    return File(candidate).resolveSymbolicLinksSync();
  } on Object {
    return candidate; // a broken link still names WHERE we looked.
  }
}

/// The version [path] reports for itself, bounded by [kEnvironmentProbeTimeout].
///
/// The LAST semantic-version-shaped token of the trimmed output (stdout, else
/// stderr): agent CLIs print anything from `0.155.1` to
/// `codex-acp 1.6.2 (protocol 1)`, and the version is the last such token in
/// every shape observed. Null when nothing version-shaped appears at all.
Future<String?> readBinaryVersion(String path) async {
  final ProcessResult result;
  try {
    result = await Process.run(
      path,
      const <String>['--version'],
    ).timeout(kEnvironmentProbeTimeout);
  } on Object {
    return null;
  }
  final out = '${result.stdout}'.trim();
  final text = out.isNotEmpty ? out : '${result.stderr}'.trim();
  return semanticVersionToken(text);
}

/// The LAST semantic-version-shaped token in [text], or null.
String? semanticVersionToken(String text) {
  final matches = RegExp(
    r'\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?',
  ).allMatches(text).toList(growable: false);
  return matches.isEmpty ? null : matches.last.group(0);
}

/// When [path] was last written, in UTC; null when it cannot be read.
Future<DateTime?> readBinaryMtime(String path) async {
  try {
    return (await File(path).lastModified()).toUtc();
  } on Object {
    return null;
  }
}
