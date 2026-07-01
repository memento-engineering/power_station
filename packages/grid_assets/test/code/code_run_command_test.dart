import 'package:grid_assets/grid_assets.dart';
import 'package:grid_cli/grid_cli.dart' show RuntimeProviderKind;
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// Offline proofs for the code asset's [CodeRunCommand] (moved here from
/// the_grid's `grid_cli` at the `power_station` repo split) — Fakes, not mocks,
/// no live state, no real `claude`, no real `git`.
void main() {
  group('CodeRunCommand flag parsing (via the StationRunCommand base)', () {
    test('--dry-run is the SAFE DEFAULT (true when unspecified)', () {
      final cmd = CodeRunCommand();
      final parsed = cmd.argParser.parse(['--substation', 'tgdog']);
      expect(parsed.flag('dry-run'), isTrue);
    });

    test('--provider defaults to subprocess', () {
      final cmd = CodeRunCommand();
      final parsed = cmd.argParser.parse(['--substation', 'tgdog']);
      expect(parsed.option('provider'), 'subprocess');
      expect(
        RuntimeProviderKind.parse(parsed.option('provider')),
        RuntimeProviderKind.subprocess,
      );
    });

    test('--substation and --owner both feed the one allow-set', () {
      final cmd = CodeRunCommand();
      final parsed = cmd.argParser.parse([
        '--substation',
        'tgdog',
        '--owner',
        'other',
      ]);
      final substations = <String>{
        ...parsed.multiOption('substation'),
        ...parsed.multiOption('owner'),
      };
      expect(substations, {'tgdog', 'other'});
    });

    test('--no-dry-run is the explicit live-arm opt-in', () {
      final cmd = CodeRunCommand();
      final parsed = cmd.argParser.parse([
        '--substation',
        'tgdog',
        '--no-dry-run',
      ]);
      expect(parsed.flag('dry-run'), isFalse);
    });

    test('the CODE ASSET carries the opinion, not the framework: the trio + a '
        'git-SourceControl servicesFor live on CodeRunCommand', () {
      final cmd = CodeRunCommand();
      // The trio is the command's (the composer requires it, defaults nothing).
      expect(cmd.resolver, isNotNull);
      expect(
        cmd.registry.formula('code'),
        isNotNull,
        reason: 'the code registry (agent/review/land) rides the command',
      );
      // servicesFor builds the git SourceControl from the live wiring.
      final services = cmd.servicesFor!((
        git: StationGitService(
          runner: FakeGitRunner(),
          prOpener: _FakePrOpener(),
        ),
        workRoot: const RootCheckout(
          path: '/tmp/r',
          defaultBranch: 'main',
          substation: 'tgdog',
        ),
        gitOps: null,
        prOpener: null,
      ));
      expect(
        services.sourceControl,
        isNotNull,
        reason: 'the code asset supplies provisioning source control',
      );
      expect(
        services.sourceControl!.canLand,
        isFalse,
        reason: 'land ops null (not armed) → commit-only posture',
      );
    });
  });
}

// =============================================================================
// Fakes (Fakes, not mocks) — local copies so this suite is self-contained.
// =============================================================================

class FakeGitRunner implements GitRunner {
  final List<List<String>> calls = [];

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async {
    calls.add(List<String>.unmodifiable(args));
    return const GitRunResult(exitCode: 0, output: '');
  }
}

class _FakePrOpener implements PrOpener {
  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async => PullRequestResult.opened(
    PullRequestRef(url: 'https://example.test/pr/1', number: 1),
  );
}
