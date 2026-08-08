/// Declared embedding-provider values and their single OpenAI-compatible client.
library;

import 'dart:convert';
import 'dart:io';

import 'embedding_index.dart';

/// Semantic facts describing one uniformly rendered embedding provider.
class EmbeddingProvider {
  /// Creates a provider declaration containing model shape, never an endpoint.
  const EmbeddingProvider({
    required this.id,
    required this.bindingName,
    required this.model,
    required this.authEnvironmentVariable,
    required this.dimensions,
    required this.contextWindowTokens,
    required this.batchLimit,
  });

  /// Registry identifier selected by configuration.
  final String id;

  /// Machine-local endpoint fact name in [EmbeddingSiteBinding].
  final String bindingName;

  /// Model identifier sent on the embeddings wire.
  final String model;

  /// Environment variable containing the bearer token.
  final String authEnvironmentVariable;

  /// Exact vector width produced by the model.
  final int dimensions;

  /// Maximum model input length in tokens.
  final int contextWindowTokens;

  /// Maximum number of inputs sent in one request.
  final int batchLimit;

  /// Returns a loud configuration refusal, or null when the shape is valid.
  String? validate() {
    if (id.trim().isEmpty) {
      return 'embedding provider id is blank; declare a non-blank provider id';
    }
    if (bindingName.trim().isEmpty) {
      return 'embedding provider "$id" has blank bindingName; declare the '
          'machine-local endpoint fact name';
    }
    if (model.trim().isEmpty) {
      return 'embedding provider "$id" has blank model; declare the served '
          'embedding model id';
    }
    if (authEnvironmentVariable.trim().isEmpty) {
      return 'embedding provider "$id" has blank auth environment variable; '
          'declare the bearer-token environment variable name';
    }
    if (dimensions <= 0) {
      return 'embedding provider "$id" has invalid dimensions $dimensions; '
          'declare the positive vector width produced by the model';
    }
    if (contextWindowTokens <= 0) {
      return 'embedding provider "$id" has invalid contextWindowTokens '
          '$contextWindowTokens; declare the positive model input limit';
    }
    if (batchLimit <= 0) {
      return 'embedding provider "$id" has invalid batchLimit $batchLimit; '
          'declare a positive maximum request batch size';
    }
    return null;
  }

  /// Identity an index must have to accept vectors from this provider.
  EmbeddingIndexIdentity get indexIdentity => EmbeddingIndexIdentity(
    providerId: id,
    model: model,
    dimensions: dimensions,
  );
}

/// First-party embedding provider declarations.
const Map<String, EmbeddingProvider> kBuiltinEmbeddingProviders = {
  'swift-infer': EmbeddingProvider(
    id: 'swift-infer',
    bindingName: 'swift-infer',
    model: 'bge-small',
    authEnvironmentVariable: 'SWIFT_INFER_ADMIN_TOKEN',
    dimensions: 384,
    contextWindowTokens: 512,
    batchLimit: 128,
  ),
};

/// Provider selected when configuration names none.
const String kDefaultEmbeddingProviderId = 'swift-infer';

/// A provider declaration or mount-time configuration refusal.
class EmbeddingProviderRegistryError implements Exception {
  /// Creates a refusal with an actionable [message].
  const EmbeddingProviderRegistryError(this.message);

  /// Actionable refusal text.
  final String message;

  @override
  String toString() => 'EmbeddingProviderRegistryError: $message';
}

/// Resolves declared providers and validates every mount-time invariant.
class EmbeddingProviderRegistry {
  /// Creates a registry from declared [providers] and its default selection.
  const EmbeddingProviderRegistry({
    this.providers = kBuiltinEmbeddingProviders,
    this.defaultProviderId = kDefaultEmbeddingProviderId,
  });

  /// Provider declarations keyed by their exact ids.
  final Map<String, EmbeddingProvider> providers;

  /// Provider id selected when no override is supplied.
  final String defaultProviderId;

