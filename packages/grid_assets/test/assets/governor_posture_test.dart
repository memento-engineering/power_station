// The vended seats' COST posture (bead `pow-8dwh`): a seat states the cost of
// its own behaviour, and the governor states the measurement that produced it.
//
// Each of the three surviving claims is pinned by its OWN marker, so an edit
// that keeps two and silently drops the third fails HERE, by name — which is
// the whole point of a posture document nobody re-measures.
//
// A fourth claim named a NUMBER — compact at 150k — and Nico retired it from
// both seats on 2026-09-18: it was measured on the governor alone, the refiner
// carried an unmeasured copy, and a seat read it as a handoff trigger. That one
// is pinned the other way round, by a test that fails if either role names the
// figure again.
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

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_root.dart';

/// This package's `extension/` dir, off the shared cwd-independent package
/// root. Never a walk up from the process working
/// directory: that is a process property and `dart test` runs the suites
/// concurrently, so a walk from here could read a directory another file had
/// pointed somewhere else.
String _extensionDir() => p.join(packageRoot(), 'extension');

/// The section heading the cost posture lives under.
const String kCostHeading = '## Cost — a request costs what the context costs';

/// The handoff-preference marker, pinned on BOTH seats: it is the rule the
/// retired watermark was mistaken for, so it is named on its own rather than
/// only as one claim among the governor's.
const String kHandoffPreference =
    '**Hand off by preference; compact only mid-thought.**';

/// The three claims the posture must carry, each by the marker that pins it.
const Map<String, String> kCostClaims = {
  'independent reads are batched into ONE message':
      '**Batch independent reads.**',
  'a tool call is billed the whole context whatever it returns':
      '**A tool call is billed the whole context.**',
  'a written handoff is preferred, with the one case compaction still wins':
      kHandoffPreference,
};

/// The measurement that tells POSTURE from preference — a reader who doubts a
/// rule can check the number it came from.
const Map<String, String> kCostMeasurement = {
  'the measurement date': '2026-09-03',
  'the request count': '14,502',
  'the per-request cost': r'$0.52',
  "this seat's tool calls per message": '1.106',
  'the contrast seat that sustains more': '1.544',
};

/// The numeric compaction watermark Nico retired on 2026-09-18. Cost stays
/// ranked under the work and the clean-boundary handoff rule stays; what goes
/// is the NUMBER and the instruction to watch a context figure for it, on
/// EVERY vended seat.
const String kRetiredWatermark = '150k';

/// The sentence each seat uses to rank its cost posture under the work it
/// buys. Cost is never a reason to leave work undriven (ADR-0004), and the
/// wording is the seat's own.
const Map<String, String> kCostRank = {
  'governor': 'it NEVER outranks the throughput rules in the mandate',
  'refiner': 'none of them is a reason to refine less',
};

/// The clean-boundary handoff rule each seat states in its own words — the
/// rule that survives the retired watermark, and the one a seat must not read
/// a context figure into.
const Map<String, String> kCleanBoundaryHandoff = {
  'governor': 'At a clean boundary, write that handoff and then EXIT',
  'refiner': 'At a clean boundary, write the handoff and then EXIT',
};

/// Verbs this bead deliberately does NOT name, because they do not exist yet:
/// the terminating watch predicate and the two bead read verbs are filed in
/// the_grid, and the doc gets a follow-up amendment once they land.
const List<String> kUnbornVerbs = ['bead board', 'bead round', 'watch --until'];

/// A vended CLAUDE-leg seat role, read off the bundled `extension/` tree.
String _roleFile(String name) => File(
  p.join(_extensionDir(), 'station_overlay', 'claude', 'agents', name),
).readAsStringSync();

void main() {
  /// Both vended seat roles, keyed by the seat name a failure should name.
  final Map<String, String> seatRoles = {
    'governor': _roleFile('governor.md'),
    'refiner': _roleFile('refiner.md'),
  };
  final governor = seatRoles['governor']!;

  /// A role's COST section body — its heading through to the next `## `
  /// heading. Every assertion below reads this rather than the whole file, so
  /// a marker that drifted into another section does not vacuously pass. The
  /// watermark fence is the one exception: it reads the WHOLE file, because a
  /// retired number is retired wherever it reappears.
  String costSectionOf(String role) {
    final start = role.indexOf(kCostHeading);
    expect(start, greaterThan(-1), reason: 'the cost section exists');
    final end = role.indexOf('\n## ', start + kCostHeading.length);
    return end == -1 ? role.substring(start) : role.substring(start, end);
  }

  /// [section] with every run of whitespace collapsed to one space, so a PROSE
  /// assertion survives a re-wrap of the paragraph it lives in. Bold MARKERS
  /// are matched against the raw body (they never span a line break);
  /// sentences are matched against this.
  String flowed(String section) => section.replaceAll(RegExp(r'\s+'), ' ');

  String costSection() => costSectionOf(governor);
  String flowedSection() => flowed(costSection());

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

  group('the cost posture Nico ruled on 2026-09-18 holds on every seat', () {
    // The surviving posture, seat by seat: what the retired watermark was
    // never load-bearing for.
    test('both vended seat roles keep the surviving cost posture', () {
      seatRoles.forEach((seat, role) {
        expect(
          role,
          contains('\n$kCostHeading\n'),
          reason: 'the $seat role still opens a cost section of its own',
        );
        final section = costSectionOf(role);
        expect(
          flowed(section),
          contains(kCostRank[seat]!),
          reason:
              'the $seat posture stays ranked under the work it buys — cost is '
              'never a reason to leave work undriven',
        );
        expect(
          section,
          contains(kHandoffPreference),
          reason: 'the $seat role keeps the handoff-preference marker',
        );
        expect(
          flowed(section),
          contains(kCleanBoundaryHandoff[seat]!),
          reason:
              'the $seat role keeps the clean-boundary handoff rule, which the '
              'retired watermark was mistaken for',
        );
      });
    });

    // The whole file, not just the Cost section: a number retired for reading
    // as a trigger is retired wherever a rewrite moves it.
    test('neither vended seat role carries the retired compaction watermark', () {
      seatRoles.forEach((seat, role) {
        expect(
          role,
          isNot(contains(kRetiredWatermark)),
          reason:
              'the $kRetiredWatermark watermark was retired from BOTH seats on '
              '2026-09-18: it was measured on one seat, was never the '
              "refiner's, and read as a handoff trigger — the $seat role names "
              'a context figure to watch again',
        );
      });
    });
  });
}
