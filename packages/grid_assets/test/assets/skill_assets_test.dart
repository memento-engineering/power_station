// The vended SKILLS (bead `pow-88p`) — the agentic halves of the coupled
// skill+command pairs (ADR-0001), shipped as Packaged AI Assets under
// `extension/station_overlay/skills/<id>/SKILL.md` and rendered by
// [PackagedAssetLoader].
//
// Pins the bead's acceptance:
//   - `discover` is VENDED from grid_assets (loads, renders, is in the
//     manifest) and dispatches on arg shape (topic / advisory / directed);
//   - its research CALLS the vended `search --json` Command — deterministic,
//     roster-driven — and never re-derives cross-store search by inference
//     (the ad-hoc `bd` query forms are FENCED out of the skill body);
//   - on the human's yes it files a bead (durable + staged, `bd create`)
//     and can kick off `specify`.
//
// Offline only — reads the bundled `extension/` files; no live anything.
import 'dart:convert';
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_assets/station_asset_registry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../support/package_root.dart';

/// This package's `extension/` dir, off the shared cwd-independent package
/// root. Never a walk up from the process working
/// directory: that is a process property and `dart test` runs the suites
/// concurrently, so a walk from here could read a directory another file had
/// pointed somewhere else.
String _extensionDir() => p.join(packageRoot(), 'extension');

/// The two INDEPENDENT instruction legs of the station overlay. A harness may
/// carry its own instructions, so identical content between them is permitted
/// and is the common case — but it is never required, and nothing here
/// compares one leg's bytes to the other's. Each leg is asserted on its own.
const List<String> _skillLegs = ['claude', 'agents'];

/// Renders one LEG's SKILL.md for [skillId], binding every `{{key}}` from
/// [args]. [PackagedAssetLoader.renderSkill] only reaches the claude leg, so
/// the agents leg gets the same substitution here — including the same LOUD
/// refusal when a hole survives, because an installed skill has no unbound
/// hole on either leg.
String _renderLeg(
  String root,
  String leg,
  String skillId,
  Map<String, String> args,
) {
  final file = File(
    p.join(root, 'station_overlay', leg, 'skills', skillId, 'SKILL.md'),
  );
  expect(
    file.existsSync(),
    isTrue,
    reason: 'the $leg leg vends $skillId at ${file.path}',
  );
  var rendered = file.readAsStringSync();
  for (final entry in args.entries) {
    rendered = rendered.replaceAll('{{${entry.key}}}', entry.value);
  }
  expect(
    rendered,
    isNot(contains('{{')),
    reason: 'the $leg leg of $skillId renders with no unbound hole',
  );
  return rendered;
}

/// The two PUSHED role definitions. A seat loads one at session open and
/// carries it on EVERY turn after — the largest single instruction surface a
/// seat pays for, and the only one nobody pulls deliberately.
const List<String> _roles = ['governor', 'refiner'];

/// The ordered `## ` sections both role definitions expose.
///
/// One shape, one canonical list: a reader who has found the gates in one seat
/// knows where they are in the other, and a section added to one alone fails
/// here rather than quietly making the two files different documents.
const List<String> _roleSections = [
  '## The mandate',
  '## The operating loop',
  '## Cost — a request costs what the context costs',
  '## Human gates — never cross without an explicit, per-item go',
  '## Safety invariants (non-negotiable)',
];

/// Grammar and catalogs another surface already owns, each keyed by that
/// owner.
///
/// These are DELETED from the pushed definitions rather than shortened: a verb
/// cannot drift from its own `--help`, and a skill cannot drift from its own
/// procedure, but a prose copy of either drifts the moment the owner changes —
/// and nobody audits a 4,000-token file they did not write.
const Map<String, String> _ownedElsewhere = {
  '## Tool grammar': 'the verbs describe themselves',
  '## The skills': 'the harness lists the skills it installed',
  '{{runner}}': 'a station invocation is spelled by the verb, not by prose',
  'bd -C': 'a store-query recipe belongs to the skill that runs it',
  'bd batch': 'a store-query recipe belongs to the skill that runs it',
  'bd export': 'a store-query recipe belongs to the skill that runs it',
  '--state-root': 'a flag list is the verb’s own',
  'gh pr edit': 'a repair recipe is circuit-owned procedure',
};

/// Every clause each role definition must KEEP — the mandate it operates
/// under, the gates only a human may cross, and the invariants that hold
/// whatever the station is doing. None of these has another owner, so deleting
/// one deletes the policy itself.
const Map<String, List<String>> _loadBearing = {
  'governor': [
    // The mandate, and the boundary that makes it an operator seat.
    'You OPERATE; you do not engineer from this seat.',
    'When you find an engine or asset defect, file a precise bead',
    // ADR-0004 throughput, which outranks every other rule on the page.
    'THROUGHPUT OUTRANKS CEREMONY',
    '**Never pend work with a defer date.**',
    'THE STAMP IS THE APPROVAL',
    '**A ready P0/P1 never waits on you asking.**',
    '**A decision departure is RECORDED, not blocking.**',
    '`ready > 0` with `mounted 0` is an INCIDENT',
    // The five human gates, each with the qualification that scopes it.
    '**Merging PRs**',
    '`merge=human`',
    '**Firing a live arm**',
    '**Persistence changes**',
    '**PROMOTING a release — never publishing one.**',
    'Anything else outward-facing beyond a branch push + PR on org repos.',
    // The four safety invariants.
    '**Coexistence:**',
    '**bd is the only writer:**',
    '**Store discipline:**',
    '**Fail-closed reading:**',
    // The ratified cost posture, still ranked UNDER throughput.
    '## Cost — a request costs what the context costs',
    '**MEASURED 2026-09-03**',
    'NEVER outranks the throughput rules in the mandate',
  ],
  'refiner': [
    // The mandate: a human in the room, and one oracle for completeness.
    'The human is in the room with you; the governor is not.',
    'Make every filed bead APPROVABLE and keep the backlog TRUE',
    "The station's filing verdict is the completeness oracle; follow its "
        'failing details and mint no competing completeness predicate.',
    'Interview the human — one decision at a time, with the context that '
        'decides it.',
    'encode the ruling THE SAME TURN',
    '**You do not run the loop.**',
    // The five human gates.
    '**Approval.** APPROVAL STAYS HUMAN.',
    'explicit per-bead human ruling',
    'The refiner never un-stamps',
    '**Deciding an EITHER/OR fork.**',
    '**Merging PRs and pushing to any main.**',
    '**PROMOTING a release — not publishing one.**',
    '**Closing or re-homing work the human owns**',
    // The six safety invariants.
    '**You stamp `--actor refiner`.**',
    '**bd is the only writer:**',
    '**Store discipline:**',
    '**Coexistence:**',
    '**Multi-agent work has a ceiling here.**',
    '**Fail-closed reading:**',
  ],
};