  /// Resolves [id], or the default, and throws when it is undeclared.
  EmbeddingProvider resolve([String? id]) {
    final selected = id ?? defaultProviderId;
    final provider = providers[selected];
    if (provider == null) {
      throw EmbeddingProviderRegistryError(
        'unknown embedding provider "$selected"; declare it in the registry '
        'or select a declared provider id',
      );
    }
    return provider;
  }

  /// Validates declarations, selection, auth, index identity, then binding.
  String? validate({
    String? providerId,
    required Map<String, String> environment,
    required EmbeddingIndexIdentity indexIdentity,
    required EmbeddingSiteBinding siteBinding,
  }) {
    for (final entry in providers.entries) {
      final refusal = entry.value.validate();
      if (refusal != null) return refusal;
      if (entry.key != entry.value.id) {
        return 'embedding provider map key "${entry.key}" does not match '
            'declared id "${entry.value.id}"; key the value by its exact id';
      }
    }
    final EmbeddingProvider provider;
    try {
      provider = resolve(providerId);
    } on EmbeddingProviderRegistryError catch (error) {
      return error.message;
    }
    final token = environment[provider.authEnvironmentVariable];
    if (token == null || token.trim().isEmpty) {
      return 'embedding provider "${provider.id}" needs bearer token '
          '${provider.authEnvironmentVariable}; set a non-blank value before '
          'mounting';
    }
    if (provider.indexIdentity != indexIdentity) {
      return 'embedding provider/index identity mismatch for "${provider.id}": '
          'expected ${provider.id}/${provider.model}/${provider.dimensions}, '
          'observed ${indexIdentity.providerId}/${indexIdentity.model}/'
          '${indexIdentity.dimensions}; delete .grid/embeddings and re-index';
    }
    return siteBinding.refusalFor(provider);
  }
}

/// Version owned by the embedding-specific site-binding decoder.
const int kEmbeddingSiteBindingVersion = 1;

/// Machine-local embedding endpoint binding path.
const String kEmbeddingSiteBindingFile = '.grid/embedding-site.json';

/// A missing endpoint fact requested from an embedding site binding.
class EmbeddingSiteBindingError implements Exception {
  /// Creates a binding refusal with an actionable [message].
  const EmbeddingSiteBindingError(this.message);

  /// Actionable refusal text.
  final String message;

  @override
  String toString() => 'EmbeddingSiteBindingError: $message';
}

/// Machine-local mapping from semantic binding names to endpoint URIs.
class EmbeddingSiteBinding {
  /// Creates a binding from endpoint facts.
  const EmbeddingSiteBinding(this.endpoints);

  /// An empty binding with no fallback endpoints.
  static const none = EmbeddingSiteBinding(<String, Uri>{});

  /// Endpoint facts keyed by provider binding name.
  final Map<String, Uri> endpoints;

  /// Parses the versioned binding envelope, refusing malformed facts whole.
  factory EmbeddingSiteBinding.parse(Map<String, Object?> raw) {
    if (raw['version'] != kEmbeddingSiteBindingVersion) {
      throw const FormatException(
        'unsupported embedding site binding version; write version 1',
      );
    }
    final values = raw['endpoints'];
    if (values is! Map) {
      throw const FormatException('embedding endpoints must be an object');
    }
    final endpoints = <String, Uri>{};
    values.forEach((key, value) {
      if (key is! String || key.trim().isEmpty) {
        throw const FormatException(
          'embedding endpoint name must be a non-blank string',
        );
      }
      if (value is! String || value.trim().isEmpty) {
        throw FormatException(
          'embedding endpoint "$key" url must be a non-blank string',
        );
      }
      final uri = Uri.tryParse(value);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        throw FormatException(
          'embedding endpoint "$key" is not an absolute url; bind a url with '
          'scheme and authority',
        );
      }
      endpoints[key] = uri;
    });
    return EmbeddingSiteBinding(endpoints);
  }

  /// Decodes and parses a JSON binding envelope.
  factory EmbeddingSiteBinding.fromJson(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('embedding site binding must be an object');
    }
    return EmbeddingSiteBinding.parse(decoded.cast<String, Object?>());
  }

  /// Loads [path], returning [none] only when the file is absent.
  static EmbeddingSiteBinding loadJsonFile(String path) {
    final file = File(path);
    return file.existsSync()
        ? EmbeddingSiteBinding.fromJson(file.readAsStringSync())
        : none;
  }

  /// Returns an actionable refusal when [provider]'s endpoint fact is absent.
  String? refusalFor(EmbeddingProvider provider) {
    if (endpoints.containsKey(provider.bindingName)) return null;
    return 'embedding provider "${provider.id}" is missing endpoint fact '
        '"${provider.bindingName}"; bind it in $kEmbeddingSiteBindingFile with '
        'version 1 and an endpoints name-to-url entry; no fallback exists';
  }

  /// Resolves [provider]'s endpoint or throws a loud binding refusal.
  Uri endpointFor(EmbeddingProvider provider) {
    final refusal = refusalFor(provider);
    if (refusal != null) throw EmbeddingSiteBindingError(refusal);
    return endpoints[provider.bindingName]!;
  }
}

