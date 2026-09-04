// Bead `pow-zetn` — the usage-read EDGES, where the declared prices and the
// flare sink actually reach the FT-2 codec.
//
// The parser half is `usage_report_test.dart`. This file grades the OTHER half,
// which is the one the reported symptom lives in: a codex lane vanished from
// `traj committee-report` because `result()` folded its envelope to a null cost.
// A parser that CAN derive a cost fixes nothing until every `result()` hook
// hands it the ambient table — so each hook is driven bare here, over an
// envelope with tokens and no `total_cost_usd`, and must produce a cost.
//
// Three properties per edge:
//  1. a token-only envelope comes back WITH a derived cost + `costSource`;
//  2. the table is read off the AMBIENT `AgentConfig` (a mounted custom table
//     wins — proving the tree's value is what's read, not a baked-in const);
//  3. an unpriced model reaches the ambient transport as ONE flare.
//
// Offline: temp dirs and fakes only — no real claude, codex, or git.
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

/// A codex-shaped envelope: tokens under a PRICED model, and no billed cost.
const String _codexEnvelope =
    '{"result":"done","num_turns":2,'
    '"modelUsage":{"gpt-5.6-sol":{}},'
    '"usage":{"input_tokens":1000,"output_tokens":100}}';

/// 1000 × $4/M + 100 × $20/M, as [kUsageModelPrices] declares them.
const String _codexCostUsd = '0.006';

/// A token-bearing envelope under a model NO table here prices.
const String _unpricedEnvelope =
    '{"modelUsage":{"unpriced-codex":{}},'
    '"usage":{"input_tokens":12,"output_tokens":3}}';

/// A station arming its OWN prices: one token of input costs exactly $1, so a
/// derived cost proves the AMBIENT table was read and not a hardcoded default.
const AgentConfig _customPricedConfig = AgentConfig(
  modelPrices: <String, ModelTokenPrice>{
    'gpt-5.6-sol': ModelTokenPrice(
      inputUsdPerMillion: 1000000,
      cacheReadUsdPerMillion: 0,
      cacheCreationUsdPerMillion: 0,
      outputUsdPerMillion: 0,
    ),
  },
);

