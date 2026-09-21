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
// So the three authored texts must carry the INVERSE question — what is
// stamped-but-unmounted work waiting ON, and which of those blockers is
// driveable GOVERNOR WORK — and the handoff must not claim `empty by design`
// until that comes back empty. Each sentence is pinned exactly, inside the
// section that owns it: a rewrite that keeps three and drops the fourth fails
// HERE, by name.
//
// The three texts carry it at DIFFERENT altitudes. The role definition is
// PUSHED — a seat pays for it on every turn — so it states the judgement and
// nothing else; the runbook is PULLED when the board reads quiet, so it owns
// the INVOCATION that answers it. That invocation is now the `mount` verb: the
// four hand-authored reads the runbook used to spell out are one command, and
// the command answers six preconditions the dance never asked about at all.
// One owner per sentence is what keeps them from drifting apart.
//
// OPEN PULL REQUESTS are the same omission one step later (bead `pow-07zx`).
// The Sweep read sessions, gates and stamped-bead blockers — all questions
// asked of work the station is still DOING — so a pull request that had left
// the agents and sat unmerged appeared nowhere. Measured 2026-09-12: NINE
// pull-request chore beads open across two stores, every one of their pull
// requests already merged, by up to nine days. The stale rows did not merely
// clutter the board: a genuinely stalled pull request — power_station#268,
// three days CONFLICTING with its own chore bead already filed — was
// INDISTINGUISHABLE from the nine that needed nothing.
//
// So the two policy owners state the OWNERSHIP RULE and point at the surfaces
// the station already has (the pull-request chore beads the GitHub intake
// mints, and the poll's own pull-request feedback). Neither enumerates
// repositories by hand: anything a verb can answer is deleted from prose, not
// duplicated into it
// (`power_station#a-station-explains-itself-through-prime-and-bounded-help`),
// and that enumeration is pinned ABSENT below.
//
// The Landing clause keeps force-with-lease inside the grant it was given:
// `memento-engineering#the-governor-force-pushes-its-own-station-branches`
// covers the station's own per-bead `grid/<bead>` delivery branches and
// nothing else, so a `decisions/*` branch stays a hand-back.
//
// Two further decisions declare `governor.md` itself as a surface, and this
// file disturbs neither:
// `power_station#the-governor-carries-a-cost-posture-ranked-under-throughput`
// and `power_station#the-vended-seat-roles-carry-no-compaction-watermark` own
// the role's `## Cost` section — and the second claims the WHOLE file against
// the retired 150k figure. The sentences pinned here live in the operating
// loop's Sweep step, name no context figure and no compaction trigger, and
// leave every Cost claim as it stands; `governor_posture_test.dart` remains
// their sole owner.
//
// SCOPE: `governor.md` is read on the CLAUDE leg, because it has no `agents/`
// twin at all. `harvest-review` is ARMED on both legs, so each leg is loaded
// from its own path and checked on its own — never compared. Each per-harness
// leg of `station_overlay` is an INDEPENDENT instruction source
// (`power_station#a-harness-may-carry-its-own-instructions` — identical
// content between legs is permitted, never required, and nothing tests for
// it), so no assertion here relates one leg's body to the other's.
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

/// The authored agents leg of the station overlay, off the same shared
/// cwd-independent package root. An independent instruction source, read here
/// only so its OWN copy of an armed skill is checked on its own terms.
String _agentsLeg() =>
    p.join(packageRoot(), 'extension', 'station_overlay', 'agents');

/// The Claude leg's harvest-review runbook — where a branch becomes a pull
/// request, and therefore where the pull request's ownership is stated.
String _claudeHarvestReview() => File(
  p.join(_claudeLeg(), 'skills', 'harvest-review', 'SKILL.md'),
).readAsStringSync();

/// The agents leg's harvest-review runbook, loaded from its own path. Armed
/// independently, so it carries its own copy of the policy or fails here by
/// name — never by comparison with [_claudeHarvestReview].
String _agentsHarvestReview() => File(
  p.join(_agentsLeg(), 'skills', 'harvest-review', 'SKILL.md'),
).readAsStringSync();

