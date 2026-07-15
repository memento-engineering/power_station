/// Flow telemetry — the CAPTURE-ONLY claude usage codec (FT-2, bead `tg-goh`).
///
/// The code circuit's keep/kill table needs per-lane tokens/cost, but nothing
/// captured it: `claude -p` was run in plain print mode and only its exit code
/// was read. This library adds the capture seam WITHOUT touching agent work,
/// briefs, grading, or the route matrix:
///
///  - the operative harness ([ClaudeHarness]) runs with `--output-format json`
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
/// Everything here is FAIL-SAFE: an absent, empty, or malformed envelope yields
/// NO fields — telemetry can never fail, gate, or delay a step (the acceptance
/// property). The parse is a pure function over a string (fixture-testable with
/// no I/O); only [readUsageFields] touches the filesystem.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

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

/// The usage fields a `claude --output-format json` run reports — every field
/// OPTIONAL (a partial or version-skewed envelope contributes only what it
/// carries). Pure value; parse with [tryParse], project with [toResultFields].
class UsageReport {
  /// Creates the report over whatever fields were present.
  const UsageReport({
    this.tokensIn,
    this.tokensOut,
    this.costUsd,
    this.numTurns,
    this.harnessDurationMs,
    this.model,
  });

  /// `usage.input_tokens` — prompt tokens the run consumed.
  final int? tokensIn;

  /// `usage.output_tokens` — completion tokens the run produced.
  final int? tokensOut;

  /// `total_cost_usd` — the run's billed cost in USD.
  final num? costUsd;

  /// `num_turns` — assistant turns the run took.
  final int? numTurns;

  /// `duration_ms` — the harness-observed wall-clock duration of the run.
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
      costUsd == null &&
      numTurns == null &&
      harnessDurationMs == null &&
      model == null;

  /// Parses a `claude --output-format json` result envelope [content],
  /// FAIL-SAFE: `null`/blank/malformed content, a non-object shape, or an
  /// envelope with no recoverable usage all yield `null` — NEVER a throw. A
  /// well-formed envelope yields whatever fields it carries (a missing field is
  /// simply omitted, not an error).
  static UsageReport? tryParse(String? content) {
    if (content == null) return null;
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;
    final envelope = _resultObject(_decode(trimmed));
    if (envelope == null) return null;
    final rawUsage = envelope['usage'];
    final usage = rawUsage is Map ? rawUsage : const <dynamic, dynamic>{};
    final report = UsageReport(
      tokensIn: _asInt(usage['input_tokens']),
      tokensOut: _asInt(usage['output_tokens']),
      costUsd: _asNum(envelope['total_cost_usd']),
      numTurns: _asInt(envelope['num_turns']),
      harnessDurationMs: _asInt(envelope['duration_ms']),
      model: _modelNames(envelope['modelUsage']),
    );
    return report.isEmpty ? null : report;
  }

  /// The string map merged into a step's `result()` payload — collision-safe
  /// key names (`tokensIn`/`tokensOut`/`costUsd`/`numTurns`/`harnessDurationMs`/
  /// `model`, distinct from `grade`/`rationale`/`verdict`/`transport`). Only
  /// present fields appear.
  Map<String, String> toResultFields() => {
    if (tokensIn != null) 'tokensIn': '$tokensIn',
    if (tokensOut != null) 'tokensOut': '$tokensOut',
    if (costUsd != null) 'costUsd': '$costUsd',
    if (numTurns != null) 'numTurns': '$numTurns',
    if (harnessDurationMs != null) 'harnessDurationMs': '$harnessDurationMs',
    if (model != null) 'model': model!,
  };
}

/// Reads + parses the usage telemetry the harness redirected for the step at
/// [nodePath] under [workspaceDir], returning the result fields to merge — an
/// EMPTY map when the file is absent, unreadable, or malformed. NEVER throws, so
/// merging usage can never fail or gate a step (the FT-2 fail-safe property).
Map<String, String> readUsageFields(String workspaceDir, String nodePath) {
  try {
    final file = File(p.join(workspaceDir, usageReportPath(nodePath)));
    if (!file.existsSync()) return const {};
    return UsageReport.tryParse(file.readAsStringSync())?.toResultFields() ??
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
