/// Flow telemetry — the CAPTURE-ONLY harness usage codec (FT-2, bead `tg-goh`).
///
/// The code circuit's keep/kill table needs per-lane tokens/cost, but nothing
/// captured it: `claude -p` was run in plain print mode and only its exit code
/// was read. This library adds the capture seam WITHOUT touching agent work,
/// briefs, grading, or the route matrix:
///
///  - the operative harness runs with its declared JSON/JSONL output arguments
///    and redirects the result envelope to a per-step telemetry file
///    ([usageReportPath]) — the gating lane's rc-file `sh -c` wrapper precedent;
///  - a step's `result()` hook reads that file back through [readUsageFields]
///    ([UsageReport.tryParse] + [UsageReport.toResultFields]) and merges the
///    fields into the durable `grid.result.<nodePath>.*` payload;
///  - the envelope's `modelUsage` names the model(s) that ACTUALLY ran, captured
///    as the `model` field (beads `pow-edp` + `pow-efv`) — the ledger-side proof
///    that a critic graded on sonnet and a build ran on opus, and the only place
///    a silent mid-run model fallback would be visible.
///
/// A harness billed through a SUBSCRIPTION reports tokens but no money (bead
/// `pow-zetn`): codex's envelope has no `total_cost_usd`, so every codex lane
/// folded to a null cost and dropped out of the station's spend report the
/// moment the cost posture moved the build/spec seats onto it. So when — and
/// ONLY when — no cost is reported, the cost is DERIVED from the station's
/// declared [ModelPriceTable] and stamped [UsageCostSource.derived]; a reported
/// cost always wins and is stamped [UsageCostSource.reported]. A model with no
/// declared price keeps its tokens, reports NO cost, and raises the
/// [kUsagePriceUnknownFlare] naming it — never a silent zero.
///
/// Everything here is FAIL-SAFE: an absent, empty, or malformed envelope yields
/// NO fields — telemetry can never fail, gate, or delay a step (the acceptance
/// property). The parse is a pure function over a string (fixture-testable with
/// no I/O); only [readUsageFields] touches the filesystem.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'model_tier.dart';

/// The workspace-relative directory each step's usage telemetry lands in
/// (sibling of the committee's `.grid/critique`).
const String kTelemetryDir = '.grid/telemetry';

/// The workspace-relative usage-telemetry path for the step at [nodePath] — the
/// `--output-format json` result envelope redirect target the harness writes and
/// `result()` reads. The node path is sanitized for a filename (its `/`
/// separators — and any other filesystem-hostile char — collapse to `_`), so
/// `tg-1/review/spec-adherence` → `.grid/telemetry/tg-1_review_spec-adherence.usage.json`.
String usageReportPath(String nodePath) =>
    p.join(kTelemetryDir, '${_sanitize(nodePath)}.usage.json');

final RegExp _unsafeFilenameChar = RegExp(r'[^A-Za-z0-9._-]');

String _sanitize(String nodePath) =>
    nodePath.replaceAll(_unsafeFilenameChar, '_');

/// Where a non-null [UsageReport.costUsd] came from (bead `pow-zetn`) — durable
/// beside the number, because a report that mixes billed and estimated money
/// with no marker is a report nobody can audit.
enum UsageCostSource {
  /// The harness envelope REPORTED a billed amount (`total_cost_usd`, or the
  /// per-model `modelUsage.*.costUSD` it sums to). Authoritative.
  reported,

  /// No amount was reported: the cost is an ESTIMATE, from the station's
  /// declared per-model token prices over the token classes the envelope
  /// carried.
  derived;

  /// The stable spelling this rides into `grid.result.<nodePath>.costSource`.
  String get wire => switch (this) {
    UsageCostSource.reported => 'reported',
    UsageCostSource.derived => 'derived',
  };
}

/// The EMIT-ONLY observation sink the fail-safe usage parse names a problem
/// through — the `ExplorationTransport.flare` shape (D-8), taken as a function
/// so this codec stays dependency-free and fixture-testable with no transport.
typedef UsageFlare = void Function(String name, Map<String, String> data);

/// Raised when a run reports tokens under a NAMED model the declared
/// [ModelPriceTable] has no row for: the tokens are still recorded, the cost
/// stays null, and the flare names the model so an operator adds the price
/// (guards LOUD or GONE — the alternative, a silent $0 lane, is the exact
/// invisibility this bead exists to end).
const String kUsagePriceUnknownFlare = 'agent.usagePriceUnknown';

