import 'dart:io';

/// Environment variable containing the external GitHub App key file path.
const kGitHubAppKeyPathEnvironment = 'GC_GITHUB_APP_KEY_PATH';

/// Non-secret identifiers and endpoint configuration for a GitHub App.
class GitHubAppConfig {
  /// Creates GitHub App configuration.
  GitHubAppConfig({
    required this.appId,
    required this.installationId,
    Uri? apiBaseUri,
  }) : apiBaseUri = apiBaseUri ?? Uri.https('api.github.com', '');

  /// The GitHub App identifier used as the JWT issuer.
  final String appId;

  /// The installation whose access tokens are requested.
  final int installationId;

  /// The base URI for GitHub REST API requests.
  final Uri apiBaseUri;
}

/// An operator-provisioned GitHub App private key loaded from disk.
class GitHubAppPrivateKey {
  /// Creates a private key value with its source path.
  const GitHubAppPrivateKey({required this.path, required this.pem});

  /// The external file path from which the key was loaded.
  final String path;

  /// The PEM-encoded RSA private key.
  final String pem;
}

/// File metadata used to enforce the private key storage policy.
class GitHubKeyFileStat {
  /// Creates key file metadata.
  const GitHubKeyFileStat({required this.type, required this.mode});

  /// The kind of filesystem entity at the configured path.
  final FileSystemEntityType type;

  /// The platform file mode, including its POSIX permission bits.
  final int mode;
}

/// Reads the current process environment.
typedef EnvironmentReader = Map<String, String> Function();

/// Reads filesystem metadata for a key path.
typedef KeyFileStatReader = Future<GitHubKeyFileStat> Function(String path);

/// Reads the PEM contents at a key path.
typedef KeyFileReader = Future<String> Function(String path);

/// Resolves a GitHub App private key with inert-or-loud semantics.
class GitHubAppCredentialLoader {
  /// Creates a loader, optionally replacing platform operations for testing.
  GitHubAppCredentialLoader({
    EnvironmentReader environment = platformEnvironment,
    KeyFileStatReader stat = platformStat,
    KeyFileReader read = platformRead,
  }) : _environment = environment,
       _stat = stat,
       _read = read;

  final EnvironmentReader _environment;
  final KeyFileStatReader _stat;
  final KeyFileReader _read;

  /// Returns `null` when unconfigured, otherwise loads a guarded key file.
  Future<GitHubAppPrivateKey?> resolve() async {
    final path = _environment()[kGitHubAppKeyPathEnvironment]?.trim() ?? '';
    if (path.isEmpty) return null;
    final fileStat = await _stat(path);
    if (fileStat.type != FileSystemEntityType.file) {
      throw StateError(
        '$kGitHubAppKeyPathEnvironment points to missing/non-file key: $path',
      );
    }
    final permissions = fileStat.mode & 0x1ff;
    if (permissions != 0x180) {
      final octal = permissions.toRadixString(8).padLeft(4, '0');
      throw StateError(
        'GitHub App key must be mode 0600; found $octal at $path',
      );
    }
    try {
      return GitHubAppPrivateKey(path: path, pem: await _read(path));
    } on FileSystemException catch (error) {
      throw StateError('Cannot read GitHub App key at $path: ${error.message}');
    }
  }
}

/// Returns the current process environment.
Map<String, String> platformEnvironment() => Platform.environment;

/// Reads platform file metadata for [path].
Future<GitHubKeyFileStat> platformStat(String path) async {
  final value = await FileStat.stat(path);
  return GitHubKeyFileStat(type: value.type, mode: value.mode);
}

/// Reads the file at [path] as text.
Future<String> platformRead(String path) => File(path).readAsString();
