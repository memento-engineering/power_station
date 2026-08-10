import 'dart:convert';
import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart';

import '../github_app_client.dart';

/// Reads the origin URL for the checkout rooted at [workDir].
typedef GitRemoteReader = Future<String> Function(String workDir);

/// Opens pull requests with a per-substation GitHub App identity.
class GitHubAppPrOpener implements PrOpener {
  /// Creates an opener. [owner] and [repository] are the preferred
  /// roster-supplied coordinates; when either is blank, [remoteReader]
  /// resolves both from the checkout's origin.
  GitHubAppPrOpener({
    required GitHubAppClient client,
    String? owner,
    String? repository,
    GitRemoteReader remoteReader = readOriginRemote,
  }) : _client = client,
       _owner = owner?.trim(),
       _repository = repository?.trim(),
       _remoteReader = remoteReader;

  final GitHubAppClient _client;
  final String? _owner;
  final String? _repository;
  final GitRemoteReader _remoteReader;

  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async {
    try {
      final configuredOwner = _owner;
      final configuredRepository = _repository;
      final (owner, repository) =
          configuredOwner != null &&
              configuredOwner.isNotEmpty &&
              configuredRepository != null &&
              configuredRepository.isNotEmpty
          ? (configuredOwner, configuredRepository)
          : parseGitHubRemote(await _remoteReader(workDir));
      final response = await _client.send(
        method: 'POST',
        path:
            '/repos/${Uri.encodeComponent(owner)}/'
            '${Uri.encodeComponent(repository)}/pulls',
        jsonBody: <String, Object>{
          'title': title,
          'body': body,
          'head': branch,
          'base': baseBranch,
        },
      );
      if (response.statusCode != HttpStatus.created) {
        return PullRequestResult.failed(
          PrOpenFailure(
            _failureReason(
              response.statusCode,
              response.body,
              owner,
              repository,
            ),
          ),
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['html_url'] is! String ||
          decoded['number'] is! int) {
        return PullRequestResult.failed(
          const PrOpenFailure(
            'GitHub created the pull request but returned no usable '
            'html_url/number; inspect the repository on GitHub.',
          ),
        );
      }
      return PullRequestResult.opened(
        PullRequestRef(
          url: decoded['html_url'] as String,
          number: decoded['number'] as int,
        ),
      );
    } on Object catch (error) {
      return PullRequestResult.failed(
        PrOpenFailure(
          'Could not open the pull request with the GitHub App: $error. '
          'Verify the checkout origin, App installation, credentials, and '
          'network, then retry.',
        ),
      );
    }
  }
}

/// Reads `remote.origin.url` without consulting `gh` or its credentials.
Future<String> readOriginRemote(String workDir) async {
  final result = await Process.run('git', const <String>[
    'config',
    '--get',
    'remote.origin.url',
  ], workingDirectory: workDir);
  if (result.exitCode != 0) {
    throw StateError(
      'git could not read remote.origin.url in $workDir: '
      '${result.stderr.toString().trim()}',
    );
  }
  final value = result.stdout.toString().trim();
  if (value.isEmpty) {
    throw StateError('origin has no URL in $workDir');
  }
  return value;
}

/// Parses `git@host:owner/repo.git`, `ssh://git@host/owner/repo.git`, or
/// `https://host/owner/repo.git` into GitHub repository coordinates.
(String, String) parseGitHubRemote(String remote) {
  final value = remote.trim();
  final scp = RegExp(
    r'^[^@/]+@[^:]+:([^/]+)/(.+?)(?:\.git)?$',
  ).firstMatch(value);
  final segments = scp == null
      ? Uri.tryParse(
          value,
        )?.pathSegments.where((part) => part.isNotEmpty).toList()
      : <String>[scp.group(1)!, scp.group(2)!];
  if (segments == null || segments.length != 2) {
    throw FormatException(
      'cannot derive owner/repository from origin URL: $remote',
    );
  }
  final owner = segments[0];
  final repository = segments[1].replaceFirst(RegExp(r'\.git$'), '');
  if (owner.isEmpty || repository.isEmpty) {
    throw FormatException(
      'cannot derive owner/repository from origin URL: $remote',
    );
  }
  return (owner, repository);
}

String _failureReason(
  int status,
  String body,
  String owner,
  String repository,
) {
  String detail = body.trim();
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic> && decoded['message'] is String) {
      detail = decoded['message'] as String;
    }
  } on FormatException {
    // Retain the raw response text.
  }
  final action = switch (status) {
    401 =>
      'Check the App credentials: App ID, private key, and installation token.',
    403 => 'Check pull-request permission and the GitHub rate-limit headers.',
    404 =>
      'Install the App for $owner/$repository and verify the repository '
          'coordinates.',
    422 =>
      'A pull request may already exist for this branch; inspect open PRs and '
          'the head/base values.',
    429 => 'GitHub rate-limited the App; wait for the reset and retry.',
    _ => 'Inspect GitHub and retry after correcting the reported condition.',
  };
  return 'GitHub refused PR creation for $owner/$repository '
      '(HTTP $status${detail.isEmpty ? '' : ': $detail'}). $action';
}