/// The four sentences the sweep PROCEDURE is made of, each keyed by the
/// failure it prevents.
///
/// They are asserted on the RUNBOOK alone. The store grammar that reaches the
/// sweep's answer has exactly one owner, and a second copy in the pushed role
/// definition drifts the moment the grammar changes — so the governor def
/// states the JUDGEMENT ([_governorSweepPolicy]) and the skill states how to
/// reach it.
///
/// The MECHANICAL half is no longer a query dance. It used to be four
/// hand-authored reads — a `dep list`, a `link ls`, a per-blocker
/// `query id=…` — which the operator had to reassemble correctly every time and
/// which said nothing at all about session occupancy, defer state or either
/// cap. The `mount` verb answers all ten preconditions in one call, so the
/// runbook CALLS it and the choreography is gone ([_retiredChoreography]).
const Map<String, String> _sweepSentences = {
  'the retired label is not mistaken for a stamp':
      'For this sweep, stamped means `grid.approved_by`, `grid.approved_at`, '
      'and `grid.approved_rev` are all present; the retired '
      '`grid.approved` label does not count.',
  'the mechanical sweep is the mount COMMAND, and it runs FIRST':
      'Before treating a stamped-but-unmounted bead as waiting, run the '
      'mount verb over it FIRST — `{{runner}} mount --json --state-root '
      '"\$(pwd)" "<bead>"` — and read its ten ordered preconditions rather '
      'than reconstructing them by hand.',
  'an UNCHECKED row is not a pass':
      '`UNCHECKED` means NOT ASKED and is never a pass: supply the '
      '`--state-root`, or record the condition as unknown.',
  'a driveable blocker is classified as GOVERNOR WORK, with a next action':
      'A blocker that is a release node or whose notes explicitly say an '
      'agent executes it is **GOVERNOR WORK**, not a human gate; list its '
      'id, title, owning store, and next executable action.',
};

/// The ten preconditions the runbook hands the operator, named so a rewrite
/// that keeps the invocation and drops the contract fails here.
const List<String> _sweepPreconditions = [
  'driveable_type',
  'validation_plan',
  'acceptance_criteria',
  'dependencies',
  'approval_stamp',
  'session_occupancy',
  'defer_state',
  'verdict_cap',
  'mount_attempt_cap',
  'live_admission',
];

/// The hand-authored query choreography the verb RETIRED. A runbook that keeps
/// one of these alive beside the command has two answers to one question, and
/// the hand-assembled one is the one that was wrong.
const List<String> _retiredChoreography = [
  'dep list <bead-id>',
  '`link ls` verb',
  'query id=<blocker-id>',
  'enumerate every OPEN blocker',
];

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

/// The three sentences that put OPEN PULL REQUESTS inside the governor's own
/// Sweep, each keyed by the failure it prevents.
///
/// Policy only, at the altitude the seat pays for on every turn: WHAT a pull
/// request obliges, and WHERE its state is read — the station's own chore
/// beads and poll feedback. The reading itself has one owner, the station's
/// loop, and a hand-rolled repository walk here would be the second copy
/// ([_handRolledEnumeration]).
const Map<String, String> _governorPullRequestPolicy = {
  'sessions, gates and blockers are not a complete Sweep on their own':
      'Sessions, gates, and stamped-bead blockers are an incomplete Sweep '
      "until open pull-request state is read from the station's pull-request "
      'chore beads and poll feedback.',
  'an open pull request with no live session is operator work, not quiet':
      'An open pull request with no live session is an OPERATOR item to '
      'rebase, queue, or close, never a quiet board.',
  'a chore bead closes when its pull request leaves the open set':
      'When a pull request leaves the open set, close its pull-request chore '
      'bead with the merge commit or pull-request URL as the receipt.',
};

/// The two sentences the LANDING step owes a pull request it just opened:
/// attribution that is stated rather than inferred, and who owns the branch
/// when it conflicts.
///
/// The force-push half is deliberately NARROW. The grant covers the station's
/// own per-bead delivery branch and no other, so the sentence carries the
/// restriction beside the grant — a reader who sees only "force-with-lease is
/// allowed" is the reader that decision exists to prevent.
const Map<String, String> _harvestLandingPullRequestPolicy = {
  'a seat-opened pull request carries an explicit reference and a way to '
          'notice it merging':
      'A pull request opened by a seat must carry an explicit bead reference '
      "through the chore bead's external_ref and/or the bead id in the "
      'pull-request body, plus either a merge watcher or the '
      "handoff's awaiting-merge queue.",
  'a conflicting per-bead delivery branch is rebased, and ONLY that branch':
      'A conflicting station-owned grid/<bead> delivery branch is governor '
      'work: rebase it and push that named branch with force-with-lease '
      'rather than handing it back; under '
      'memento-engineering#the-governor-force-pushes-its-own-station-branches, '
      'the grant is restricted to that per-bead branch, so a decisions/* '
      'branch or any other non-per-bead branch is OUT of scope and remains a '
      'hand-back.',
};

/// The sentence that makes the reported queue the STATION's queue rather than
/// this harvest's — the nine stale rows were all opened by someone else's
/// round, and a queue that only reports its own opens never showed them.
const Map<String, String> _harvestReportingPullRequestPolicy = {
  'the awaiting-merge queue is every open pull request, not just this '
          "harvest's":
      'The awaiting-merge queue contains every open pull request the station '
      'knows about, not only pull requests opened by this harvest.',
};

