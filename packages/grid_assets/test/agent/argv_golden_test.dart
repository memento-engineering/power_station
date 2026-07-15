// The argv GOLDEN pins — the acceptance clause "pin the four classes' emitted
// RuntimeConfig BEFORE any deletion" (a silent argv change is a live-station
// regression). This file first asserts the CURRENT four harness CLASSES emit
// exact literal RuntimeConfigs; a later pass re-points these SAME literals at
// the single `spawnFor` over declared environments (byte-identity is the whole
// proof of the collapse). Pure Dart, offline.
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

void main() {
  final ws = testWorkspace('tg-1', workspaceDir: '/w/tg-1', branch: 'grid/tg-1');
  const brief = AgentBrief(task: 'BODY');
  final rendered = brief.render();

  group('claude — byte-identical across the collapse', () {
    test('with model, no usage', () {
      final old = const ClaudeHarness().spawnFor(
        config: const AgentConfig(params: {'model': 'opus'}),
        brief: brief,
        workspace: ws,
      );
      expect(
        old,
        RuntimeConfig(
          workDir: '/w/tg-1',
          command: 'claude',
          args: ['--dangerously-skip-permissions', '--model', 'opus', '-p', rendered],
          lifecycle: Lifecycle.oneTurn,
        ),
      );
    });

    test('usage-wrapped (FT-2)', () {
      final old = const ClaudeHarness().spawnFor(
        config: const AgentConfig(params: {'model': 'opus'}),
        brief: brief,
        workspace: ws,
        usageOut: '.grid/telemetry/tg-1_agent.usage.json',
      );
      expect(old.command, 'sh');
      expect(old.args.sublist(2), [
        'grid-claude', 'claude', '--dangerously-skip-permissions', '--model', 'opus',
        '--output-format', 'json', '-p', rendered,
      ]);
    });
  });
}