/// Transport-neutral request passed to the injectable HTTP function seam.
class EmbeddingHttpRequest {
  /// Creates a complete embedding HTTP request.
  const EmbeddingHttpRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  /// HTTP method.
  final String method;

  /// Absolute request URI.
  final Uri uri;

  /// HTTP headers.
  final Map<String, String> headers;

  /// Encoded request body.
  final String body;
}

/// Minimal HTTP response consumed by the embedding client.
class EmbeddingHttpResponse {
  /// Creates a response with [statusCode] and encoded [body].
  const EmbeddingHttpResponse({required this.statusCode, required this.body});

  /// HTTP response status.
  final int statusCode;

  /// Encoded response body.
  final String body;
}

/// Function-typed HTTP dependency used by every provider.
typedef EmbeddingHttpSend =
    Future<EmbeddingHttpResponse> Function(EmbeddingHttpRequest request);

/// The end-to-end deadline on one embedding HTTP round-trip. A black-holing
/// endpoint (packets dropped, no fast connection-refused) must degrade to
/// `SemanticUnavailable` like every other provider failure — never stall the
/// whole search command behind the lexical half (the review committee's
/// regression-risk finding on this diff; same bound-the-external-call
/// convention as `pr_describe.dart`/`bounded_use.dart`).
const Duration kEmbeddingHttpTimeout = Duration(seconds: 30);

/// Sends one request through dart:io's HTTP client, bounded end to end by
/// [kEmbeddingHttpTimeout].
Future<EmbeddingHttpResponse> sendEmbeddingHttpRequest(
  EmbeddingHttpRequest request,
) async {
  final client = HttpClient();
  try {
    return await () async {
      final wire = await client.openUrl(request.method, request.uri);
      request.headers.forEach(wire.headers.set);
      wire.write(request.body);
      final response = await wire.close();
      return EmbeddingHttpResponse(
        statusCode: response.statusCode,
        body: await utf8.decoder.bind(response).join(),
      );
    }().timeout(kEmbeddingHttpTimeout);
  } finally {
    client.close(force: true);
  }
}

/// A loud embeddings wire or response-shape failure.
class EmbeddingClientError implements Exception {
  /// Creates a client failure with a diagnostic [message].
  const EmbeddingClientError(this.message);

  /// Diagnostic failure text.
  final String message;

  @override
  String toString() => 'EmbeddingClientError: $message';
}

/// The single client that renders every declared embedding provider value.
class EmbeddingClient {
  EmbeddingClient._({
    required this.provider,
    required this.endpoint,
    required String bearerToken,
    required EmbeddingHttpSend send,
  }) : _bearerToken = bearerToken,
       _send = send;

