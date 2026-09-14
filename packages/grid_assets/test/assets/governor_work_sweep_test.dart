// The GOVERNOR-WORK blocker sweep (bead `pow-i7tw`): a stamped bead that has
// not mounted is not, by that fact, waiting on a human.
//
// The sweep the governor ran read open gates, session states, and the
// mount-eligibility of stamped beads — three questions all asked of things
// that MOUNT. A release node mounts nowhere (no builder runs a chore), so it
// never appeared, and every stamped adopter behind one was classified as a
// human gate. The handoff inherited the omission, the successor trusted it,
// and the station sat with zero live sessions for 26 hours.
//
// So the three authored texts must carry the INVERSE question — enumerate the
// OPEN BLOCKERS of stamped-but-unmounted work, and classify the driveable ones
// as GOVERNOR WORK — and the handoff must not claim `empty by design` until
// that enumeration comes back empty. Each sentence is pinned exactly, inside
// the section that owns it: a rewrite that keeps three and drops the fourth
// fails HERE, by name.
//
// The three texts carry it at DIFFERENT altitudes. The role definition is
// PUSHED — a seat pays for it on every turn — so it states the judgement and
// nothing else; the runbook is PULLED when the board reads quiet, so it owns
// the store grammar that enumerates both blocker sources. One owner per
// sentence is what keeps them from drifting apart.
//
// SCOPE: this file reads the CLAUDE leg only. `governor.md` has no `agents/`
// twin at all, and each per-harness leg of `station_overlay` is an INDEPENDENT
// instruction source (`power_station#a-harness-may-carry-its-own-instructions`
// — identical content between legs is permitted, never required, and nothing
// tests for it), so nothing here reads or compares the agents leg.
//
// Offline only — reads the bundled `extension/` files.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_root.dart';

/// The authored Claude leg of the station overlay, off the shared
/// cwd-independent package root. Never a walk up from the process working
/// directory: that is a process property and `dart test` runs the suites
/// concurrently, so a walk from here could read a directory another file had
/// pointed somewhere else.
String _claudeLeg() =>
    p.join(packageRoot(), 'extension', 'station_overlay', 'claude');

/// The governor seat's own definition — the operating loop lives here.
String _governor() =>
    File(p.join(_claudeLeg(), 'agents', 'governor.md')).readAsStringSync();

/// The sweep runbook the governor is sent to when the board reads quiet.
String _stationOperations() => File(
  p.join(_claudeLeg(), 'skills', 'station-operations', 'SKILL.md'),
).readAsStringSync();

/// The session-end ritual whose board section made the false claim.
String _handoff() => File(
  p.join(_claudeLeg(), 'skills', 'handoff', 'SKILL.md'),
).readAsStringSync();

/// The four sentences the sweep PROCEDURE is made of, each keyed by the
/// failure it prevents.
///
/// They are asserted on the RUNBOOK alone. The store grammar that enumerates
/// both blocker sources has exactly one owner, and a second copy in the
/// pushed role definition drifts the moment the grammar changes — so the
/// governor def states the JUDGEMENT ([_governorSweepPolicy]) and the skill
/// states how to reach it.
const Map<String, String> _sweepSentences = {
  'the retired label is not mistaken for a stamp':
      'For this sweep, stamped means `grid.approved_by`, `grid.approved_at`, '
      'and `grid.approved_rev` are all present; the retired '
      '`grid.approved` label does not count.',
  'both blocker sources are enumerated — in-store deps AND external rows':
      'Before treating a stamped-but-unmounted bead as waiting, enumerate '
      'every OPEN blocker: read its in-store dependencies with `bd -C '
      '<work-store-root> dep list <bead-id> --json` and its cross-store '
      'dependencies — bd `external:<project>:<capability>` rows on the bead '
      "itself — with the station's `link ls` verb, which lists the external "
      'rows every armed store carries.',
  'each blocker is read in its OWNING store, and closed ones are discarded':
      'Read every unique blocker in its owning store with `bd -C '
      '<blocker-store-root> query id=<blocker-id> --all --json --limit 0`, '
      'and discard any blocker whose own status is not open.',
  'a driveable blocker is classified as GOVERNOR WORK, with a next action':
      'A blocker that is a release node or whose notes explicitly say an '
      'agent executes it is **GOVERNOR WORK**, not a human gate; list its '
      'id, title, owning store, and next executable action.',
};

