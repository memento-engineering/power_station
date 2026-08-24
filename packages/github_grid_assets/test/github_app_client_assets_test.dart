import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart' as sdk;
import 'package:test/test.dart';

const _oneVar = 'APP_ONE_PRIVATE_KEY';
const _twoVar = 'APP_TWO_PRIVATE_KEY';
const _onePath = 'test/fixtures/github_app_test_private.pem';
const _twoPath = 'test/fixtures/github_app_test_private_two.pem';

const _onePublicKey = '''-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw/ptIEdI4c2ovZNN0Syl
vYU5puXy9fy8v2moG1taODddq4mbfwMDLCclAMCwNnBwDemkYISUXOBC4jdm/rcW
Fxq5uJImtfK/EUudDxgHFpb/B6YKtpXXW+MPz9H8SNy+bcZBPuNXwpyIKC2Y8yNY
msj30vRQvOy78IT1xR6MrcF86RrkxNZqwYnrMPgwj/HyMKRB/X04uIh/LAMdxXhU
bvVTAIH/NmvSZq5mWoUiVLGBj4/kJqkQ4Qrj19BknHzaqBFNGi1oNjaGsLUsW35Z
vH0YfIQiiN/cBiUTMN5HFPE7o8F49gT+WW7wvJ2zlE1S2G6qkpmp/gdbnyDJFYnN
xQIDAQAB
-----END PUBLIC KEY-----''';

const _twoPublicKey = '''-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAs5jhfX2HDMp0QPcYNak+
JRf+cFC239kLKTTiKEi82Te76mqSNvmx3dcdzxtHqaEHw4STTzyx/PPG+J7xUpMn
CH5vFBB8WFr7EkjDq5QzL5wI5IMz1dXttGhCpXmJ93ebUdkFX8VpfSM+/OfgjGZs
Zno3nsZZIp15nTGClXB70ohzbWvTNls7Wc+ME/Uxg9weTRdB1QY5SlAaIsFSyVU+
ORLfN0E1uF3pITVnKHZHTQJucJVHvneiSsG1kflL+YHYNjAXyeNc//6C7YCSd4FN
wiV87q7NM6AH9BHQQwIcqpM38EKBJJ4nlFDFQ+R9sbKd448dEbD0lMXFY/tTAco8
mQIDAQAB
-----END PUBLIC KEY-----''';

class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

class _Probe extends StatelessSeed {
  const _Probe(this.observe);
  final void Function(GitHubAppClient?) observe;

  @override
  Seed build(TreeContext context) {
    observe(context.dependOnInheritedSeedOfExactType<GitHubAppClient>());
    return const _Leaf();
  }
}

class _Host extends StatefulSeed {
  const _Host({required this.onCreate, required this.describe});
  final void Function(_HostState) onCreate;
  final Seed Function() describe;

  @override
  State<_Host> createState() => _HostState();
}

class _Siblings extends MultiChildSeed {
  const _Siblings({required super.children});
}

class _HostState extends State<_Host> {
  Seed Function()? _next;
  @override
  void initState() => seed.onCreate(this);
  void swap(Seed Function() describe) => setState(() => _next = describe);
  @override
  Seed build(TreeContext context) => (_next ?? seed.describe)();
}

class _FakeStat {
  _FakeStat(this.values);
  final Map<String, GitHubKeyFileStat> values;
  var calls = 0;
  Future<GitHubKeyFileStat> call(String path) async {
    calls++;
    return values[path] ??
        const GitHubKeyFileStat(type: FileSystemEntityType.notFound, mode: 0);
  }
}

class _FakeRead {
  var calls = 0;
  Future<String> call(String path) async {
    calls++;
    return File(path).readAsString();
  }
}

