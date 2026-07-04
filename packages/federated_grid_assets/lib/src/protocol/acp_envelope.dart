/// The ACP-shaped wire envelope (D-B3, the honesty pass, 2026-07-03).
///
/// ACP = Zed's Agent Client Protocol (agentclientprotocol.com) — NOT IBM's
/// retired ACP, and MCP is explicitly NOT being introduced here (RULED). What
/// is borrowed is narrow and deliberate: the **JSON-RPC 2.0 envelope** (a
/// request carries `id`+`method`+`params`; a notification the same minus
/// `id`; a response echoes the request's `id` with `result` XOR `error`) plus
/// **method namespacing** (`grid/...`, mirroring ACP's `session/...`-shaped
/// methods) plus **initialize-time capability negotiation** (`../protocol/bus_protocol.dart`'s
/// `initialize` method pair). The METHODS THEMSELVES are ours — `grid/presence`,
/// `grid/claim/unclaimed`, `grid/claim/respond`, `grid/claim/confirm` — never
/// ACP's own agent-session methods (`session/new`, `session/prompt`, …), which
/// are a different protocol for a different problem (an agent ↔ client
/// session, not station-to-station federation).
///
/// Carried as MQTT PAYLOAD BYTES (D-B1/D-B3): a broadcast-unclaimed is a
/// [AcpNotification] (no `id` — fire-and-forget, nothing to correlate a reply
/// to); claim-resp/confirm are an [AcpRequest] (minted by the RESPONDING peer,
/// on ITS OWN broker) paired with an [AcpResultResponse] (minted by the
/// CLAIM'S OWNER, on the OWNER'S OWN broker) — correlated by the SAME `id`
/// ACROSS the two brokers (there is no shared connection for JSON-RPC's usual
/// same-channel req/resp; single-writer/publish-own means each half can only
/// ever be published on its author's own broker, so `id` is the only thread
/// tying them together, not a socket).
library;

import 'dart:convert';
import 'dart:typed_data';

/// The JSON-RPC 2.0 envelope version this protocol declares (carried
/// verbatim in every encoded message, matching the wire convention ACP itself
/// borrows from JSON-RPC).
const String kJsonRpcVersion = '2.0';

/// One ACP-shaped envelope: a request, a notification, or a response
/// (result or error). Sealed so a consumer's dispatch on [AcpMessage] is
/// exhaustive (house style).
sealed class AcpMessage {
  const AcpMessage();

  /// Parses [json] into the concrete envelope shape: `method` + `id` present
  /// → [AcpRequest]; `method` present, no `id` → [AcpNotification]; otherwise
  /// (no `method`) → [AcpResultResponse] or [AcpErrorResponse] depending on
  /// which of `result`/`error` is present.
  factory AcpMessage.fromJson(Map<String, dynamic> json) {
    final method = json['method'];
    if (method is String) {
      final id = json['id'];
      final params = (json['params'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      if (id != null) {
        return AcpRequest(id: id as String, method: method, params: params);
      }
      return AcpNotification(method: method, params: params);
    }
    final id = json['id'] as String? ?? '';
    final error = json['error'];
    if (error is Map) {
      final e = error.cast<String, dynamic>();
      return AcpErrorResponse(
        id: id,
        code: e['code'] as int? ?? 0,
        message: e['message'] as String? ?? '',
        data: (e['data'] as Map?)?.cast<String, dynamic>(),
      );
    }
    final result =
        (json['result'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AcpResultResponse(id: id, result: result);
  }

  /// The JSON form (always stamped `"jsonrpc": "2.0"`).
  Map<String, dynamic> toJson();
}

/// A JSON-RPC 2.0 REQUEST — [id]-bearing, expects a correlated
/// [AcpResultResponse]/[AcpErrorResponse] carrying the SAME [id] back.
class AcpRequest extends AcpMessage {
  /// Creates a request. [id] is minted by the SENDER (this station), unique
  /// enough to correlate its eventual response (a station-scoped counter is
  /// sufficient — the sender is also the one matching the reply).
  const AcpRequest({
    required this.id,
    required this.method,
    this.params = const {},
  });

  /// The correlation id — echoed verbatim by the response.
  final String id;

  /// The namespaced method (`../protocol/bus_protocol.dart`'s [BusMethods]).
  final String method;

  /// The method's parameters.
  final Map<String, dynamic> params;

  @override
  Map<String, dynamic> toJson() => {
        'jsonrpc': kJsonRpcVersion,
        'id': id,
        'method': method,
        'params': params,
      };

  @override
  String toString() => 'AcpRequest($method, id: $id, params: $params)';
}

/// A JSON-RPC 2.0 NOTIFICATION — no `id`, fire-and-forget (nothing correlates
/// a reply to it; the claim protocol's broadcast-unclaimed is exactly this).
class AcpNotification extends AcpMessage {
  /// Creates a notification.
  const AcpNotification({required this.method, this.params = const {}});

  /// The namespaced method.
  final String method;

  /// The method's parameters.
  final Map<String, dynamic> params;

  @override
  Map<String, dynamic> toJson() => {
        'jsonrpc': kJsonRpcVersion,
        'method': method,
        'params': params,
      };

  @override
  String toString() => 'AcpNotification($method, params: $params)';
}

/// A JSON-RPC 2.0 SUCCESS response — echoes the originating request's [id].
class AcpResultResponse extends AcpMessage {
  /// Creates a success response for request [id].
  const AcpResultResponse({required this.id, this.result = const {}});

  /// The correlation id (matches the [AcpRequest.id] this responds to).
  final String id;

  /// The result payload.
  final Map<String, dynamic> result;

  @override
  Map<String, dynamic> toJson() => {
        'jsonrpc': kJsonRpcVersion,
        'id': id,
        'result': result,
      };

  @override
  String toString() => 'AcpResultResponse(id: $id, result: $result)';
}

/// A JSON-RPC 2.0 ERROR response — echoes the originating request's [id].
class AcpErrorResponse extends AcpMessage {
  /// Creates an error response for request [id].
  const AcpErrorResponse({
    required this.id,
    required this.code,
    required this.message,
    this.data,
  });

  /// The correlation id.
  final String id;

  /// A JSON-RPC-shaped error code (this protocol does not mandate the
  /// standard JSON-RPC reserved ranges — a station-local convention is
  /// sufficient since both ends are our own implementation).
  final int code;

  /// A human-readable reason.
  final String message;

  /// Optional structured detail.
  final Map<String, dynamic>? data;

  @override
  Map<String, dynamic> toJson() => {
        'jsonrpc': kJsonRpcVersion,
        'id': id,
        'error': {
          'code': code,
          'message': message,
          if (data != null) 'data': data,
        },
      };

  @override
  String toString() => 'AcpErrorResponse(id: $id, code: $code, $message)';
}

/// Encodes [message] to UTF-8 JSON bytes — the [Broker.publish] payload.
Uint8List encodeAcp(AcpMessage message) =>
    Uint8List.fromList(utf8.encode(jsonEncode(message.toJson())));

/// Decodes a [Broker]-delivered payload back into an [AcpMessage]. Throws
/// [FormatException] on invalid JSON (a malformed/foreign message on the
/// topic) — callers on an untrusted/mixed topic should catch it rather than
/// let a bad payload crash the listener loop.
AcpMessage decodeAcp(Uint8List payload) =>
    AcpMessage.fromJson(
      (jsonDecode(utf8.decode(payload)) as Map).cast<String, dynamic>(),
    );
