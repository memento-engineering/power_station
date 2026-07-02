// FT-2 — the CAPTURE-ONLY claude usage codec (bead `tg-goh`).
//
// The codec parses a `claude --output-format json` result envelope into the
// tokens/cost/turns/duration fields the keep/kill table needs. The load-bearing
// property is FAIL-SAFE: an absent / malformed / partial / non-object envelope
// yields NO fields and NEVER throws, so telemetry can never fail, gate, or delay
// a step. Pure over a string (fixture-pinned); the file-read half uses temp
// dirs. Zero I/O against real claude.
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A pinned WELL-FORMED `claude --output-format json` result envelope — the
/// exact shape the wrapped harness redirects (extra keys included, to prove the
/// codec ignores what it does not need).
const String _wellFormed = '''
{
  "type": "result",
  "subtype": "success",
  "is_error": false,
  "duration_ms": 45231,
  "duration_api_ms": 43000,
  "num_turns": 7,
  "result": "Done.",
  "session_id": "abc-123",
  "total_cost_usd": 0.1834,
  "usage": {
    "input_tokens": 15234,
    "output_tokens": 2841,
    "cache_creation_input_tokens": 0,
    "cache_read_input_tokens": 12000
  }
}
''';

void main() {
  group('FT-2 UsageReport.tryParse — the well-formed envelope', () {
    test('recovers every named field and projects the result map', () {
      final report = UsageReport.tryParse(_wellFormed);
      expect(report, isNotNull);
      expect(report!.tokensIn, 15234);
      expect(report.tokensOut, 2841);
      expect(report.costUsd, 0.1834);
      expect(report.numTurns, 7);
      expect(report.harnessDurationMs, 45231);
      // The exact map merged into grid.result.<nodePath>.* — collision-safe keys.
      expect(report.toResultFields(), {
        'tokensIn': '15234',
        'tokensOut': '2841',
        'costUsd': '0.1834',
        'numTurns': '7',
        'harnessDurationMs': '45231',
      });
    });
  });

  group('FT-2 UsageReport.tryParse — fail-safe (never throws, omits fields)', () {
    test('null / empty / whitespace content ⇒ null', () {
      expect(UsageReport.tryParse(null), isNull);
      expect(UsageReport.tryParse(''), isNull);
      expect(UsageReport.tryParse('   \n  '), isNull);
    });

    test('malformed (not JSON) content ⇒ null', () {
      expect(UsageReport.tryParse('not json at all'), isNull);
      expect(UsageReport.tryParse('{"usage": {'), isNull); // truncated
    });

    test('a non-object JSON shape ⇒ null', () {
      expect(UsageReport.tryParse('"hello"'), isNull);
      expect(UsageReport.tryParse('42'), isNull);
      expect(UsageReport.tryParse('true'), isNull);
    });

    test('a well-formed object with NO recognizable usage ⇒ null (isEmpty)', () {
      expect(UsageReport.tryParse('{"foo": "bar", "result": "hi"}'), isNull);
      expect(UsageReport.tryParse('{"usage": {}}'), isNull);
    });

    test('a PARTIAL envelope contributes only the fields it carries', () {
      // usage present, but no cost/turns/duration at top level.
      final onlyTokens = UsageReport.tryParse(
        '{"usage": {"input_tokens": 10, "output_tokens": 20}}',
      );
      expect(onlyTokens, isNotNull);
      expect(onlyTokens!.toResultFields(), {'tokensIn': '10', 'tokensOut': '20'});

      // no usage object, but the top-level cost/turns/duration are present.
      final noUsage = UsageReport.tryParse(
        '{"total_cost_usd": 0.5, "num_turns": 3, "duration_ms": 900}',
      );
      expect(noUsage, isNotNull);
      expect(noUsage!.toResultFields(), {
        'costUsd': '0.5',
        'numTurns': '3',
        'harnessDurationMs': '900',
      });
    });

    test('a wrong-typed usage object ⇒ null (no field is coerced from junk)', () {
      // usage is a string, tokens are objects — none survive the type checks.
      expect(UsageReport.tryParse('{"usage": "nope"}'), isNull);
      expect(
        UsageReport.tryParse('{"usage": {"input_tokens": {"x": 1}}}'),
        isNull,
      );
    });

    test('numeric-as-string values are parsed defensively', () {
      final report = UsageReport.tryParse(
        '{"total_cost_usd": "0.02", "usage": {"input_tokens": "100"}}',
      );
      expect(report, isNotNull);
      expect(report!.tokensIn, 100);
      expect(report.costUsd, 0.02);
    });

    test('a stream-json ARRAY: the last result-shaped member wins (defensive)',
        () {
      final arr = jsonEncode([
        {'type': 'assistant', 'message': 'thinking'},
        {
          'type': 'result',
          'num_turns': 2,
          'usage': {'input_tokens': 5, 'output_tokens': 6},
        },
      ]);
      final report = UsageReport.tryParse(arr);
      expect(report, isNotNull);
      expect(report!.tokensIn, 5);
      expect(report.tokensOut, 6);
      expect(report.numTurns, 2);
    });
  });

  group('FT-2 usageReportPath — filename sanitization', () {
    test('collapses `/` (and hostile chars) so a nodePath is a flat filename',
        () {
      expect(
        usageReportPath('tg-1/agent'),
        '.grid/telemetry/tg-1_agent.usage.json',
      );
      expect(
        usageReportPath('tg-1/review/spec-adherence'),
        '.grid/telemetry/tg-1_review_spec-adherence.usage.json',
      );
      // Any non-[A-Za-z0-9._-] collapses to `_` (defensive — never escapes the
      // telemetry dir or breaks the shell redirect).
      expect(usageReportPath('a b/c:d'), '.grid/telemetry/a_b_c_d.usage.json');
    });
  });

  group('FT-2 readUsageFields — the file-read half (temp dirs, fail-safe)', () {
    test('reads + projects a written envelope', () {
      final dir = Directory.systemTemp.createTempSync('usage-read-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const nodePath = 'tg-1/agent';
      File(p.join(dir.path, usageReportPath(nodePath)))
        ..createSync(recursive: true)
        ..writeAsStringSync(_wellFormed);
      expect(readUsageFields(dir.path, nodePath), {
        'tokensIn': '15234',
        'tokensOut': '2841',
        'costUsd': '0.1834',
        'numTurns': '7',
        'harnessDurationMs': '45231',
      });
    });

    test('an ABSENT file ⇒ empty (never throws)', () {
      final dir = Directory.systemTemp.createTempSync('usage-absent-');
      addTearDown(() => dir.deleteSync(recursive: true));
      expect(readUsageFields(dir.path, 'tg-1/agent'), isEmpty);
    });

    test('a MALFORMED file ⇒ empty (never throws)', () {
      final dir = Directory.systemTemp.createTempSync('usage-malformed-');
      addTearDown(() => dir.deleteSync(recursive: true));
      const nodePath = 'tg-1/review/regression-risk';
      File(p.join(dir.path, usageReportPath(nodePath)))
        ..createSync(recursive: true)
        ..writeAsStringSync('{ this is not json');
      expect(readUsageFields(dir.path, nodePath), isEmpty);
    });
  });
}