/// The usage fields a harness JSON/JSONL run reports — every field OPTIONAL (a
/// partial or version-skewed envelope contributes only what it carries). Pure
/// value; parse with [tryParse], project with [toResultFields].
class UsageReport {
  /// Creates the report over whatever fields were present.
  const UsageReport({
    this.tokensIn,
    this.tokensOut,
    this.cacheReadInputTokens,
    this.cacheCreationInputTokens,
    this.costUsd,
    this.costSource,
    this.premiumRequests,
    this.numTurns,
    this.harnessDurationMs,
    this.model,
  });

  /// UNCACHED prompt tokens: `usage.input_tokens`, less the `cached_input_tokens`
  /// subset a codex envelope reports INSIDE it (claude already reports the two
  /// disjointly), so the field means the same thing across harnesses and the
  /// cache-read half is never billed at the uncached rate.
  final int? tokensIn;

  /// `usage.output_tokens` — completion tokens the run produced.
  final int? tokensOut;

  /// Input tokens served from the prompt cache (`usage.cache_read_input_tokens`,
  /// or codex's `usage.cached_input_tokens`) — ABSENT when the harness reported
  /// no split, which is a different fact from a reported zero.
  final int? cacheReadInputTokens;

  /// Input tokens WRITTEN to the prompt cache
  /// (`usage.cache_creation_input_tokens`) — absent when unreported.
  final int? cacheCreationInputTokens;

  /// The run's cost in USD: the envelope's billed `total_cost_usd`, else an
  /// estimate over the declared prices ([costSource] says which).
  final num? costUsd;

  /// Whether [costUsd] was REPORTED by the harness or DERIVED from declared
  /// prices — always null exactly when [costUsd] is null.
  final UsageCostSource? costSource;

  /// `usage.premiumRequests` — premium-request consumption reported for this
  /// run. A [num] preserves fractional values if a harness emits them.
  final num? premiumRequests;

  /// `num_turns` — assistant turns the run took.
  final int? numTurns;

  /// `duration_ms`, falling back to Copilot's `usage.sessionDurationMs` — the
  /// harness-observed wall-clock duration of the run.
  final int? harnessDurationMs;

  /// The envelope's top-level `modelUsage` map KEYS — the model id(s) that
  /// ACTUALLY served the run (e.g. `claude-opus-4-8`), comma-joined in envelope
  /// key order when more than one contributed (a subagent or a FALLBACK route).
  /// Observed identity, NOT the configured `--model` param (beads `pow-edp` +
  /// `pow-efv`): the argv proves what we asked for, this proves what ran, and
  /// two ids here is exactly the silent mid-run fallback shape the role-model
  /// split exists to prevent (the fable/opus incident — an unpinned run resolved
  /// to opus, then fell back to fable). Durable on
  /// `grid.result.<nodePath>.model`, so per-bead model attribution survives
  /// worktree reaping and "did the critic really grade on sonnet?" is answerable
  /// from the ledger.
  final String? model;

  /// True when NO field was recovered (an envelope with no recognizable usage).
  bool get isEmpty =>
      tokensIn == null &&
      tokensOut == null &&
      cacheReadInputTokens == null &&
      cacheCreationInputTokens == null &&
      costUsd == null &&
      premiumRequests == null &&
      numTurns == null &&
      harnessDurationMs == null &&
      model == null;

