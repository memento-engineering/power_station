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

/// The configuration ONE key load answers, as a tree VALUE.
///
/// Value equality over the four facts a client is built from is what makes an
/// equivalent rebuilt configuration a NO-OP: the mounted value does not change,
/// so the owning lifecycle is never handed a new dependency pass and the key is
/// never re-read. It is also the tag a landed result carries, so a result can
/// only ever be published under the request that produced it.
final class _GitHubAppClientRequest {
  const _GitHubAppClientRequest({
    required this.config,
    required this.privateKeyVar,
  });

  final GitHubAppConfig config;
  final String privateKeyVar;

  @override
  bool operator ==(Object other) =>
      other is _GitHubAppClientRequest &&
      other.config.appId == config.appId &&
      other.config.installationId == config.installationId &&
      other.config.apiBaseUri == config.apiBaseUri &&
      other.privateKeyVar == privateKeyVar;

  @override
  int get hashCode => Object.hash(
    config.appId,
    config.installationId,
    config.apiBaseUri,
    privateKeyVar,
  );
}

/// Owns the key load's dependency pass without retaining a tree reader outside
/// its own lifecycle callback (the `CapabilityHost` precedent in
/// `grid_engine`'s `circuit/capability_host.dart`).
///
/// Its ONLY field is the host State. The per-pass [TreeDependencyScope] rides
/// into the host's async load as a PARAMETER and is stored nowhere: the pass
/// that started a load is the only thing that may finish it.
final class _GitHubAppClientLifecycle implements TreeLifecycleParticipant {
  _GitHubAppClientLifecycle(this._host);

  final _GitHubAppClientAssetsState _host;

  @override
  void initState(TreeSnapshotReader reader) {}

  @override
  void didChangeDependencies(
    TreeWatchingReader reader,
    TreeDependencyScope scope,
  ) {
    // WATCH the dep: the request is mounted by the host directly above this
    // provider, so the lookup can never miss and every replacement request
    // lands here as a fresh pass.
    final request = reader.watch<_GitHubAppClientRequest>()!;
    unawaited(_host._load(scope, request));
  }

  @override
  void dispose() {}
}

final class _GitHubAppClientAssetsState
    extends SingleChildState<GitHubAppClientAssets> {
  GitHubAppClient? _client;
  Object? _failure;
  StackTrace? _failureStack;

  /// The request the client/failure in hand answers — null until the first
  /// load lands. A result is published ONLY under its own request.
  _GitHubAppClientRequest? _resultRequest;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    final assets = seed;
    final request = _GitHubAppClientRequest(
      config: assets.config,
      privateKeyVar: assets.privateKeyVar,
    );
    if (_resultRequest != request) {
      // A replacement request is in flight: the older client and the older
      // failure both answer a question nobody is asking any more, so they are
      // hidden SYNCHRONOUSLY — neither projected nor thrown — until this
      // request produces its own result.
      return _mount(request, child);
    }
    if (_failure case final failure?) {
      Error.throwWithStackTrace(failure, _failureStack!);
    }
    final client = _client;
    return _mount(
      request,
      client == null
          ? child
          : InheritedSeed<GitHubAppClient>(value: client, child: child),
    );
  }

  /// Mounts the watched [request] over the lifecycle that loads it, so the
  /// dependency pass is delivered before [child] is reached.
  Seed _mount(_GitHubAppClientRequest request, Seed child) =>
      InheritedSeed<_GitHubAppClientRequest>(
        value: request,
        child: LifecycleProvider<_GitHubAppClientLifecycle>(
          create: () => _GitHubAppClientLifecycle(this),
          child: child,
        ),
      );

  /// Resolves [request]'s private key and installs the client it authorizes.
  ///
  /// Two questions, two guards, at each continuation: `context.mounted` answers
  /// REMOVAL (this branch left the tree) and [TreeDependencyScope.isCurrent]
  /// answers STALENESS (a newer request superseded this one). Only a
  /// continuation that survives both may tag and apply its result.
  Future<void> _load(
    TreeDependencyScope scope,
    _GitHubAppClientRequest request,
  ) async {
    try {
      final privateKey = await seed.credentialLoader.resolve(
        request.privateKeyVar,
      );
      if (!context.mounted || !scope.isCurrent) return;
      if (privateKey == null) {
        setState(() {
          _resultRequest = request;
          _client = null;
          _failure = null;
          _failureStack = null;
        });
        return;
      }
      final transport = seed.transportFactory();
      final tokens = GitHubAppTokenProvider(
        config: request.config,
        privateKey: privateKey,
        transport: transport,
      );
      final replacement = GitHubAppClient(
        config: request.config,
        tokens: tokens,
        transport: transport,
      );
      setState(() {
        _resultRequest = request;
        _client = replacement;
        _failure = null;
        _failureStack = null;
      });
    } on Object catch (error, stackTrace) {
      if (!context.mounted || !scope.isCurrent) return;
      setState(() {
        _resultRequest = request;
        _client = null;
        _failure = error;
        _failureStack = stackTrace;
      });
    }
  }
}