  /// Validates all mount invariants before constructing a usable client.
  factory EmbeddingClient.mount({
    required EmbeddingProviderRegistry registry,
    String? providerId,
    required Map<String, String> environment,
    required EmbeddingIndexIdentity indexIdentity,
    required EmbeddingSiteBinding siteBinding,
    EmbeddingHttpSend send = sendEmbeddingHttpRequest,
  }) {
    final refusal = registry.validate(
      providerId: providerId,
      environment: environment,
      indexIdentity: indexIdentity,
      siteBinding: siteBinding,
    );
    if (refusal != null) throw EmbeddingProviderRegistryError(refusal);
    final provider = registry.resolve(providerId);
    return EmbeddingClient._(
      provider: provider,
      endpoint: siteBinding.endpointFor(provider),
      bearerToken: environment[provider.authEnvironmentVariable]!,
      send: send,
    );
  }

  /// Selected provider declaration.
  final EmbeddingProvider provider;

  /// Machine-local base endpoint resolved at mount.
  final Uri endpoint;

  final String _bearerToken;
  final EmbeddingHttpSend _send;

  /// Embeds [inputs] in declared-size batches while preserving global order.
  Future<List<List<double>>> embed(List<String> inputs) async {
    if (inputs.isEmpty) return const [];
    final output = <List<double>>[];
    for (var start = 0; start < inputs.length; start += provider.batchLimit) {
      final end = start + provider.batchLimit < inputs.length
          ? start + provider.batchLimit
          : inputs.length;
      output.addAll(await _embedBatch(inputs.sublist(start, end)));
    }
    return output;
  }

  Future<List<List<double>>> _embedBatch(List<String> inputs) async {
    final clean = endpoint.path.replaceFirst(RegExp(r'/+$'), '');
    final response = await _send(
      EmbeddingHttpRequest(
        method: 'POST',
        uri: endpoint.replace(path: '$clean/v1/embeddings'),
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $_bearerToken',
          HttpHeaders.contentTypeHeader: 'application/json',
        },
        body: jsonEncode({'model': provider.model, 'input': inputs}),
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw EmbeddingClientError(
        'embedding provider "${provider.id}" returned HTTP '
        '${response.statusCode}; expected a 2xx response',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw EmbeddingClientError(
        'embedding provider "${provider.id}" returned invalid JSON: $error',
      );
    }
    if (decoded is! Map || decoded['data'] is! List) {
      throw EmbeddingClientError(
        'embedding provider "${provider.id}" response needs a data list',
      );
    }
    final data = decoded['data'] as List;
    if (data.length != inputs.length) {
      throw EmbeddingClientError(
        'embedding provider "${provider.id}" returned ${data.length} vectors; '
        'expected ${inputs.length}',
      );
    }
    final ordered = List<List<double>?>.filled(inputs.length, null);
    for (final item in data) {
      if (item is! Map || item['index'] is! int || item['embedding'] is! List) {
        throw EmbeddingClientError(
          'embedding provider "${provider.id}" returned a malformed data item; '
          'expected integer index and embedding list',
        );
      }
      final index = item['index'] as int;
      if (index < 0 || index >= inputs.length || ordered[index] != null) {
        throw EmbeddingClientError(
          'embedding provider "${provider.id}" returned duplicate or '
          'out-of-range index $index; expected each index from 0 through '
          '${inputs.length - 1} exactly once',
        );
      }
      final raw = item['embedding'] as List;
      if (raw.any((value) => value is! num)) {
        throw EmbeddingClientError(
          'embedding provider "${provider.id}" returned a non-numeric vector '
          'at index $index',
        );
      }
      final vector = raw.map((value) => (value as num).toDouble()).toList();
      if (vector.length != provider.dimensions) {
        throw EmbeddingClientError(
          'embedding provider "${provider.id}" returned vector width '
          '${vector.length} at index $index; expected ${provider.dimensions}',
        );
      }
      ordered[index] = vector;
    }
    if (ordered.any((value) => value == null)) {
      final missing = ordered.indexWhere((value) => value == null);
      throw EmbeddingClientError(
        'embedding provider "${provider.id}" omitted index $missing; expected '
        'each index from 0 through ${inputs.length - 1}',
      );
    }
    return [for (final vector in ordered) vector!];
  }
}