  /// Parses a harness JSON result envelope or JSONL event stream [content],
  /// FAIL-SAFE: `null`/blank/malformed content, a non-object shape, or an
  /// envelope with no recoverable usage all yield `null` — NEVER a throw. A
  /// well-formed envelope yields whatever fields it carries (a missing field is
  /// simply omitted, not an error).
  ///
  /// [modelPrices] is the station's declared price table, consulted ONLY when
  /// the envelope reported no cost of its own (bead `pow-zetn`); empty ⇒ pure
  /// capture, exactly the pre-derivation behaviour. [flare] observes an unknown
  /// model; absent ⇒ no observation, never a failure.
  static UsageReport? tryParse(
    String? content, {
    ModelPriceTable modelPrices = const <String, ModelTokenPrice>{},
    UsageFlare? flare,
  }) {
    if (content == null) return null;
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;
    final envelope = _resultObject(_decode(trimmed));
    if (envelope == null) return null;
    final rawUsage = envelope['usage'];
    final usage = rawUsage is Map ? rawUsage : const <dynamic, dynamic>{};
    final modelUsage = envelope['modelUsage'];
    final model = _modelNames(modelUsage);
    // Codex reports `input_tokens` GROSS (the cached subset included); claude
    // reports the two disjointly. Normalize to claude's meaning so one field
    // means one thing, and a negative difference (an envelope contradicting
    // itself) contributes NO token count rather than a fabricated one.
    final grossInput =
        _asToken(usage['input_tokens']) ??
        _sumModelUsageInt(modelUsage, 'inputTokens');
    final codexCached = _asToken(usage['cached_input_tokens']);
    final cacheRead =
        _asToken(usage['cache_read_input_tokens']) ??
        codexCached ??
        _sumModelUsageInt(modelUsage, 'cacheReadInputTokens');
    final cacheCreation =
        _asToken(usage['cache_creation_input_tokens']) ??
        _sumModelUsageInt(modelUsage, 'cacheCreationInputTokens');
    final tokensIn = grossInput == null || codexCached == null
        ? grossInput
        : grossInput < codexCached
        ? null
        : grossInput - codexCached;
    final tokensOut =
        _asToken(usage['output_tokens']) ??
        _sumModelUsageInt(modelUsage, 'outputTokens');
    final cost = _usageCost(
      reportedCost:
          _asNum(envelope['total_cost_usd']) ??
          _sumModelUsageNum(modelUsage, 'costUSD'),
      model: model,
      tokensIn: tokensIn,
      tokensOut: tokensOut,
      cacheReadInputTokens: cacheRead,
      cacheCreationInputTokens: cacheCreation,
      modelPrices: modelPrices,
      flare: flare,
    );
    final report = UsageReport(
      tokensIn: tokensIn,
      tokensOut: tokensOut,
      cacheReadInputTokens: cacheRead,
      cacheCreationInputTokens: cacheCreation,
      costUsd: cost.usd,
      costSource: cost.source,
      premiumRequests: _asNum(usage['premiumRequests']),
      numTurns: _asInt(envelope['num_turns']),
      harnessDurationMs:
          _asInt(envelope['duration_ms']) ?? _asInt(usage['sessionDurationMs']),
      model: model,
    );
    return report.isEmpty ? null : report;
  }

  /// The string map merged into a step's `result()` payload — collision-safe
  /// key names (`tokensIn`/`tokensOut`/`cache_read_input_tokens`/
  /// `cache_creation_input_tokens`/`costUsd`/`costSource`/`premiumRequests`/
  /// `numTurns`/`harnessDurationMs`/`model`, distinct from `grade`/`rationale`/
  /// `verdict`/`transport`). Only present fields appear — an unreported token
  /// class is ABSENT, never a zero.
  Map<String, String> toResultFields() => {
    if (tokensIn != null) 'tokensIn': '$tokensIn',
    if (tokensOut != null) 'tokensOut': '$tokensOut',
    if (cacheReadInputTokens != null)
      'cache_read_input_tokens': '$cacheReadInputTokens',
    if (cacheCreationInputTokens != null)
      'cache_creation_input_tokens': '$cacheCreationInputTokens',
    if (costUsd != null) 'costUsd': '$costUsd',
    if (costSource != null) 'costSource': costSource!.wire,
    if (premiumRequests != null) 'premiumRequests': '$premiumRequests',
    if (numTurns != null) 'numTurns': '$numTurns',
    if (harnessDurationMs != null) 'harnessDurationMs': '$harnessDurationMs',
    if (model != null) 'model': model!,
  };
}

/// Reads + parses the usage telemetry the harness redirected for the step at
/// [nodePath] under [workspaceDir], returning the result fields to merge — an
/// EMPTY map when the file is absent, unreadable, or malformed. NEVER throws, so
/// merging usage can never fail or gate a step (the FT-2 fail-safe property).
///
/// [modelPrices] is REQUIRED, because a caller that forgets it silently drops
/// every subscription-billed lane's cost — which is the defect bead `pow-zetn`
/// closes. Every `result()` edge reads it off the ambient [AgentConfig]; the
/// optional [flare] is that edge's `ExplorationTransport.flare`.
Map<String, String> readUsageFields(
  String workspaceDir,
  String nodePath, {
  required ModelPriceTable modelPrices,
  UsageFlare? flare,
}) {
  try {
    final file = File(p.join(workspaceDir, usageReportPath(nodePath)));
    if (!file.existsSync()) return const {};
    return UsageReport.tryParse(
          file.readAsStringSync(),
          modelPrices: modelPrices,
          flare: flare,
        )?.toResultFields() ??
        const {};
  } catch (_) {
    return const {}; // any I/O surprise — fail-safe omit.
  }
}

