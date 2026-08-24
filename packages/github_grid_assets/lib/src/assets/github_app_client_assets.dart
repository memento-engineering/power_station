import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';

import '../credentials.dart';
import '../github_app_client.dart';
import '../http_transport.dart';
import '../token_provider.dart';

/// Creates the HTTP transport owned by one GitHub App client composition.
typedef GitHubHttpTransportFactory = GitHubHttpTransport Function();

/// Creates the production GitHub HTTP transport.
GitHubHttpTransport createGitHubHttpTransport() => IoGitHubHttpTransport();

/// Provides one App-authenticated client for one seat composition.
class GitHubAppClientAssets extends SingleChildStatefulSeed {
  /// Creates a per-seat GitHub App client provider.
  const GitHubAppClientAssets({
    required this.config,
    required this.privateKeyVar,
    this.credentialLoader = const GitHubAppCredentialLoader(),
    this.transportFactory = createGitHubHttpTransport,
    super.child,
    super.key,
  });

  /// The package-local GitHub authentication identity.
  final GitHubAppConfig config;

  /// Environment-variable name containing this App's private-key path.
  final String privateKeyVar;

  /// Injected inert-or-loud credential loader.
  final GitHubAppCredentialLoader credentialLoader;

  /// Injected transport factory, invoked for each replacement client.
  final GitHubHttpTransportFactory transportFactory;

  @override
  SingleChildState<GitHubAppClientAssets> createState() =>
      _GitHubAppClientAssetsState();
}

final class _GitHubAppClientAssetsState
    extends SingleChildState<GitHubAppClientAssets> {
  GitHubAppClient? _client;
  GitHubAppConfig? _builtConfig;
  String? _builtPath;
  GitHubAppConfig? _loadingConfig;
  String? _loadingPrivateKeyVar;
  Object? _failure;
  StackTrace? _failureStack;
  var _generation = 0;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final assets = seed;
    if (!_sameConfig(assets.config, _loadingConfig) ||
        assets.privateKeyVar != _loadingPrivateKeyVar) {
      final generation = ++_generation;
      _client = null;
      _builtConfig = null;
      _builtPath = null;
      _failure = null;
      _failureStack = null;
      _loadingConfig = assets.config;
      _loadingPrivateKeyVar = assets.privateKeyVar;
      unawaited(_load(generation, assets.config, assets.privateKeyVar));
    }
    if (_failure case final failure?) {
      Error.throwWithStackTrace(failure, _failureStack!);
    }
    final client = _client;
    if (client == null || !_sameConfig(assets.config, _builtConfig)) {
      return child;
    }
    return InheritedSeed<GitHubAppClient>(value: client, child: child);
  }

  Future<void> _load(
    int generation,
    GitHubAppConfig config,
    String privateKeyVar,
  ) async {
    try {
      final privateKey = await seed.credentialLoader.resolve(privateKeyVar);
      if (!context.mounted || generation != _generation) return;
      if (privateKey == null) {
        setState(() {});
        return;
      }
      if (_sameConfig(config, _builtConfig) && privateKey.path == _builtPath) {
        return;
      }
      final transport = seed.transportFactory();
      final tokens = GitHubAppTokenProvider(
        config: config,
        privateKey: privateKey,
        transport: transport,
      );
      final replacement = GitHubAppClient(
        config: config,
        tokens: tokens,
        transport: transport,
      );
      setState(() {
        _client = replacement;
        _builtConfig = config;
        _builtPath = privateKey.path;
      });
    } on Object catch (error, stackTrace) {
      if (!context.mounted || generation != _generation) return;
      setState(() {
        _failure = error;
        _failureStack = stackTrace;
      });
    }
  }

  bool _sameConfig(GitHubAppConfig? left, GitHubAppConfig? right) =>
      left?.appId == right?.appId &&
      left?.installationId == right?.installationId &&
      left?.apiBaseUri == right?.apiBaseUri;

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}
