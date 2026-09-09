import 'package:grid_engine/grid_engine.dart';

import '../credentials.dart';

/// The [ActorIdentity] scheme carrying a repository's OWN workflow identity.
///
/// A workflow run has no human author, so it cannot be represented under the
/// `github` login scheme. Its id is `OWNER/REPOSITORY` — the repository whose
/// workflow file produced the run.
const String kGitHubWorkflowScheme = 'github-workflow';

/// SELF-only GitHub actor trust for v1 intake.
///
/// Exactly two identities are SELF: the one admitted human [githubUser], and —
/// when the seat declares its own [repository] — that repository's own
/// workflow identity under [kGitHubWorkflowScheme]. Every other login, every
/// other repository and every other scheme is EXTERNAL, so a fork's run and a
/// third party's issue are refused by the same predicate.
final class GitHubSelfTrust implements Trust {
  /// Creates trust bound to one GitHub login and, optionally, one repository.
  GitHubSelfTrust({required String githubUser, String? repository})
    : githubUser = githubUser.trim().isEmpty
          ? throw ArgumentError.value(
              githubUser,
              'githubUser',
              'must not be blank',
            )
          : githubUser,
      repository = switch (repository) {
        null => null,
        final value when value.trim().isEmpty => throw ArgumentError.value(
          repository,
          'repository',
          'must not be blank',
        ),
        final value => value,
      };

  /// Creates trust from `GITHUB_USER`; absence is refused loudly.
  ///
  /// [environment] is the injectable [EnvironmentReader] seam — it defaults to
  /// [platformEnvironment] so production reads the process environment, and a
  /// test injects its own map instead of depending on what the operator
  /// exported.
  factory GitHubSelfTrust.fromEnvironment({
    EnvironmentReader environment = platformEnvironment,
    String? repository,
  }) {
    final value = environment()['GITHUB_USER'];
    if (value == null) {
      throw StateError('GITHUB_USER is required for GitHub intake');
    }
    return GitHubSelfTrust(githubUser: value, repository: repository);
  }

  /// The sole GitHub login admitted by the v1 predicate.
  final String githubUser;

  /// The seat's own `OWNER/REPOSITORY`, or null when no workflow identity is
  /// admitted at all.
  final String? repository;

  @override
  Future<TrustLevel> levelOf(ActorIdentity actor) async => switch (actor) {
    ActorIdentity(scheme: 'github', :final id) when id == githubUser =>
      TrustLevel.self,
    ActorIdentity(scheme: kGitHubWorkflowScheme, :final id)
        when repository != null && id == repository =>
      TrustLevel.self,
    _ => TrustLevel.external,
  };
}
