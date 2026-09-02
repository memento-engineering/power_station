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

import 'agent_environment.dart';

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
    final command = request.environment.command;
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