/// Reads the RAW `result` text field out of the harness's `--output-format
/// json` envelope for the step at [nodePath] under [workspaceDir] — the
/// verdict-transport fallback (tg-291): a critic that graded cleanly but wrote
/// its verdict into stdout instead of `.grid/critique/<rubric>.json` still has
/// that text recoverable here, so a caller can attempt to parse a verdict out
/// of it. FAIL-SAFE: an absent/unreadable/malformed envelope, or one with no
/// non-blank string `result` field, yields `null` — NEVER a throw.
String? readEnvelopeResultText(String workspaceDir, String nodePath) {
  try {
    final file = File(p.join(workspaceDir, usageReportPath(nodePath)));
    if (!file.existsSync()) return null;
    final envelope = _resultObject(jsonDecode(file.readAsStringSync()));
    final result = envelope?['result'];
    return (result is String && result.trim().isNotEmpty) ? result : null;
  } catch (_) {
    return null; // any I/O or decode surprise — fail-safe omit.
  }
}

/// Decodes harness usage output: a single JSON object/array (claude
/// `--output-format json`) OR a JSONL event stream (codex `exec --json`, one JSON
/// object per line). FAIL-SAFE — non-JSON, or a JSONL with any non-JSON line,
/// yields `null` (telemetry never throws; the FT-2 property).
Object? _decode(String trimmed) {
  try {
    return jsonDecode(trimmed);
  } catch (_) {
    final events = <Object?>[];
    for (final line in const LineSplitter().convert(trimmed)) {
      final t = line.trim();
      if (t.isEmpty) continue;
      try {
        events.add(jsonDecode(t));
      } catch (_) {
        return null; // a non-JSON line — not JSONL either; fail-safe omit.
      }
    }
    return events.isEmpty ? null : events;
  }
}

/// Normalizes [decoded] to the result-envelope object: the object itself, or —
/// defensively, should a future flag emit an array of stream events — the last
/// array member that looks like a result envelope (carries a usage/cost/turns/
/// duration key). `null` when neither shape yields one.
Map<String, dynamic>? _resultObject(Object? decoded) {
  if (decoded is Map) return decoded.cast<String, dynamic>();
  if (decoded is List) {
    for (final item in decoded.reversed) {
      if (item is Map &&
          (item.containsKey('usage') ||
              item.containsKey('modelUsage') ||
              item.containsKey('total_cost_usd') ||
              item.containsKey('num_turns') ||
              item.containsKey('duration_ms'))) {
        return item.cast<String, dynamic>();
      }
    }
  }
  return null;
}

/// The `modelUsage` map's keys — the model id(s) the envelope attributes the run
/// to — comma-joined in envelope key order. Capture-only: keys ride VERBATIM (no
/// allowlist — interpretation belongs to the reader), blank/non-string keys are
/// dropped defensively, and a missing / non-map / keyless `modelUsage` yields
/// `null` — NEVER a throw (the FT-2 fail-safe property).
String? _modelNames(Object? modelUsage) {
  if (modelUsage is! Map) return null;
  final names = modelUsage.keys
      .whereType<String>()
      .map((key) => key.trim())
      .where((key) => key.isNotEmpty)
      .toList();
  return names.isEmpty ? null : names.join(',');
}

/// The run's cost and its provenance (bead `pow-zetn`).
///
/// A REPORTED amount always wins — a table can drift, a bill cannot. Absent
/// one, the declared price for the observed model prices whatever token classes
/// the envelope carried. Three deliberate refusals, each leaving the cost null:
/// no tokens at all, no model to key on, and a NAMED model with no declared
/// price (which also flares — an unpriced lane must be visibly unpriced, never
/// silently free).
({num? usd, UsageCostSource? source}) _usageCost({
  required num? reportedCost,
  required String? model,
  required int? tokensIn,
  required int? tokensOut,
  required int? cacheReadInputTokens,
  required int? cacheCreationInputTokens,
  required ModelPriceTable modelPrices,
  required UsageFlare? flare,
}) {
  if (reportedCost != null) {
    return (usd: reportedCost, source: UsageCostSource.reported);
  }
  final hasTokens =
      tokensIn != null ||
      tokensOut != null ||
      cacheReadInputTokens != null ||
      cacheCreationInputTokens != null;
  if (!hasTokens || model == null) return (usd: null, source: null);

  final price = modelPrices[_baseModelId(model)];
  if (price == null) {
    _flareUnknownModel(flare, model);
    return (usd: null, source: null);
  }
  final usd = price.costUsd(
    inputTokens: tokensIn ?? 0,
    cacheReadInputTokens: cacheReadInputTokens ?? 0,
    cacheCreationInputTokens: cacheCreationInputTokens ?? 0,
    outputTokens: tokensOut ?? 0,
  );
  // A derived ZERO is not a fact about money, it is the absence of one.
  return usd == 0
      ? (usd: null, source: null)
      : (usd: usd, source: UsageCostSource.derived);
}

