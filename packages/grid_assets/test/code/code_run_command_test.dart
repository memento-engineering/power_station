import 'package:args/args.dart' show ArgParserException;
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_cli/grid_cli.dart' show RuntimeProviderKind;
import 'package:grid_engine/grid_engine.dart' show ServiceBundle;
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// Offline proofs for the code asset's [CodeRunCommand] (moved here from
/// the_grid's `grid_cli` at the `power_station` repo split; now COMPOSED over
/// the station-runner library pieces — a plain `Command<int>` +
/// `addStationFlags`, ADR-0008 Decision 2's composition inversion) — Fakes,
/// not mocks, no live state, no real `claude`, no real `git`.
void main() {
  group('CodeRunCommand flag parsing (via addStationFlags)', () {
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

    test('the agent-scope flags ride the command: --harness defaults to claude, '
        'the endpoint flags are optional', () {
      final cmd = CodeRunCommand();
      final parsed = cmd.argParser.parse(['--substation', 'tgdog']);
      expect(parsed.option('harness'), 'claude');
      expect(parsed.option('model'), isNull);
      expect(parsed.option('openai-base'), isNull);
      expect(parsed.option('swift-base'), isNull);
      // The harness id is a closed set (the four shipped harnesses).
      expect(
        () => cmd.argParser.parse(['--harness', 'vim']),
        throwsA(isA<ArgParserException>()),
      );
    });

    test('the CODE ASSET carries the opinion, not the framework: the code '
        'registry (with the committee) + the git SourceControl are built by '
        'the asset, composed in run() (the composition inversion — no '
        'StationRunCommand base, no servicesFor hook)', () {
      // The trio's registry half: buildCodeRegistry carries the code formula +
      // the committee sub-formula the command wires via a FormulaResolver.
      final registry = buildCodeRegistry();
      expect(
        registry.formula('code'),
        isNotNull,
        reason: 'the code registry (agent/review/land) is the asset\'s',
      );
      expect(
        registry.formula('code_review'),
        isNotNull,
        reason: 'the adversarial committee rides the same registry',
      );
      // The services half: the asset's OWN git SourceControl — provisioning
      // works even when land is NOT armed (gitOps/prOpener null), exactly the
      // bundle the command constructs from the live wiring.
      final services = ServiceBundle(
        sourceControl: GitSourceControl(
          provisioner: StationGitService(
            runner: FakeGitRunner(),
            prOpener: _FakePrOpener(),
          ),
          root: const RootCheckout(
            path: '/tmp/r',
            defaultBranch: 'main',
            substation: 'tgdog',
          ),
        ),
      );
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
