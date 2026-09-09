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

    test('keeps every workflow identity external with no repository', () async {
      expect(trust.repository, isNull);
      expect(
        await trust.levelOf(
          const ActorIdentity(
            scheme: kGitHubWorkflowScheme,
            id: 'memento/power_station',
          ),
        ),
        TrustLevel.external,
      );
    });

    test('reads GITHUB_USER from a supplied environment', () async {
      final fromEnvironment = GitHubSelfTrust.fromEnvironment(
        environment: () => const {'GITHUB_USER': 'nico'},
      );
      expect(fromEnvironment.githubUser, 'nico');
    });

    test('refuses absent or blank GITHUB_USER', () {
      expect(
        () => GitHubSelfTrust.fromEnvironment(environment: () => const {}),
        throwsStateError,
      );
      for (final value in ['', '  ']) {
        expect(
          () => GitHubSelfTrust.fromEnvironment(
            environment: () => {'GITHUB_USER': value},
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('GitHubSelfTrust github-workflow scheme', () {
    final seat = GitHubSelfTrust(
      githubUser: 'nico',
      repository: 'memento/power_station',
    );

    test('admits ONLY the seat\'s own owner/repository', () async {
      expect(
        await seat.levelOf(
          const ActorIdentity(
            scheme: kGitHubWorkflowScheme,
            id: 'memento/power_station',
          ),
        ),
        TrustLevel.self,
      );
      for (final id in [
        'forker/power_station',
        'memento/lunar_station',
        'Memento/power_station',
        'memento/power_station ',
      ]) {
        expect(
          await seat.levelOf(
            ActorIdentity(scheme: kGitHubWorkflowScheme, id: id),
          ),
          TrustLevel.external,
          reason: '$id is not this seat',
        );
      }
    });

    test('the schemes never cross', () async {
      expect(
        await seat.levelOf(
          const ActorIdentity(scheme: 'github', id: 'memento/power_station'),
        ),
        TrustLevel.external,
      );
      expect(
        await seat.levelOf(
          const ActorIdentity(scheme: kGitHubWorkflowScheme, id: 'nico'),
        ),
        TrustLevel.external,
      );
      expect(
        await seat.levelOf(const ActorIdentity(scheme: 'github', id: 'nico')),
        TrustLevel.self,
        reason: 'the human login keeps its admission',
      );
    });

    test('carries the repository through fromEnvironment', () async {
      final fromEnvironment = GitHubSelfTrust.fromEnvironment(
        environment: () => const {'GITHUB_USER': 'nico'},
        repository: 'memento/power_station',
      );
      expect(fromEnvironment.repository, 'memento/power_station');
    });

    test('refuses a blank repository rather than admitting nothing', () {
      expect(
        () => GitHubSelfTrust(githubUser: 'nico', repository: '  '),
        throwsArgumentError,
      );
    });
  });
}