/// The per-repository walk none of the three prose sources may grow.
///
/// A roster loop written into an instruction file is a second copy of
/// discovery the station's own poll already owns: it starts accurate, drifts
/// silently as the roster changes, and is exactly what obligation 3 of
/// `power_station#a-station-explains-itself-through-prime-and-bounded-help`
/// deletes from prose. Matched case-insensitively, against the WHOLE source —
/// a shell loop is no better in a neighbouring section.
const List<String> _handRolledEnumeration = [
  'gh pr list',
  'for repo in',
  'for repository in',
  'for each roster repo',
  'for each roster repository',
];

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
            'own body, that $guarantee — it is the one place the sweep is '
            'spelled out',
      );
    });

    // The command's CONTRACT, not just its name: ten rows, in order.
    for (final precondition in _sweepPreconditions) {
      expect(
        runbook,
        contains('`$precondition`'),
        reason: 'the runbook names the $precondition precondition it reads',
      );
    }

    // And the dance it replaced is GONE — a second, hand-assembled answer to
    // the same question is the defect this verb exists to end.
    for (final retired in _retiredChoreography) {
      expect(
        runbook,
        isNot(contains(retired)),
        reason:
            'the runbook must not keep the manual `$retired` choreography '
            'beside the command that answers it',
      );
    }
  });

  test('the governor Sweep owns open pull-request reconciliation policy', () {
    final sweep = _section(
      _governor(),
      '1. **Sweep**',
      '2. **Diagnose**',
      of: 'agents/governor.md',
    );

    _governorPullRequestPolicy.forEach((guarantee, sentence) {
      expect(
        sweep,
        contains(sentence),
        reason:
            'the governor def’s Sweep step must state, in its own body, that '
            '$guarantee — without it a merged pull request and a stalled one '
            'are the same open row, and the stalled one waits for a human to '
            'happen to look',
      );
    });
  });

  /// Both armed legs answer the same two questions; each is asked of the leg
  /// named in [of], and of nothing else. No assertion crosses the two.
  void expectHarvestPullRequestPolicy(String source, {required String of}) {
    final landing = _section(
      source,
      '## Landing',
      '## Reporting the harvest',
      of: of,
    );

    _harvestLandingPullRequestPolicy.forEach((guarantee, sentence) {
      expect(
        landing,
        contains(sentence),
        reason:
            'the Landing section of $of must state that $guarantee — a pull '
            'request opened without it is a row nobody owns once the session '
            'that opened it is gone',
      );
    });

    final reporting = _section(
      source,
      '## Reporting the harvest',
      '## Gotchas',
      of: of,
    );

    _harvestReportingPullRequestPolicy.forEach((guarantee, sentence) {
      expect(
        reporting,
        contains(sentence),
        reason:
            'the Reporting section of $of must state that $guarantee — a '
            'queue scoped to this harvest reports zero on the very run where '
            'an older pull request has been sitting for days',
      );
    });
  }

  test('the Claude harvest-review owns open pull-request policy', () {
    expectHarvestPullRequestPolicy(
      _claudeHarvestReview(),
      of: 'claude/skills/harvest-review/SKILL.md',
    );
  });

  test('the agents harvest-review owns open pull-request policy', () {
    expectHarvestPullRequestPolicy(
      _agentsHarvestReview(),
      of: 'agents/skills/harvest-review/SKILL.md',
    );
  });

  test(
    'pull-request policy contains no hand-rolled repository enumeration',
    () {
      final sources = <String, String>{
        'agents/governor.md': _governor(),
        'claude/skills/harvest-review/SKILL.md': _claudeHarvestReview(),
        'agents/skills/harvest-review/SKILL.md': _agentsHarvestReview(),
      };

      sources.forEach((of, source) {
        final lowered = source.toLowerCase();
        for (final enumeration in _handRolledEnumeration) {
          expect(
            lowered,
            isNot(contains(enumeration)),
            reason:
                '$of must not enumerate pull requests per repository with '
                '`$enumeration` — the station owns that discovery in its own '
                'poll, '
                'and a copy in prose drifts the moment the roster changes',
          );
        }
      });
    },
  );

  test('the section extractor rejects either missing policy anchor', () {
    expect(
      () => _section(
        _governor(),
        '1. **Sweep of an absent heading**',
        '2. **Diagnose**',
        of: 'agents/governor.md',
      ),
      throwsA(isA<StateError>()),
      reason:
          'an extractor that returned nothing for a missing START would pass '
          'every sentence above vacuously',
    );

    expect(
      () => _section(
        _claudeHarvestReview(),
        '## Landing',
        '## An absent closing heading',
        of: 'claude/skills/harvest-review/SKILL.md',
      ),
      throwsA(isA<StateError>()),
      reason:
          'an extractor that ran to end-of-file for a missing END would let a '
          'sentence in any later section pass as this one’s',
    );
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