/// What each seat must be able to tell it may NEVER do, from its own
/// definition alone — without opening a command, a skill or the other seat's
/// file.
const Map<String, List<String>> _prohibitions = {
  'governor': [
    'you do not engineer from this seat',
    'never broad-kill',
    'never SQL',
    'never lifecycle writes',
    'never cross without an explicit, per-item go',
    'do not work around it',
    "Never write that seat's Agent Disc.",
  ],
  'refiner': [
    'they are actions you do not take',
    'never broad-kill',
    'never SQL',
    'NEVER lifecycle writes',
    'you may NOT convene judge panels',
    'The refiner never un-stamps',
    'never work around it',
    "Never write that seat's Agent Disc.",
  ],
};

/// The ownership rule both seats now state, and the three affirmative phrases
/// it REPLACED.
///
/// The refiner definition used to send a cross-seat finding to the governor's
/// own disc. On 2026-09-12 a refiner did exactly that at 00:58; the governor's
/// next index rewrite erased the pointer line at 06:24 and the note was never
/// read. A finding goes where its actor already looks — the bead.
const String _discOwnership =
    'A finding another seat must act on belongs on the relevant bead. '
    "Never write that seat's Agent Disc.";

/// The retired channel, in every wording it was written in. Asserted with
/// POLARITY: a definition that merely mentions the governor's disc while still
/// routing a finding to it would pass a bare `contains` of [_discOwnership].
const List<String> _retiredDiscChannel = [
  'because that is the disc its occupant reads',
  'hand the governor a receipt on its disc',
  'leave the governor its receipts',
];

/// The MEASURED size of each definition before this reduction, in UTF-8 bytes
/// and in estimated tokens. A cut that does not cut fails here.
const Map<String, int> _baselineBytes = {'governor': 12916, 'refiner': 11945};
const Map<String, int> _baselineTokens = {'governor': 4758, 'refiner': 4406};

/// Characters per token, measured on this corpus. Prose, not code — a token is
/// a shade under three characters of it.
const double _charsPerToken = 2.69;

