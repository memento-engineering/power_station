import 'package:github_grid_assets/github_grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

void main() {
  group('GitHubSelfTrust', () {
    final trust = GitHubSelfTrust(githubUser: 'nico');

    test('admits only an exact case-sensitive GitHub identity', () async {
      expect(
        await trust.levelOf(const ActorIdentity(scheme: 'github', id: 'nico')),
        TrustLevel.self,
      );
      expect(
        await trust.levelOf(const ActorIdentity(scheme: 'github', id: 'Nico')),
        TrustLevel.external,
      );
      expect(
        await trust.levelOf(
          const ActorIdentity(scheme: 'github', id: 'somebody-else'),
        ),
        TrustLevel.external,
      );
      expect(
        await trust.levelOf(const ActorIdentity(scheme: 'gitlab', id: 'nico')),
        TrustLevel.external,
      );
    });

    test('reads GITHUB_USER from a supplied environment', () async {
      final fromEnvironment = GitHubSelfTrust.fromEnvironment(
        environment: const {'GITHUB_USER': 'nico'},
      );
      expect(fromEnvironment.githubUser, 'nico');
    });

    test('refuses absent or blank GITHUB_USER', () {
      expect(
        () => GitHubSelfTrust.fromEnvironment(environment: const {}),
        throwsStateError,
      );
      for (final value in ['', '  ']) {
        expect(
          () => GitHubSelfTrust.fromEnvironment(
            environment: {'GITHUB_USER': value},
          ),
          throwsArgumentError,
        );
      }
    });
  });
}
