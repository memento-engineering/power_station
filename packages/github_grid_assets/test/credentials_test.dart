import 'dart:io';

import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:test/test.dart';

const _path = '/operator/secrets/github-app.pem';
const _varName = 'APP_ONE_PRIVATE_KEY';

class FakeEnvironment {
  FakeEnvironment(this.values);
  final Map<String, String> values;
  Map<String, String> call() => values;
}

class FakeStat {
  FakeStat(this.value);
  final GitHubKeyFileStat value;
  var calls = 0;
  Future<GitHubKeyFileStat> call(String path) async {
    calls++;
    return value;
  }
}

class FakeRead {
  FakeRead({this.value = 'pem', this.error});
  final String value;
  final FileSystemException? error;
  var calls = 0;
  Future<String> call(String path) async {
    calls++;
    if (error case final error?) throw error;
    return value;
  }
}

void main() {
  test(
    'absent and empty configuration are inert without filesystem access',
    () async {
      for (final environment in <Map<String, String>>[
        const <String, String>{},
        const <String, String>{_varName: '  '},
      ]) {
        final stat = FakeStat(
          const GitHubKeyFileStat(type: FileSystemEntityType.file, mode: 0x180),
        );
        final read = FakeRead();
        final loader = GitHubAppCredentialLoader(
          environment: FakeEnvironment(environment).call,
          stat: stat.call,
          read: read.call,
        );
        expect(await loader.resolve(_varName), isNull);
        expect(stat.calls, 0);
        expect(read.calls, 0);
      }
    },
  );

  test('non-file binding names the configured path', () async {
    final loader = _loader(
      stat: const GitHubKeyFileStat(
        type: FileSystemEntityType.notFound,
        mode: 0,
      ),
    );
    await expectLater(
      loader.resolve(_varName),
      throwsA(
        isA<StateError>()
            .having((e) => '$e', 'message', contains(_path))
            .having((e) => '$e', 'variable', contains(_varName)),
      ),
    );
  });

  for (final mode in <int>[0x1a4, 0x1b0, 0x100]) {
    final observed = (mode & 0x1ff).toRadixString(8).padLeft(4, '0');
    test('mode $observed refuses with expected and observed modes', () async {
      final loader = _loader(
        stat: GitHubKeyFileStat(type: FileSystemEntityType.file, mode: mode),
      );
      await expectLater(
        loader.resolve(_varName),
        throwsA(
          isA<StateError>()
              .having((e) => '$e', 'path', contains(_path))
              .having((e) => '$e', 'expected', contains('0600'))
              .having((e) => '$e', 'observed', contains(observed)),
        ),
      );
    });
  }

  test('read failure names the configured path', () async {
    final read = FakeRead(error: const FileSystemException('denied'));
    final loader = _loader(
      stat: const GitHubKeyFileStat(
        type: FileSystemEntityType.file,
        mode: 0x180,
      ),
      read: read,
    );
    await expectLater(
      loader.resolve(_varName),
      throwsA(
        isA<StateError>().having((e) => '$e', 'message', contains(_path)),
      ),
    );
  });

  test('mode 0600 loads the PEM and preserves its path', () async {
    final loader = _loader(
      stat: const GitHubKeyFileStat(
        type: FileSystemEntityType.file,
        mode: 0x180,
      ),
      read: FakeRead(value: 'secret pem'),
    );
    final key = await loader.resolve(_varName);
    expect(key?.path, _path);
    expect(key?.pem, 'secret pem');
  });
}

GitHubAppCredentialLoader _loader({
  required GitHubKeyFileStat stat,
  FakeRead? read,
}) => GitHubAppCredentialLoader(
  environment: FakeEnvironment(const <String, String>{_varName: _path}).call,
  stat: FakeStat(stat).call,
  read: (read ?? FakeRead()).call,
);