void main() {
  final root = _extensionDir();
  final loader = PackagedAssetLoader(root: root);

  group('PackagedAssetLoader — the vended skills', () {
    test('every vended skill loads to a non-empty SKILL.md whose frontmatter '
        'parses as REAL yaml and names itself', () {
      for (final skillId in vendedSkillIds) {
        final template = loader.loadSkillTemplate(skillId);
        expect(template, isNotEmpty);
        // agentskills frontmatter — the harness's skill discovery parses the
        // `---`-fenced yaml block and dispatches on `name:`.
        expect(template, startsWith('---\n'));
        final fenceEnd = template.indexOf('\n---', 3);
        expect(
          fenceEnd,
          greaterThan(0),
          reason: 'the frontmatter block is `---`-closed',
        );
        final frontmatter =
            loadYaml(template.substring(4, fenceEnd)) as YamlMap;
        expect(frontmatter['name'], skillId);
        expect(frontmatter['description'], isNotEmpty);
      }
    });

    test('an unknown skill throws (fail-loud — a packaging bug, never a '
        'silent empty install)', () {
      expect(
        () => loader.loadSkillTemplate('does-not-exist'),
        throwsArgumentError,
      );
    });

    test(
      'renderSkill substitutes every declared arg — no `{{` hole survives',
      () {
        final rendered = loader.renderSkill(
          'discover',
          args: {'runner': 'space'},
        );
        expect(rendered, isNot(contains('{{')));
        expect(rendered, contains('space search --json'));
      },
    );

    test('renderSkill with an unbound hole throws LOUD (an installed skill '
        'has no template residue)', () {
      expect(
        () => loader.renderSkill('discover', args: {}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('{{runner}}'),
          ),
        ),
      );
    });
  });

  group('the discover skill — the coupled skill+command acceptance', () {
    final rendered = PackagedAssetLoader(
      root: root,
    ).renderSkill('discover', args: {'runner': 'space'});

    String filingSection() {
      final start = rendered.indexOf('## Filing');
      final end = rendered.indexOf('## Design conversation');
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      return rendered.substring(start, end);
    }

    test('dispatches on arg shape — topic research, bead-id advisory, '
        'bead-id + instruction directed', () {
      expect(rendered, contains('## Dispatch'));
      expect(rendered, contains('## Topic research'));
      expect(rendered, contains('## Advisory'));
      expect(rendered, contains('## Directed'));
      // The three anchors of the dispatch table.
      expect(rendered, contains('**No arguments**'));
      expect(rendered, contains('looks like a bead-id'));
      expect(rendered, contains('a prompt after it'));
    });

    test('the research layer CALLS the vended search Command — the rendered '
        'verb, with the structured --json report', () {
      expect(rendered, contains('space search --json'));
      // The report contract the skill consumes (A11's documented schema).
      expect(rendered, contains('hitCount'));
      expect(rendered, contains('substation, prefix, root, outcome'));
      expect(rendered, contains('semantic'));
      expect(rendered, contains('indexed'));
      expect(rendered, contains('stale'));
      expect(rendered, contains('unindexed'));
      expect(rendered, contains('unavailable'));
      expect(rendered, contains('path=semantic'));
      expect(rendered, contains('score'));
      expect(rendered, contains('lexical stores section'));
      expect(rendered, contains('field=id'));
      expect(rendered, contains('semantic hit never confirms'));
    });

    test('never re-derives cross-store search by inference — the ad-hoc bd '
        'query forms are absent from the skill body', () {
      // The fence: the skill must not instruct (or even name) the ad-hoc
      // sweep forms — coverage rides the deterministic Command exclusively.
      expect(rendered, isNot(contains('bd search')));
      expect(rendered, isNot(contains('bd export')));
      expect(rendered, isNot(contains('bd ready')));
      // The one sanctioned anchored read is the one-shot, human-present
      // `bd show` — present, but explicitly cautioned against looping.
      expect(rendered, contains('bd show'));
      expect(rendered.toLowerCase(), contains('never loop'));
    });

    test(
      'filing cites the canonical contract and cannot pass an incomplete bead',
      () {
        final filing = filingSection();
        expect(filing, contains('intake-refinement/SKILL.md'));
        expect(filing, contains('The bead contract'));
        expect(filing, contains('--type <feature|bug|task|chore>'));
        expect(
          filing,
          isNot(contains('--type <feature|bug|task|epic|chore|decision>')),
        );
        expect(filing, contains('--acceptance'));
        expect(filing, contains('validation_plan'));
        expect(
          filing,
          contains(
            'cd packages/<pkg> && dart pub get && dart analyze && dart test',
          ),
        );
        expect(filing, contains('bd dep add <new bead id>'));
        expect(filing, contains('space filing --json "<new bead id>"'));
        expect(filing, contains('Do not leave Filing after'));
        expect(
          filing,
          contains(
            'specify\nauthoritatively replaces or refines the '
            'implementation-aligned plan',
          ),
        );
        expect(filing, contains('mounted\npredicate remains the authority'));
      },
    );

    test('filing and intake approve with the approve verb, never a '
        'hand-added label', () {
      const stampKeys = <String>[
        'grid.approved_by',
        'grid.approved_at',
        'grid.approved_rev',
      ];
      const refusal = 'approval: not approved - run the approve verb';

      final filing = filingSection();
      expect(rendered, isNot(contains('--defer')));
      expect(filing, contains('**Unapproved, never mounted:**'));
      expect(filing, contains('`grid.approved` label'));
      expect(filing, contains('space approve --actor governor --json "<id>"'));
      for (final key in stampKeys) {
        expect(filing, contains(key), reason: 'discover names $key');
      }
      expect(filing, contains(refusal));
      expect(
        filing,
        contains('staging transition; do not run it before the human approves'),
      );
      expect(filing, isNot(contains('--add-label')));

      final intake = loader.loadSkillTemplate('intake-refinement');
      expect(intake, isNot(contains('--defer')));
      expect(
        intake,
        contains('grid.approved_* stamp approval via the approve verb'),
      );
      expect(
        intake,
        contains(
          '## Staging: approve with the approve verb, only after refinement',
        ),
      );
      expect(
        intake,
        contains('{{runner}} approve --actor operator --json "<bead>"'),
      );
      for (final key in stampKeys) {
        expect(intake, contains(key), reason: 'intake names $key');
      }
      expect(intake, contains(refusal));
      expect(intake, contains('mounted predicate refuses'));
      expect(intake, isNot(contains('--add-label')));
    });

    test('cross-store guidance cites the register slugs directly', () {
      final filing = filingSection();
      expect(filing, contains('decisions#the-decision-register'));
      expect(filing, contains('decisions#legacy-register-migration'));
      expect(filing, contains('six legacy registers\n  are not yet migrated'));
      expect(filing, contains('were already binding'));
      expect(filing, contains('changes their location and not their force'));
      expect(
        filing,
        contains(
          'the_grid#a44-federated-work-sources-staleness-scope-member-removal-vs',
        ),
      );
      // The cross-store MECHANISM is bd's own external row since the link
      // surface was cut (grid_engine 0.4.0-dev.3, the_grid#447) — the retired
      // grid-state `type=link` bead is taught nowhere.
      expect(filing, contains('external:<project>:<capability>'));
      expect(filing, contains('export:<target>'));
      expect(filing, contains('bd ship <target>'));
      expect(filing, isNot(contains('type=link')));
      expect(filing, isNot(contains('grid.link.')));
      expect(filing, isNot(contains('crossLinkTypeRefusal')));
      expect(filing, isNot(contains('StationJoinBridge._applyCrossLinks')));
      expect(filing, isNot(contains('applyBlockGuard')));
      // The old ADR directory is retired: built, not typed literally, so
      // this fixture never re-adds the retired path string to the tree.
      const retiredAdrDir =
          'docs/'
          'adr';
      expect(filing, isNot(contains(retiredAdrDir)));
      expect(filing, isNot(contains('ADR-0000')));
    });

    test(
      'can kick off specify — the hand-off names the sibling vended asset',
      () {
        expect(rendered, contains('/specify'));
        expect(rendered, contains('Hand off to specify'));
      },
    );

    test('no bead before the yes — the no-junk-beads rule rides the skill', () {
      expect(rendered, contains('Do **not** file before the yes'));
    });
  });

  group('extension/mcp/config.yaml — the skills manifest section', () {
    test('declares the discover skill with its render args (parsed as real '
        'yaml)', () {
      final manifest = File(p.join(root, 'mcp', 'config.yaml'));
      final doc = loadYaml(manifest.readAsStringSync()) as YamlMap;

      final skills = (doc['skills'] as YamlList).cast<YamlMap>();
      final skillIds = {for (final s in skills) s['id'] as String};
      expect(
        skillIds,
        containsAll(vendedSkillIds),
        reason: 'every vended skill is declared in the manifest',
      );

      final discover = skills.firstWhere(
        (s) => s['id'] == 'discover',
        orElse: () => fail('the `discover` skill must be declared'),
      );
      expect(
        discover['path'],
        'station_overlay/claude/skills/discover/SKILL.md',
      );
      expect(
        discover['visibility'],
        isNotNull,
        reason: 'the discover skill declares a visibility',
      );
      final args = (discover['args'] as YamlList).cast<YamlMap>();
      final argNames = {for (final a in args) a['name'] as String};
      expect(
        argNames,
        {'runner'},
        reason: 'the manifest declares exactly the holes the template carries',
      );
    });
  });

  group('the re-homed OPERATOR skills', () {
    const reHomed = <String, Set<String>>{
      'asset-author': <String>{},
      // station-operations names BOTH runtimes: `runner` is the verb
      // invocation a seat can reach, `bootRunner` is what starts the resident
      // (which needs the JIT form for --enable-vm-service). It is the only
      // skill that boots anything, so it is the only one carrying two.
      'station-operations': {'runner', 'bootRunner'},
      'gate-medicine': {'runner'},
      'harvest-review': {'runner'},
      'intake-refinement': {'runner'},
      'release': {'runner'},
    };

    test('asset-author teaches the complete B-style provider contract', () {
      final manual = loader.loadSkillTemplate('asset-author');

      expect(manual, contains('context.watch<T>()'));
      expect(manual, contains('always returns `T?`'));
      expect(manual, contains('appearance, replacement, and disappearance'));
      expect(manual, contains('renders a refusal into diagnostics'));
      expect(manual, contains('do not search for a throwing `of()` variant'));
      expect(manual, contains('Provider<T>(create: ...)'));
      expect(manual, contains('Provider<T>.value'));
      expect(
        manual,
        contains('A pre-built instance never passes through `create:`'),
      );
      expect(manual, contains('The nearest provider wins'));
      expect(manual, contains('per-substation override'));
      expect(manual, contains('`GridDelegate.boot` is transitional'));
      expect(manual, contains('never entitled to `GitServices`'));
    });

    test('each is VENDED, declared in the manifest, and carries EXACTLY the '
        'holes it declares', () {
      final manifest =
          loadYaml(File(p.join(root, 'mcp', 'config.yaml')).readAsStringSync())
              as YamlMap;
      final skills = (manifest['skills'] as YamlList).cast<YamlMap>();

      for (final entry in reHomed.entries) {
        expect(vendedSkillIds, contains(entry.key));
        final template = loader.loadSkillTemplate(entry.key);
        final holes = {
          for (final m in RegExp(r'\{\{(\w+)\}\}').allMatches(template))
            m.group(1)!,
        };
        expect(
          holes,
          entry.value,
          reason: '${entry.key} carries exactly its declared args',
        );

        final declared = skills.firstWhere(
          (s) => s['id'] == entry.key,
          orElse: () => fail('${entry.key} must be declared in the manifest'),
        );
        expect(
          declared['path'],
          'station_overlay/claude/skills/${entry.key}/SKILL.md',
        );
        expect(declared['audience'], 'operator');
        final args =
            (declared['args'] as YamlList?)?.cast<YamlMap>() ??
            const <YamlMap>[];
        expect({for (final a in args) a['name'] as String}, entry.value);
      }
    });

    test('release renders the complete rc-first operator flow', () {
      final rendered = loader.renderSkill('release', args: {'runner': 'space'});

      expect(rendered, isNot(contains('{{')));
      expect(
        rendered,
        contains('--change <docs|additive|fix|breaking|rc> --json'),
      );
      expect(rendered, contains('Breaking -> `--change rc`'));
      expect(rendered, isNot(contains('Breaking -> `--change breaking`')));
      expect(
        rendered,
        contains(
          'space dart release tag --repo-dir <repo-dir> --tag <tag> --json',
        ),
      );
      expect(
        rendered,
        contains(
          'space dart release validate-consumers --rc-tag <rc-tag> '
          '--manifest <consumers.json> --json',
        ),
      );
      expect(
        rendered,
        contains(
          'space dart release promote --repo-dir <repo-dir> '
          '--stable-tag <stable-tag> --validation <validation.json> --json',
        ),
      );
      expect(rendered, contains('Pub excludes prereleases'));
      expect(rendered, contains('^0.2.0-rc.1'));
      expect(
        rendered,
        contains(
          'an rc on a package forces an rc on EVERY in-repo\n'
          '   sibling that depends on it',
        ),
      );
      expect(
        rendered,
        contains(
          '`dart pub publish` REFUSES a stable package that depends on a '
          'prerelease',
        ),
      );
      expect(
        rendered,
        contains(
          'loop `space dart release poll --package\n'
          '   <name> --version <rc-version> --json` until `isPublished: true` '
          'before\n'
          '   pushing a dependent\'s tag',
        ),
      );
      expect(
        rendered,
        contains(
          '(`melos publish` compares against\n'
          '   latest stable and is retired for uploads)',
        ),
      );
      expect(
        rendered,
        contains(
          '“N checked-in files are modified in git” means gate 4 is incomplete',
        ),
      );
      expect(
        rendered,
        contains(
          'declaredFloors:{candidate, pins:[{package, declaredConstraint, '
          'floor}], pubGetExitCode, analyzeExitCode, passed, message, stdout, '
          'stderr}',
        ),
      );
      expect(
        rendered,
        contains('Read both `clean` and `declaredFloors.passed`'),
      );
      expect(
        rendered,
        contains(
          'This leg resolves pub.dev and belongs only to\n'
          '  this release verb, never the offline workspace test command.',
        ),
      );
      expect(
        rendered,
        contains(
          '`declaredFloors.passed: false`\n'
          '   means the candidate does not compile against the minimums its own',
        ),
      );
    });

    test('EACH release leg prescribes melos for discovery, ordering and '
        'version authoring, and states both of its limits', () {
      for (final leg in _skillLegs) {
        final rendered = _renderLeg(root, leg, 'release', {'runner': 'space'});
        String why(String what) => 'the $leg release leg $what';

        // The vended ops over melos.
        expect(
          rendered,
          contains(
            'space dart release discover --workspace <workspace-dir> '
            '--diff <ref> --json',
          ),
          reason: why('calls the discovery op'),
        );
        expect(
          rendered,
          contains('`{workspaceRoot, diff, candidates, changed}`'),
          reason: why('names the discovery result shape'),
        );
        expect(
          rendered,
          contains(
            'space dart release order --workspace <workspace-dir> --json',
          ),
          reason: why('orders from the workspace'),
        );
        expect(
          rendered,
          contains('remains as the\n  compatibility input'),
          reason: why('keeps --manifest as the compatibility input only'),
        );

        // The raw melos queries that replace the hand method.
        expect(
          rendered,
          contains('dart run melos list\n  --no-published --json'),
          reason: why('asks melos which versions are unpublished'),
        );
        expect(
          rendered,
          contains('NOT a pub.dev curl per package'),
          reason: why('retires the per-package curl'),
        );
        expect(
          rendered,
          contains('`dart run melos list --diff=<ref> --json`'),
          reason: why('asks melos what changed'),
        );
        expect(
          rendered,
          contains('NOT a `git log <ref>..HEAD -- packages/<pkg>` per package'),
          reason: why('retires the per-package git log'),
        );
        expect(
          rendered,
          contains('`dart run melos list --depends-on=<package> --json`'),
          reason: why('reads the rc closure from melos'),
        );
        expect(
          rendered,
          contains(
            'Each workspace\'s existing\nscripts-only `melos:` block stands',
          ),
          reason: why('adds no melos command configuration'),
        );

        // Version + CHANGELOG + dependent constraints are melos's job now.
        expect(
          rendered,
          contains('`dart run\n   melos version --no-git-commit-version`'),
          reason: why('authors versions with melos'),
        );
        expect(
          rendered,
          contains(
            '`--changelog`,\n   `--dependent-constraints` and '
            '`--dependent-versions` defaults all stay ON',
          ),
          reason: why('keeps melos\'s changelog + dependent updates on'),
        );
        expect(
          rendered,
          contains(
            '`--no-git-commit-version` disables melos\'s default\n   commit '
            'and, by implication, its default tagging',
          ),
          reason: why('disables melos\'s commit and tags'),
        );

        // LIMIT 1 — commit-message honesty, and the classification it forces.
        expect(
          rendered,
          contains(
            '**`melos version` reads COMMIT MESSAGES, so it inherits their '
            'honesty.**',
          ),
          reason: why('states the commit-message limit'),
        );
        expect(
          rendered,
          contains(
            'lenny#96 was a breaking change\n   that carried no `!` and no '
            '`BREAKING CHANGE:` footer, so `melos version`\n   would have cut '
            'a PATCH',
          ),
          reason: why('names the measured case the limit came from'),
        );
        expect(
          rendered,
          contains('Adopting melos is\n   NOT a substitute for classification'),
          reason: why('refuses melos as a classifier'),
        );
        expect(
          rendered,
          contains(
            'space dart release classify --dir <package-dir> --package <name>\n'
            '   --json',
          ),
          reason: why('requires the shipped classify op after versioning'),
        );

        // LIMIT 2 — publish order is a RUNTIME statement.
        expect(
          rendered,
          contains(
            '**Publish order is computed on RUNTIME dependencies only.**',
          ),
          reason: why('states the runtime-only ordering limit'),
        );
        expect(
          rendered,
          contains(
            '`leonard_agent`,\n   `leonard_flutter` and `leonard_flutter_test` '
            'form a DEV-dependency cycle',
          ),
          reason: why('names the dev cycle the limit came from'),
        );
        expect(
          rendered,
          contains(
            'filters every edge against the package\'s top-level\n   '
            '`dependencies:` before ordering',
          ),
          reason: why('states where the dev edges are dropped'),
        );
        expect(
          rendered,
          contains('A dev cycle is not a publish cycle'),
          reason: why('separates a dev cycle from a publish cycle'),
        );
      }
    });

    test('EACH release leg keeps melos uploads RETIRED and tag-triggered '
        'trusted publishing as the upload path', () {
      for (final leg in _skillLegs) {
        final rendered = _renderLeg(root, leg, 'release', {'runner': 'space'});
        String why(String what) => 'the $leg release leg $what';

        expect(
          rendered,
          contains(
            '(`melos publish` compares against\n'
            '   latest stable and is retired for uploads)',
          ),
          reason: why('keeps the prerelease reason melos publish is retired'),
        );
        expect(
          rendered,
          contains('`melos publish` remains retired for uploads'),
          reason: why('keeps melos publish retired'),
        );
        expect(
          rendered,
          isNot(contains('melos publish --')),
          reason: why('never invokes melos publish'),
        );
        expect(
          rendered,
          contains(
            '## Publishing — push the tag; CI publishes (trusted publishing)',
          ),
          reason: why('keeps trusted publishing as the upload path'),
        );
        expect(
          rendered,
          contains('**Local `dart pub publish` is RETIRED.**'),
          reason: why('keeps hand-publishing retired'),
        );
        expect(
          rendered,
          contains('**ONE TAG PER PUSH.**'),
          reason: why('keeps the one-tag-per-push rule'),
        );
        expect(
          rendered,
          contains(
            'trusted publishing must still\n   start from one per-package tag '
            'push YOU control',
          ),
          reason: why('ties melos version back to the tag-push upload path'),
        );
      }
    });

    test(
      'station-operations renders against the installer binding — the runner '
      'verb and the grid home bound, no residue',
      () {
        final rendered = loader.renderSkill(
          'station-operations',
          args: {'runner': 'space'},
        );
        expect(rendered, isNot(contains('{{')));
        expect(rendered, contains('space up'));
        expect(rendered, contains('.grid/.beads'));
      },
    );

    test('the AUDIENCE split: an operator skill is never named in a build '
        "agent's brief — one of them PUSHES, which the brief forbids", () {
      final operatorIds = operatorSkillIds(
        GeneratedGridAssetRegistrant.registry,
      );
      expect(
        operatorIds,
        {...reHomed.keys, 'handoff'},
        reason: 'handoff is operator-audience without being a re-homed skill',
      );
      expect(
        operatorIds,
        isNot(contains('discover')),
        reason: 'discover is the agent-audience skill the brief DOES name',
      );
    });
  });

  group('the intake-refinement refiner corpus (bead `pow-glza`)', () {
    final template = loader.loadSkillTemplate('intake-refinement');
    final rendered = loader.renderSkill(
      'intake-refinement',
      args: {'runner': 'space'},
    );

    test('the exit oracle is the filing verb — the skill CALLS the command '
        'and owns no completeness predicate of its own', () {
      expect(template, contains('{{runner}} filing --json "<bead>"'));
      expect(rendered, contains('space filing --json "<bead>"'));
      expect(
        template,
        contains(
          '## The exit check — `filing` is the oracle, and it is a COMMAND',
        ),
      );
      // The report contract the skill consumes, row for row.
      expect(template, contains('{id, passed, requirements, error?}'));
      for (final row in const [
        'driveable_type',
        'validation_plan',
        'acceptance_criteria',
        'dependencies',
      ]) {
        expect(template, contains(row), reason: 'the corpus names $row');
      }
      expect(template, contains('"passed": false'));
      expect(template, contains('"passed": true'));
      expect(template, contains('bd holds no blocking dependency rows'));
      expect(template, contains('unresolvable external dependency rows:'));
      expect(template, contains('is a REFUSAL, not a pass'));
      // The reinvention this bead was CURED of (governor, 2026-09-02): the
      // engine-side mount gate and a refiner-local predicate are BOTH absent.
      expect(template, isNot(contains('mountEligibilityFindings')));
      expect(template, isNot(contains('refinerExitFindings')));
    });

    test('the corpus carries every refiner rule, each with the round it '
        'burned', () {
      const sections = <String>[
        '## Search prior art BEFORE accepting a filing',
        '## Scope the validation_plan to every consumer',
        '## Wire every dependency at intake',
        '## FLAG an EITHER/OR fork — never decide it',
        '## Stamp architecture constraints into the CHILD bead',
        '## Repo-relative paths in every declared test list',
        '## Point at the primitive that already exists',
        '## Staleness reconciliation — run BEFORE arming any store',
      ];
      for (final section in sections) {
        expect(template, contains(section), reason: '$section is authored');
      }
      expect(
        RegExp(r'\*\*Why:\*\*').allMatches(template).length,
        greaterThanOrEqualTo(7),
        reason: 'every new rule states the round it burned',
      );
      // The load-bearing mechanics of each rule.
      expect(rendered, contains('space search --json "<token>"'));
      expect(template, contains('single tokens'));
      expect(template, contains('bd -C <store root> dep add <blocked bead>'));
      expect(rendered, contains('space link <blocked bead> --blocked-by'));
      expect(template, contains('external:<project>:<capability>'));
      expect(template, contains('FORK (author decides)'));
      expect(template, contains('An agent reads ONE bead: its own.'));
      expect(
        template,
        contains('packages/grid_assets/test/assets/skill_assets_test.dart'),
      );
      expect(template, contains('CLOSE IT AS STALE WITH RECEIPTS'));
      expect(template, contains('<receipts: file paths, commit ids>'));
    });

    test('the compose-do-not-reinvent pointer RESOLVES in the live tree — a '
        'stale file:line teaches the duplication it exists to prevent', () {
      final match = RegExp(
        r'COMPOSE: (packages/\S+\.dart):(\d+)',
      ).firstMatch(template);
      expect(match, isNotNull, reason: 'the corpus carries the pointer');
      final repoRoot = p.normalize(p.join(packageRoot(), '..', '..'));
      final target = File(p.join(repoRoot, match!.group(1)!));
      expect(
        target.existsSync(),
        isTrue,
        reason: '${match.group(1)} exists at the repo root',
      );
      final lines = target.readAsLinesSync();
      final at = int.parse(match.group(2)!);
      expect(lines.length, greaterThanOrEqualTo(at));
      expect(
        lines[at - 1],
        contains('class FilingContract'),
        reason: 'the cited line declares the primitive the corpus names',
      );
    });

    test('intake-refinement teaches the projection details and the bd '
        'external row in both overlay legs', () {
      // The refiner acts on the verb's `detail` verbatim, so the corpus is
      // pinned to the strings the verb EMITS — not to a paraphrase of them.
      const held = 'bd holds no blocking dependency rows';
      const unresolvable = 'unresolvable external dependency rows:';
      for (final leg in const ['claude', 'agents']) {
        final body = File(
          p.join(
            root,
            'station_overlay',
            leg,
            'skills',
            'intake-refinement',
            'SKILL.md',
          ),
        ).readAsStringSync();

        expect(
          body,
          contains(held),
          reason: '$leg teaches the PASSING projection detail verbatim',
        );
        expect(
          body,
          contains(unresolvable),
          reason: '$leg teaches the refusal the roster can produce',
        );
        // The retired state-store link surface is not taught anywhere
        // (grid_engine 0.4.0-dev.3, the_grid#447), and neither is the retired
        // prose declaration grammar or the row it fed (pow-f6pc).
        expect(body, isNot(contains('type=link')));
        expect(body, isNot(contains('grid.link.')));
        expect(body, isNot(contains('cross-store edges not consulted')));
        expect(body, isNot(contains('missing outgoing blocks edges')));
        expect(
          body,
          contains('A blocker is a DECLARATION bd holds'),
          reason: '$leg says prose declares nothing',
        );
        // A cross-store blocker is bd's own external row, written by the
        // link verb.
        expect(
          body,
          contains('external:<project>:<capability>'),
          reason: '$leg teaches bd\'s own cross-project row',
        );
        expect(
          body,
          contains(
            '{{runner}} link <blocked bead> --blocked-by <blocker bead>',
          ),
          reason: '$leg documents the link verb in its post-cut shape',
        );
        // Neither command names a second store any more: the row is a
        // projection of the WORK store's own bd rows.
        expect(
          body,
          contains('{{runner}} filing --json "<bead>"'),
          reason: '$leg documents the one filing form',
        );
        expect(
          body,
          contains('{{runner}} approve --actor operator --json "<bead>"'),
          reason: '$leg documents the one approve form',
        );
        expect(
          body,
          isNot(contains('filing --json --state-root')),
          reason: '$leg does not teach a root the verb no longer takes',
        );
      }
    });
  });

  group('the vended overlay is ROOT-RELATIVE and COMPLETE', () {
    final overlay = p.join(root, 'station_overlay');

    test(
      'it MIRRORS the target repo root — the legacy kind-dir home is gone, so '
      'a dumb path-preserving overlay lands every asset where the harness '
      'discovers it',
      () {
        expect(
          Directory(p.join(overlay, 'skills')).existsSync(),
          isFalse,
          reason:
              'the pre-root-relative `station_overlay/skills/` home is gone',
        );
        for (final id in vendedSkillIds) {
          expect(
            File(
              p.join(overlay, 'claude', 'skills', id, 'SKILL.md'),
            ).existsSync(),
            isTrue,
            reason: '$id is vended root-relative',
          );
        }
      },
    );

    test('it carries the COMPLETE operator asset set — the governor AND '
        'refiner agent-defs and the harness settings, not just the skills. '
        'These were hand-copied into the station and drifted; vending them is '
        'what ends that', () {
      final governor = File(p.join(overlay, 'claude', 'agents', 'governor.md'));
      expect(governor.existsSync(), isTrue);
      expect(
        governor.readAsStringSync(),
        startsWith('---\n'),
        reason: 'stampable: the frontmatter must open on line 1',
      );
      expect(governor.readAsStringSync(), contains('name: governor'));

      final settings = File(p.join(overlay, 'claude', 'settings.json'));
      expect(settings.existsSync(), isTrue);
      expect(
        jsonDecode(settings.readAsStringSync()),
        isA<Map<String, dynamic>>(),
        reason: 'stampable: a JSON object',
      );
      expect(
        settings.readAsStringSync(),
        contains('{{runner}} prime --hook-json'),
        reason: 'the SessionStart hook is the GRID prime verb (bead pow-lv6t)',
      );
      expect(
        settings.readAsStringSync(),
        isNot(contains('bd prime')),
        reason: 'the dead bd hook is replaced, not kept beside it',
      );
      expect(
        settings.readAsStringSync(),
        isNot(contains('PreCompact')),
        reason: 'no PreCompact guard — a hook cannot undo a compaction',
      );

      // The seat boot instruction has ONE owner now: the skill that is pulled
      // when a station is being operated. The role definition names no station
      // invocation at all.
      for (final leg in const ['claude', 'agents']) {
        final operations = File(
          p.join(overlay, leg, 'skills', 'station-operations', 'SKILL.md'),
        ).readAsStringSync();
        expect(
          operations.split('{{runner}} seat governor').length - 1,
          1,
          reason: '$leg carries its own governor-seat boot instruction',
        );
      }

      // The REFINER seat's role definition, beside the governor's on the one
      // claude leg (`power_station#a-harness-may-carry-its-own-instructions`:
      // each harness leg is an independent instruction source, so no agents/
      // twin is owed — governor.md has none either).
      //
      // What either definition SAYS is fenced in 'the vended ROLE DEFINITIONS
      // are policy, not a verb manual' below; this test owns packaging only.
      final refinerFile = File(
        p.join(overlay, 'claude', 'agents', 'refiner.md'),
      );
      expect(refinerFile.existsSync(), isTrue);
      final refiner = refinerFile.readAsStringSync();

      expect(
        refiner,
        startsWith('---\n'),
        reason: 'stampable: the frontmatter must open on line 1',
      );
      expect(refiner, contains('name: refiner'));
      expect(refiner, contains('\n# The Refiner\n'));
      expect(
        refiner,
        contains('.grid/seats/refiner/'),
        reason: 'the seat is told which disc is its own',
      );
      expect(
        refiner,
        isNot(contains('refinerExitFindings')),
        reason:
            'the exit criterion is a CALL to the filing verb, never a '
            'predicate of this seat’s own',
      );
    });

    test('no station_overlay file — skill OR governor agent-def — still '
        'teaches the hand-added label or the retired defer guard', () {
      final offenders = <String>[];
      for (final entity in Directory(overlay).listSync(recursive: true)) {
        if (entity is! File) continue;
        final body = entity.readAsStringSync();
        if (body.contains('--add-label ${'grid'}.approved') ||
            body.contains('--defer')) {
          offenders.add(p.relative(entity.path, from: overlay));
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'approval is the approve verb; the label alone never mounts',
      );
    });

    test('EVERY vended file can carry a provenance stamp — an unstampable one '
        'could never be told from a hand-authored file, so it could never be '
        'installed', () {
      final files = Directory(
        overlay,
      ).listSync(recursive: true).whereType<File>();
      expect(files, isNotEmpty);
      for (final file in files) {
        final rel = p.relative(file.path, from: overlay);
        expect(
          () => provenanceSyntaxFor(rel, file.readAsStringSync()),
          returnsNormally,
          reason: '$rel is stampable',
        );
      }
    });
  });

  group('the vended ROLE DEFINITIONS are policy, not a verb manual', () {
    final agents = p.join(root, 'station_overlay', 'claude', 'agents');

    File roleFile(String role) => File(p.join(agents, '$role.md'));

    String body(String role) => roleFile(role).readAsStringSync();

    // The body with every run of whitespace collapsed to one space, so a PROSE
    // assertion survives a re-wrap of the paragraph it lives in. Markers that
    // cannot span a line break read the raw body just as well.
    String flowed(String role) => body(role).replaceAll(RegExp(r'\s+'), ' ');

    test('mandates, human gates, and safety invariants remain load-bearing', () {
      for (final role in _roles) {
        final text = flowed(role);
        for (final clause in _loadBearing[role]!) {
          expect(
            text,
            contains(clause),
            reason:
                '$role.md must still state "$clause" — no verb reports it, so '
                'deleting it deletes the policy rather than a copy of one',
          );
        }
      }
    });

    test('each role says what it must never do', () {
      for (final role in _roles) {
        final text = flowed(role);
        for (final prohibition in _prohibitions[role]!) {
          expect(
            text,
            contains(prohibition),
            reason:
                'a seat reads $role.md and nothing else at session open; it '
                'must be able to tell from this file alone that "$prohibition"',
          );
        }
      }
    });

    test('cross-seat findings never write another seat disc', () {
      expect(
        flowed('governor'),
        contains('Your Agent Disc is your own. $_discOwnership'),
      );
      expect(
        flowed('refiner'),
        contains(
          'Your handoffs, lessons and observations go on your Agent Disc. '
          '$_discOwnership',
        ),
      );

      for (final role in _roles) {
        final text = flowed(role);
        for (final retired in _retiredDiscChannel) {
          expect(
            text,
            isNot(contains(retired)),
            reason:
                '$role.md must not route a finding onto another seat’s disc: '
                'a note written there is erased by that seat’s next index '
                'rewrite and never read',
          );
        }
        expect(
          text,
          isNot(matches(RegExp('kind: receipt.*governor'))),
          reason: '$role.md names no receipt note on the governor’s disc',
        );
      }
    });

    test('verb grammar and circuit-owned procedure are absent', () {
      for (final role in _roles) {
        final text = body(role);
        _ownedElsewhere.forEach((marker, owner) {
          expect(
            text,
            isNot(contains(marker)),
            reason:
                '$role.md must not carry `$marker` — $owner, and a pushed '
                'copy drifts the moment that owner changes',
          );
        });
      }
    });

    test('role definitions share one section structure', () {
      for (final role in _roles) {
        expect(
          body(
            role,
          ).split('\n').where((line) => line.startsWith('## ')).toList(),
          _roleSections,
          reason: '$role.md exposes the canonical seat-role sections, in order',
        );
      }
    });

    test('both definitions shrink below the live baseline', () {
      for (final role in _roles) {
        final text = body(role);
        final bytes = utf8.encode(text).length;
        final tokens = (text.runes.length / _charsPerToken).round();

        expect(
          bytes,
          lessThan(_baselineBytes[role]!),
          reason:
              '$role.md was ${_baselineBytes[role]} bytes of pushed prose; '
              'this surface is paid for on every turn, so it shrinks',
        );
        expect(
          tokens,
          lessThan(_baselineTokens[role]!),
          reason:
              '$role.md was ~${_baselineTokens[role]} tokens; bytes can fall '
              'while tokens do not, so both are measured',
        );
      }
    });
  });
}
