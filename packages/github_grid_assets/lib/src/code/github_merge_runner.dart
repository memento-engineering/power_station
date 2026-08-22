library;

import 'dart:io';

/// The GitHub command seam needed by merge delivery postures.
abstract interface class GitHubMergeRunner {
  /// Enables native auto-merge for [prUrl].
  Future<GitHubMergeResult> enableAutoMerge(String workDir, String prUrl);

  /// Determines whether [base] is protected.
  Future<GitHubProtectionResult> protection(String workDir, String base);
}

/// Result of requesting native auto-merge.
sealed class GitHubMergeResult {
  const GitHubMergeResult();
}

/// Native auto-merge was enabled.
final class GitHubMergeEnabled extends GitHubMergeResult {
  const GitHubMergeEnabled();
}

/// Native auto-merge was refused.
final class GitHubMergeRefused extends GitHubMergeResult {
  const GitHubMergeRefused(this.reason);

  /// The bounded refusal reason.
  final String reason;
}

/// Result of probing base-branch protection.
sealed class GitHubProtectionResult {
  const GitHubProtectionResult();
}

/// The base branch is protected.
final class GitHubProtected extends GitHubProtectionResult {
  const GitHubProtected();
}

/// The base branch is not protected.
final class GitHubUnprotected extends GitHubProtectionResult {
  const GitHubUnprotected();
}

/// Branch protection could not be determined safely.
final class GitHubProtectionProbeFailed extends GitHubProtectionResult {
  const GitHubProtectionProbeFailed(this.reason);

  /// The bounded failure reason.
  final String reason;
}

/// Runs the minimal `gh` commands for native auto-merge and protection probes.
final class SystemGitHubMergeRunner implements GitHubMergeRunner {
  const SystemGitHubMergeRunner({this.executable = 'gh'});

  /// Executable used for GitHub CLI calls.
  final String executable;

  @override
  Future<GitHubMergeResult> enableAutoMerge(
    String workDir,
    String prUrl,
  ) async {
    try {
      final result = await Process.run(
        executable,
        ['pr', 'merge', prUrl, '--auto'],
        workingDirectory: workDir,
        runInShell: false,
      );
      if (result.exitCode == 0) return const GitHubMergeEnabled();
      return GitHubMergeRefused(_reason(result));
    } on ProcessException catch (error) {
      return GitHubMergeRefused(_bounded('$error'));
    }
  }

  @override
  Future<GitHubProtectionResult> protection(String workDir, String base) async {
    try {
      final result = await Process.run(
        executable,
        [
          'api',
          'repos/{owner}/{repo}/branches/${Uri.encodeComponent(base)}/protection',
          '--silent',
        ],
        workingDirectory: workDir,
        runInShell: false,
      );
      if (result.exitCode == 0) return const GitHubProtected();
      final reason = _reason(result);
      if (reason.contains('HTTP 404')) return const GitHubUnprotected();
      return GitHubProtectionProbeFailed(reason);
    } on ProcessException catch (error) {
      return GitHubProtectionProbeFailed(_bounded('$error'));
    }
  }

  String _reason(ProcessResult result) => _bounded(
    '${result.stdout}${result.stderr}'.trim().isEmpty
        ? 'gh exited ${result.exitCode}'
        : '${result.stdout}${result.stderr}'.trim(),
  );

  String _bounded(String value) =>
      value.length <= 500 ? value : '${value.substring(0, 500)}…';
}