/// Strips a codex-acp reasoning-effort suffix (`gpt-5.6-sol[xhigh]` →
/// `gpt-5.6-sol`) so a qualified observed id still finds its declared price.
/// Deliberately a copy of `acp_session_adapter.dart`'s `baseAcpModelId` and not
/// an import of it: this codec stays dependency-free (dart:convert + path), and
/// the adapter already depends on THIS library — importing back would close a
/// cycle for two lines.
String _baseModelId(String id) {
  final bracket = id.indexOf('[');
  return bracket == -1 ? id : id.substring(0, bracket);
}

/// Emits [kUsagePriceUnknownFlare] naming [model]. Swallows a throwing sink:
/// telemetry — and observing telemetry — never gates agent work (FT-2).
void _flareUnknownModel(UsageFlare? flare, String model) {
  try {
    flare?.call(kUsagePriceUnknownFlare, <String, String>{'model': model});
  } catch (_) {
    // The observation sink is emit-only; its failure is not the step's.
  }
}

/// A non-negative token count, or null — a negative count is junk, not a fact.
int? _asToken(Object? value) {
  final parsed = _asInt(value);
  return parsed == null || parsed < 0 ? null : parsed;
}

/// The sum of [field] across the `modelUsage` entries that report it (claude's
/// camel-case per-model counts) — the fallback when the root `usage` object
/// carries no such class. Null when nothing reported it.
int? _sumModelUsageInt(Object? modelUsage, String field) {
  if (modelUsage is! Map) return null;
  var found = false;
  var total = 0;
  for (final value in modelUsage.values) {
    if (value is! Map) continue;
    final parsed = _asToken(value[field]);
    if (parsed == null) continue;
    found = true;
    total += parsed;
  }
  return found ? total : null;
}

/// The sum of the per-model [field] across EVERY `modelUsage` entry — the
/// reported-cost fallback (`costUSD`) for an envelope that prices per model but
/// carries no `total_cost_usd`. ALL-OR-NOTHING: one entry missing the field
/// would understate the run, so the whole sum is refused (null) and the cost
/// falls through to derivation instead.
num? _sumModelUsageNum(Object? modelUsage, String field) {
  if (modelUsage is! Map) return null;
  var found = false;
  num total = 0;
  for (final entry in modelUsage.entries) {
    final key = entry.key;
    if (key is! String || key.trim().isEmpty) continue;
    final value = entry.value;
    if (value is! Map) return null;
    final parsed = _asNum(value[field]);
    if (parsed == null) return null;
    found = true;
    total += parsed;
  }
  return found ? total : null;
}

int? _asInt(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v),
  _ => null,
};

num? _asNum(Object? value) => switch (value) {
  final num v => v,
  final String v => num.tryParse(v),
  _ => null,
};

/// Renders a harness-neutral FT-2 usage envelope — the SAME JSON shape
/// [UsageReport.tryParse] and [readEnvelopeResultText] read out of claude's
/// `--output-format json` result, so a CHANNEL harness's telemetry and its
/// final text land in the step's durable result through the identical path
/// (bead `pow-39tl`).
///
/// Every field is optional: a run that reported no usage at all still renders a
/// well-formed envelope, because the ABSENCE of a telemetry file and the
/// presence of an empty-usage one are different diagnoses.
String usageEnvelopeJson({
  String? result,
  int? tokensIn,
  int? tokensOut,
  int? numTurns,
  String? model,
}) => jsonEncode(<String, Object?>{
  if (result != null) 'result': result,
  'usage': <String, Object?>{
    if (tokensIn != null) 'input_tokens': tokensIn,
    if (tokensOut != null) 'output_tokens': tokensOut,
  },
  if (numTurns != null) 'num_turns': numTurns,
  if (model != null)
    'modelUsage': <String, Object?>{model: <String, Object?>{}},
});

/// Writes [content] to the workspace-relative [usageOut] under [workspaceDir],
/// creating the telemetry directory. FAIL-SAFE (the FT-2 property): any I/O
/// surprise is swallowed, so writing telemetry can never fail, gate, or delay
/// a run. Returns whether the file landed.
bool writeUsageEnvelope({
  required String workspaceDir,
  required String usageOut,
  required String content,
}) {
  try {
    final file = File(p.join(workspaceDir, usageOut));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return true;
  } catch (_) {
    return false; // telemetry never gates.
  }
}