/// Writes the harness's usage envelope for the step at [nodePath].
void _writeUsage(String workspaceDir, String nodePath, String content) {
  File(p.join(workspaceDir, usageReportPath(nodePath)))
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// The ambient tree a `result()` edge reads: the workspace, the station's
/// [config], and the bundle carrying the emit-only [transport].
FakeTreeContext _context(
  String workspaceDir, {
  AgentConfig config = const AgentConfig(),
  ExplorationTransport? transport,
}) => FakeTreeContext(
  values: {
    Bead: bead('tg-1'),
    Workspace: testWorkspace(
      'tg-1',
      workspaceDir: workspaceDir,
      branch: 'grid/tg-1',
    ),
    AgentConfig: config,
    ServiceBundle: ServiceBundle(transport: transport),
  },
);

Directory _temp(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

void main() {
  group('AgentCapability.result prices a token-only envelope', () {
    const nodePath = 'tg-1/agent';

    test('derives the cost off the ambient price table', () async {
      final dir = _temp('wiring-agent-');
      _writeUsage(dir.path, nodePath, _codexEnvelope);
      final out = await const AgentCapability().result(
        _context(dir.path),
        stepArgs(nodePath),
      );
      expect(out!['costUsd'], _codexCostUsd);
      expect(out['costSource'], 'derived');
      expect(out['model'], 'gpt-5.6-sol');
    });

    test('a STATION-armed table wins — the value comes off the tree', () async {
      final dir = _temp('wiring-agent-armed-');
      _writeUsage(dir.path, nodePath, _codexEnvelope);
      final out = await const AgentCapability().result(
        _context(dir.path, config: _customPricedConfig),
        stepArgs(nodePath),
      );
      // A double renders as a double: 1000 input tokens at $1 each.
      expect(out!['costUsd'], '1000.0');
      expect(out['costSource'], 'derived');
    });

    test('an unpriced model flares on the ambient transport', () async {
      final dir = _temp('wiring-agent-unpriced-');
      final transport = RecordingExplorationTransport();
      _writeUsage(dir.path, nodePath, _unpricedEnvelope);
      final out = await const AgentCapability().result(
        _context(dir.path, transport: transport),
        stepArgs(nodePath),
      );
      expect(out, isNot(contains('costUsd')));
      expect(transport.named(kUsagePriceUnknownFlare).single.data, {
        'model': 'unpriced-codex',
      });
    });
  });

  // The SPEC seat is the one the report lost first (codex on `specify`).
  group('SpecifyCapability.result prices a token-only envelope', () {
    const nodePath = 'tg-1/spec_review/specify';

    test('derives the cost beside the carried spec', () async {
      final dir = _temp('wiring-specify-');
      _writeUsage(dir.path, nodePath, _codexEnvelope);
      final out = await const SpecifyCapability().result(
        _context(dir.path),
        stepArgs(nodePath),
      );
      expect(out!['costUsd'], _codexCostUsd);
      expect(out['costSource'], 'derived');
    });

    test('a STATION-armed table wins', () async {
      final dir = _temp('wiring-specify-armed-');
      _writeUsage(dir.path, nodePath, _codexEnvelope);
      final out = await const SpecifyCapability().result(
        _context(dir.path, config: _customPricedConfig),
        stepArgs(nodePath),
      );
      // A double renders as a double: 1000 input tokens at $1 each.
      expect(out!['costUsd'], '1000.0');
    });

    test('an unpriced model flares on the ambient transport', () async {
      final dir = _temp('wiring-specify-unpriced-');
      final transport = RecordingExplorationTransport();
      _writeUsage(dir.path, nodePath, _unpricedEnvelope);
      await const SpecifyCapability().result(
        _context(dir.path, transport: transport),
        stepArgs(nodePath),
      );
      expect(transport.named(kUsagePriceUnknownFlare).single.data, {
        'model': 'unpriced-codex',
      });
    });
  });

  group('CriticCapability.result prices a token-only envelope', () {
    const rubric = 'regression-risk';
    const nodePath = 'tg-1/review/$rubric';

    ({FakeTreeContext context, StepArgs args}) criticCtx(
      String workspaceDir, {
      AgentConfig config = const AgentConfig(),
      ExplorationTransport? transport,
    }) {
      File(p.join(workspaceDir, '.grid', 'critique', '$rubric.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'grade': 'B',
            'rationale': 'narrow',
            'nodePath': nodePath,
            'round': 0,
          }),
        );
      return (
        context: _context(workspaceDir, config: config, transport: transport),
        args: stepArgs(
          nodePath,
          params: const {'rubric': rubric, 'grid.round': '0'},
        ),
      );
    }

    test('derives the cost without touching the grade', () async {
      final dir = _temp('wiring-critic-');
      _writeUsage(dir.path, nodePath, _codexEnvelope);
      final c = criticCtx(dir.path);
      final out = await const CriticCapability().result(c.context, c.args);
      expect(out!['grade'], 'B');
      expect(out['costUsd'], _codexCostUsd);
      expect(out['costSource'], 'derived');
    });

    test('a STATION-armed table wins', () async {
      final dir = _temp('wiring-critic-armed-');
      _writeUsage(dir.path, nodePath, _codexEnvelope);
      final c = criticCtx(dir.path, config: _customPricedConfig);
      final out = await const CriticCapability().result(c.context, c.args);
      // A double renders as a double: 1000 input tokens at $1 each.
      expect(out!['costUsd'], '1000.0');
    });

    test('an unpriced model flares on the ambient transport', () async {
      final dir = _temp('wiring-critic-unpriced-');
      final transport = RecordingExplorationTransport();
      _writeUsage(dir.path, nodePath, _unpricedEnvelope);
      final c = criticCtx(dir.path, transport: transport);
      await const CriticCapability().result(c.context, c.args);
      expect(transport.named(kUsagePriceUnknownFlare).single.data, {
        'model': 'unpriced-codex',
      });
    });
  });

  group('DiscoveryLensCapability.result prices a token-only envelope', () {
    const nodePath = 'tg-1/spec_review/discovery/$kCodeLens';
    final lensArgs = stepArgs(
      nodePath,
      params: const {'lens': kCodeLens, 'grid.round': '0'},
    );

    test('derives the cost beside the round stamp', () async {
      final dir = _temp('wiring-lens-');
      _writeUsage(dir.path, nodePath, _codexEnvelope);
      final out = await const DiscoveryLensCapability().result(
        _context(dir.path),
        lensArgs,
      );
      expect(out!['costUsd'], _codexCostUsd);
      expect(out['costSource'], 'derived');
    });

    test('a STATION-armed table wins', () async {
      final dir = _temp('wiring-lens-armed-');
      _writeUsage(dir.path, nodePath, _codexEnvelope);
      final out = await const DiscoveryLensCapability().result(
        _context(dir.path, config: _customPricedConfig),
        lensArgs,
      );
      // A double renders as a double: 1000 input tokens at $1 each.
      expect(out!['costUsd'], '1000.0');
    });

    test('an unpriced model flares on the ambient transport', () async {
      final dir = _temp('wiring-lens-unpriced-');
      final transport = RecordingExplorationTransport();
      _writeUsage(dir.path, nodePath, _unpricedEnvelope);
      await const DiscoveryLensCapability().result(
        _context(dir.path, transport: transport),
        lensArgs,
      );
      expect(transport.named(kUsagePriceUnknownFlare).single.data, {
        'model': 'unpriced-codex',
      });
    });
  });

  // The DESCRIBE pass is the station's one unmetered inference call; the route
  // is what threads the ambient config and transport into it.
  group('DeliverRouteCapability prices the describe pass', () {
    const nodePath = 'tg-1/deliver';

    Future<RouteVerdict> route(
      String workspaceDir, {
      AgentConfig config = const AgentConfig(),
      ExplorationTransport? transport,
    }) =>
        DeliverRouteCapability(
          gitRunner: CannedGitRunner(
            log: 'feat(x): do a thing\n\nRefs: tg-1\x00',
          ),
          inference: FakeInferenceRunner(),
        ).route(
          FakeTreeContext(
            values: {
              Bead: bead('tg-1'),
              Workspace: testWorkspace(
                'tg-1',
                workspaceDir: workspaceDir,
                branch: 'grid/tg-1',
              ),
              AgentConfig: config,
              ServiceBundle: ServiceBundle(
                delivery: RecordingDeliveryMethod(),
                transport: transport,
              ),
            },
          ),
          stepArgs(nodePath),
        );

    test('derives the describe call cost off the ambient table', () async {
      final dir = _temp('wiring-deliver-');
      _writeUsage(dir.path, nodePath, _codexEnvelope);
      final verdict = await route(dir.path);
      expect(verdict, isA<Advance>());
      final payload = (verdict as Advance).payload!;
      expect(payload['costUsd'], _codexCostUsd);
      expect(payload['costSource'], 'derived');
    });

    test('an unpriced model flares on the route transport', () async {
      final dir = _temp('wiring-deliver-unpriced-');
      final transport = RecordingExplorationTransport();
      _writeUsage(dir.path, nodePath, _unpricedEnvelope);
      final verdict = await route(dir.path, transport: transport);
      expect((verdict as Advance).payload, isNot(contains('costUsd')));
      expect(transport.named(kUsagePriceUnknownFlare).single.data, {
        'model': 'unpriced-codex',
      });
    });
  });
}
