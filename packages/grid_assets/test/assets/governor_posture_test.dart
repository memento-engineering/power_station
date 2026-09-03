// The governor's COST posture (bead `pow-8dwh`): the vended seat states the
// cost of its own behaviour, with the measurement that produced it.
//
// Each of the four claims is pinned by its OWN marker, so an edit that keeps
// three and silently drops the fourth fails HERE, by name — which is the whole
// point of a posture document nobody re-measures.
//
// SCOPE: this file reads the CLAUDE leg only. The codex leg is an INDEPENDENT
// instruction source (`power_station#a-harness-may-carry-its-own-instructions`
// — "Identical content between legs is PERMITTED … but it is never REQUIRED,
// and nothing tests for it"), so nothing here compares the two. The agents
// leg's STRUCTURE stays pinned where it already is, in
// `overlay_codex_leg_test.dart`; this file does not restate it.
//
// Offline only — reads the bundled `extension/` files.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The vended assets root, through the loader that already owns resolving it
/// (package config first, cwd walk-up as fallback — so this suite runs from
/// the package dir or the repo root alike).
String _extensionDir() => PackagedAssetLoader().root;

/// The section heading the cost posture lives under.
const String kCostHeading = '## Cost — a request costs what the context costs';

/// The four claims the posture must carry, each by the marker that pins it.
const Map<String, String> kCostClaims = {
  'independent reads are batched into ONE message':
      '**Batch independent reads.**',
  'a tool call is billed the whole context whatever it returns':
      '**A tool call is billed the whole context.**',
  'compaction happens at a NAMED watermark, not at the ceiling':
      '**Compact at 150k, not at the ceiling.**',
  'a written handoff is preferred, with the one case compaction still wins':
      '**Hand off by preference; compact only mid-thought.**',
};

/// The measurement that tells POSTURE from preference — a reader who doubts a
/// rule can check the number it came from.
const Map<String, String> kCostMeasurement = {
  'the measurement date': '2026-09-03',
  'the request count': '14,502',
  'the per-request cost': r'$0.52',
  "this seat's tool calls per message": '1.106',
  'the contrast seat that sustains more': '1.544',
  'the measured compaction floor (p50)': '57,385',
};

/// Verbs this bead deliberately does NOT name, because they do not exist yet:
/// the terminating watch predicate and the two bead read verbs are filed in
/// the_grid, and the doc gets a follow-up amendment once they land.
const List<String> kUnbornVerbs = ['bead board', 'bead round', 'watch --until'];

void main() {
  final governor = File(
    p.join(
      _extensionDir(),
      'station_overlay',
      'claude',
      'agents',
      'governor.md',
    ),
  ).readAsStringSync();

  /// The COST section's OWN body — its heading through to the next `## `
  /// heading. Every assertion below reads this rather than the whole file, so
  /// a marker that drifted into another section does not vacuously pass.
  String costSection() {
    final start = governor.indexOf(kCostHeading);
    expect(start, greaterThan(-1), reason: 'the cost section exists');
    final end = governor.indexOf('\n## ', start + kCostHeading.length);
    return end == -1
        ? governor.substring(start)
        : governor.substring(start, end);
  }

  /// [costSection] with every run of whitespace collapsed to one space, so a
  /// PROSE assertion survives a re-wrap of the paragraph it lives in. Bold
  /// MARKERS are matched against the raw body (they never span a line break);
  /// sentences are matched against this.
  String flowedSection() => costSection().replaceAll(RegExp(r'\s+'), ' ');

  group('the vended governor states the cost of its own behaviour', () {
    test('the cost posture opens its own `## ` heading at a line start', () {
      expect(governor, contains('\n$kCostHeading\n'));
    });

    kCostClaims.forEach((claim, marker) {
      test('it states, by its own marker, that $claim', () {
        expect(
          costSection(),
          contains(marker),
          reason:
              'the "$claim" claim is pinned by `$marker`; a rewrite that drops '
              'it must fail here rather than silently ship a weaker posture',
        );
      });
    });

    kCostMeasurement.forEach((label, token) {
      test('it cites $label, so a reader can tell posture from preference', () {
        expect(costSection(), contains(token));
      });
    });

    test('the posture is ranked UNDER the mandate throughput rules — a cost '
        'rule is never licence for an idle station (ADR-0004)', () {
      expect(
        flowedSection(),
        contains('NEVER outranks the throughput rules in the mandate'),
      );
      expect(governor, contains('THROUGHPUT OUTRANKS CEREMONY'));
    });

    test('the section names no verb that does not exist yet, and leaves no '
        'unbound template hole (A23(1) — the installer REFUSES one)', () {
      final section = costSection();
      for (final verb in kUnbornVerbs) {
        expect(
          section,
          isNot(contains(verb)),
          reason: '`$verb` is not a verb this station has today',
        );
      }
      expect(section, isNot(contains('{{')));
    });
  });
}