class _FakeTransport implements GitHubHttpTransport {
  final bearerTokens = <String>[];
  @override
  Future<GitHubHttpResponse> send(GitHubHttpRequest request) async {
    if (request.uri.path.endsWith('/access_tokens')) {
      bearerTokens.add(request.headers['Authorization']!.substring(7));
      return GitHubHttpResponse(
        statusCode: 201,
        body: jsonEncode(<String, Object>{
          'token': 'installation-token',
          'expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        }),
      );
    }
    return const GitHubHttpResponse(statusCode: 200, body: '{}');
  }
}

GitHubAppConfig _config(String appId, {int installationId = 1}) =>
    GitHubAppConfig(appId: appId, installationId: installationId);

GitHubAppCredentialLoader _loader(
  Map<String, String> environment,
  _FakeStat stat,
  _FakeRead read,
) => GitHubAppCredentialLoader(
  environment: () => environment,
  stat: stat.call,
  read: read.call,
);

Seed _assets({
  required GitHubAppConfig config,
  required String privateKeyVar,
  required GitHubAppCredentialLoader loader,
  required GitHubHttpTransport Function() transportFactory,
  required void Function(GitHubAppClient?) observe,
}) => GitHubAppClientAssets(
  config: config,
  privateKeyVar: privateKeyVar,
  credentialLoader: loader,
  transportFactory: transportFactory,
  child: _Probe(observe),
);

Future<void> _settle(TreeOwner owner) async {
  for (var i = 0; i < 3; i++) {
    await pumpEventQueue();
    owner.flush();
  }
}

Future<void> _send(GitHubAppClient client) async {
  await client.send(method: 'GET', path: '/repos/o/r');
}

void _verify(_FakeTransport transport, String publicKey) {
  expect(transport.bearerTokens, hasLength(1));
  expect(
    () => JWT.verify(transport.bearerTokens.single, RSAPublicKey(publicKey)),
    returnsNormally,
  );
}

void main() {
  group('GitHubAppClientAssets', () {
    test(
      'unset and blank variables provide no client and perform no file IO',
      () async {
        for (final values in <Map<String, String>>[
          const {},
          const {_oneVar: '  '},
        ]) {
          final stat = _FakeStat(const {});
          final read = _FakeRead();
          var factories = 0;
          GitHubAppClient? observed;
          final owner = TreeOwner();
          addTearDown(owner.dispose);
          owner.mountRoot(
            sdk.ProviderScope(
              child: _assets(
                config: _config('one'),
                privateKeyVar: _oneVar,
                loader: _loader(values, stat, read),
                transportFactory: () {
                  factories++;
                  return _FakeTransport();
                },
                observe: (value) => observed = value,
              ),
            ),
          );
          owner.flush();
          await _settle(owner);
          expect(observed, isNull);
          expect((stat.calls, read.calls, factories), (0, 0, 0));
        }
      },
    );

    test(
      '0600 PEM provides a client whose token exchange carries a valid JWT',
      () async {
        final stat = _FakeStat(const {
          _onePath: GitHubKeyFileStat(
            type: FileSystemEntityType.file,
            mode: 0x180,
          ),
        });
        final read = _FakeRead();
        final transport = _FakeTransport();
        GitHubAppClient? observed;
        final owner = TreeOwner();
        addTearDown(owner.dispose);
        owner.mountRoot(
          sdk.ProviderScope(
            child: _assets(
              config: _config('one'),
              privateKeyVar: _oneVar,
              loader: _loader(const {_oneVar: _onePath}, stat, read),
              transportFactory: () => transport,
              observe: (value) => observed = value,
            ),
          ),
        );
        owner.flush();
        await _settle(owner);
        await _send(observed!);
        _verify(transport, _onePublicKey);
        expect((stat.calls, read.calls), (1, 1));
      },
    );

    test(
      'missing file and wrong mode surface StateError from the asset',
      () async {
        for (final fileStat in <GitHubKeyFileStat>[
          const GitHubKeyFileStat(type: FileSystemEntityType.notFound, mode: 0),
          const GitHubKeyFileStat(type: FileSystemEntityType.file, mode: 0x1a4),
        ]) {
          final stat = _FakeStat({_onePath: fileStat});
          final read = _FakeRead();
          var factories = 0;
          final owner = TreeOwner();
          addTearDown(owner.dispose);
          owner.mountRoot(
            sdk.ProviderScope(
              child: _assets(
                config: _config('one'),
                privateKeyVar: _oneVar,
                loader: _loader(const {_oneVar: _onePath}, stat, read),
                transportFactory: () {
                  factories++;
                  return _FakeTransport();
                },
                observe: (_) {},
              ),
            ),
          );
          owner.flush();
          await pumpEventQueue();
          expect(owner.flush, throwsA(isA<StateError>()));
          expect(factories, 0);
        }
      },
    );

    test(
      'config or resolved path change replaces; unchanged identity retains',
      () async {
        final stat = _FakeStat(const {
          _onePath: GitHubKeyFileStat(
            type: FileSystemEntityType.file,
            mode: 0x180,
          ),
          _twoPath: GitHubKeyFileStat(
            type: FileSystemEntityType.file,
            mode: 0x180,
          ),
        });
        final read = _FakeRead();
        final loader = _loader(
          const {_oneVar: _onePath, _twoVar: _twoPath},
          stat,
          read,
        );
        final observations = <GitHubAppClient?>[];
        var factories = 0;
        late _HostState host;
        Seed describe(String appId, String privateKeyVar) => _assets(
          config: _config(appId),
          privateKeyVar: privateKeyVar,
          loader: loader,
          transportFactory: () {
            factories++;
            return _FakeTransport();
          },
          observe: observations.add,
        );
        final owner = TreeOwner();
        addTearDown(owner.dispose);
        owner.mountRoot(
          sdk.ProviderScope(
            child: _Host(
              onCreate: (value) => host = value,
              describe: () => describe('one', _oneVar),
            ),
          ),
        );
        owner.flush();
        await _settle(owner);
        final first = observations.last;
        host.swap(() => describe('one', _oneVar));
        owner.flush();
        await _settle(owner);
        expect(observations.last, same(first));
        expect(factories, 1);
        host.swap(() => describe('one', _twoVar));
        owner.flush();
        await _settle(owner);
        expect(observations.last, isNot(same(first)));
        expect(factories, 2);
        final second = observations.last;
        host.swap(() => describe('two', _twoVar));
        owner.flush();
        await _settle(owner);
        expect(observations.last, isNot(same(second)));
        expect(factories, 3);
      },
    );

    test(
      'sibling variable names load distinct keys and sign with matching PEMs',
      () async {
        final stat = _FakeStat(const {
          _onePath: GitHubKeyFileStat(
            type: FileSystemEntityType.file,
            mode: 0x180,
          ),
          _twoPath: GitHubKeyFileStat(
            type: FileSystemEntityType.file,
            mode: 0x180,
          ),
        });
        final read = _FakeRead();
        final environment = const {_oneVar: _onePath, _twoVar: _twoPath};
        final loader = _loader(environment, stat, read);
        final oneTransport = _FakeTransport();
        final twoTransport = _FakeTransport();
        GitHubAppClient? one;
        GitHubAppClient? two;
        final owner = TreeOwner();
        addTearDown(owner.dispose);
        owner.mountRoot(
          sdk.ProviderScope(
            child: _Siblings(
              children: [
                _assets(
                  config: _config('one'),
                  privateKeyVar: _oneVar,
                  loader: loader,
                  transportFactory: () => oneTransport,
                  observe: (value) => one = value,
                ),
                _assets(
                  config: _config('two', installationId: 2),
                  privateKeyVar: _twoVar,
                  loader: loader,
                  transportFactory: () => twoTransport,
                  observe: (value) => two = value,
                ),
              ],
            ),
          ),
        );
        owner.flush();
        await _settle(owner);
        expect(two, isNot(same(one)));
        await _send(one!);
        await _send(two!);
        _verify(oneTransport, _onePublicKey);
        _verify(twoTransport, _twoPublicKey);
      },
    );
  });
}