/// The three sentences the governor's OWN Sweep step is made of — the same
/// guarantee as [_sweepSentences], stated as judgement a seat carries on every
/// turn rather than as a query it would have to re-run from memory.
const Map<String, String> _governorSweepPolicy = {
  'a stamped-but-unmounted bead is not a human gate until its blockers are '
          'read':
      'For a stamped-but-unmounted bead, enumerate every open blocker across '
      'in-store and cross-store dependencies before calling it a human gate.',
  'a closed blocker is not a blocker': 'Closed blockers do not count.',
  'a driveable blocker is classified as GOVERNOR WORK, with a next action':
      'A release node or a blocker whose notes say an agent executes it is '
      'GOVERNOR WORK; name its id, owning store, and next executable action.',
};

/// Grammar the Sweep step must NOT restate: the store flags and field names
/// belong to the runbook, which is pulled when it is needed, not pushed on
/// every turn.
const List<String> _sweepGrammar = ['bd -C', '--json', 'grid.approved_by'];

/// The two sentences that make `empty by design` a CONCLUSION rather than an
/// assumption the successor inherits.
const Map<String, String> _boardSentences = {
  'the claim is preconditioned on the same enumeration':
      'Before writing `empty by design`, repeat the Sweep enumeration for '
      'every stamped-but-unmounted bead across both blocker sources and '
      "inspect each open blocker's type and notes.",
  'a non-empty enumeration is written out, split governor work from human':
      'The board is empty by design only when that OPEN-blocker enumeration '
      'is empty; otherwise record every blocker, putting each release '
      'node or explicit agent-executes blocker in a **GOVERNOR WORK** row '
      'with its id, title, owning store, and next executable action, and '
      'only genuine human blockers in human-gate rows.',
};

/// The body of [source] from [start] up to (not including) [end], with every
/// run of whitespace collapsed to one space.
///
/// Scoped so a sentence that drifted into a neighbouring section cannot
/// vacuously pass, and flowed so a re-wrap of the paragraph it lives in cannot
/// falsify a sentence that is still there.
///
/// Throws a [StateError] naming the anchor it could not find: an extractor
/// that silently returned the whole file, or nothing, would make every
/// assertion below meaningless.
String _section(String source, String start, String end, {required String of}) {
  final from = source.indexOf(start);
  if (from == -1) throw StateError('no "$start" section opens $of');
  final to = source.indexOf(end, from + start.length);
  if (to == -1) {
    throw StateError('no "$end" closes the "$start" section of $of');
  }
  return source.substring(from, to).replaceAll(RegExp(r'\s+'), ' ');
}

void main() {
  test('the governor definition carries policy and the station-operations '
      'skill owns procedure', () {
    final sweep = _section(
      _governor(),
      '1. **Sweep**',
      '2. **Diagnose**',
      of: 'agents/governor.md',
    );

    _governorSweepPolicy.forEach((guarantee, sentence) {
      expect(
        sweep,
        contains(sentence),
        reason:
            'the governor def’s Sweep step must state, in its own body, that '
            '$guarantee — a stamped bead behind a governor-driveable chore '
            'reads as a human gate without it, and the station starves',
      );
    });

    for (final grammar in _sweepGrammar) {
      expect(
        sweep,
        isNot(contains(grammar)),
        reason:
            'the pushed role definition states the judgement; `$grammar` is '
            'the runbook’s to own, and a second copy drifts from it',
      );
    }

    final runbook = _section(
      _stationOperations(),
      '## Governor-work sweep',
      '## Silent-death runbook',
      of: 'skills/station-operations/SKILL.md',
    );

    _sweepSentences.forEach((guarantee, sentence) {
      expect(
        runbook,
        contains(sentence),
        reason:
            'the station-operations governor-work runbook must state, in its '
            'own body, that $guarantee — it is the one place the enumeration '
            'is spelled out',
      );
    });
  });

  test(
    'the Claude handoff board refuses an unevaluated empty-by-design claim',
    () {
      final board = _section(
        _handoff(),
        '3. **Board state**',
        '4. **In flight**',
        of: 'skills/handoff/SKILL.md',
      );

      _boardSentences.forEach((guarantee, sentence) {
        expect(
          board,
          contains(sentence),
          reason:
              'the handoff template’s board section must state that $guarantee — '
              'a successor cannot re-derive a board the predecessor never swept',
        );
      });
    },
  );
}
