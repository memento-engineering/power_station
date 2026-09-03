import 'package:grid_engine/grid_engine.dart';

import '../credentials.dart';

/// SELF-only GitHub actor trust for v1 intake.
final class GitHubSelfTrust implements Trust {
  /// Creates trust bound to one GitHub login.
  GitHubSelfTrust({required String githubUser})
    : githubUser = githubUser.trim().isEmpty
          ? throw ArgumentError.value(
              githubUser,
              'githubUser',
              'must not be blank',
            )
          : githubUser;

  /// Creates trust from `GITHUB_USER`; absence is refused loudly.
  ///
  /// [environment] is the injectable [EnvironmentReader] seam — it defaults to
  /// [platformEnvironment] so production reads the process environment, and a
  /// test injects its own map instead of depending on what the operator
  /// exported.
  factory GitHubSelfTrust.fromEnvironment({
    EnvironmentReader environment = platformEnvironment,
  }) {
    final value = environment()['GITHUB_USER'];
    if (value == null) {
      throw StateError('GITHUB_USER is required for GitHub intake');
    }
    return GitHubSelfTrust(githubUser: value);
  }

  /// The sole GitHub login admitted by the v1 predicate.
  final String githubUser;

  @override
  Future<TrustLevel> levelOf(ActorIdentity actor) async =>
      actor.scheme == 'github' && actor.id == githubUser
      ? TrustLevel.self
      : TrustLevel.external;
}
