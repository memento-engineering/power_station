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
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Resolves this package's `extension/` dir by walking up from the cwd (the
/// same walk the loader + track_d suite use), so the loader root and the
/// manifest read never disagree on cwd.
String _extensionDir() {
  final candidates = <String>[
    'extension',
    p.join('packages', 'grid_assets', 'extension'),
  ];
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    for (final rel in candidates) {
      final probe = Directory(p.join(dir.path, rel));
      if (probe.existsSync() &&
          Directory(p.join(probe.path, 'rubrics')).existsSync()) {
        return probe.path;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail(
    'could not locate packages/grid_assets/extension from '
    '${Directory.current.path}',
  );
}

void main() {
  final root = _extensionDir();
  final loader = PackagedAssetLoader(root: root);

  group('PackagedAssetLoader — the vended skills', () {
    test('every vended skill loads to a non-empty SKILL.md whose frontmatter '
        'parses as REAL yaml and names itself', () {
      for (final skillId in kVendedSkills) {
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
      const refusal =
          'approval: unstamped label - approve with the approve verb';

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
      expect(intake, contains('grid.approved approval via the approve verb'));
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

    test('cross-store guidance preserves unmigrated binding authority', () {
      final filing = filingSection();
      expect(filing, contains('decisions#the-decision-register'));
      expect(filing, contains('decisions#legacy-register-migration'));
      expect(filing, contains('six legacy registers\n  are not yet migrated'));
      expect(filing, contains('were already binding'));
      expect(filing, contains('changes their location and not their force'));
      expect(
        filing,
        contains('the_grid/docs/adr/ADR-0000-ai-decision-register.md A44'),
      );
      expect(
        filing,
        contains('the_grid/docs/adr/ADR-0000-ai-decision-register.md A55'),
      );
      expect(filing, contains('type=link'));
      expect(filing, contains('grid.link.from=<blocked bead id>'));
      expect(filing, contains('grid.link.to=<blocker bead id>'));
      expect(filing, contains('grid.link.type=blocks'));
      expect(filing, contains('crossLinkTypeRefusal'));
      expect(filing, contains('StationJoinBridge._applyCrossLinks'));
      expect(filing, contains('applyBlockGuard'));
      expect(
        filing,
        isNot(
          contains(
            'power_station/docs/adr/ADR-0000-ai-decision-register.md A44',
          ),
        ),
      );
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
        containsAll(kVendedSkills),
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
      'station-operations': {'runner'},
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
      expect(manual, contains('per-seat override'));
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
        expect(kVendedSkills, contains(entry.key));
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
      expect(kOperatorSkills, reHomed.keys.toSet());
      expect(
        kOperatorSkills,
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
      expect(template, contains('missing outgoing blocks edges'));
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
      expect(template, contains('grid.link.type=blocks'));
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
      final repoRoot = p.normalize(p.join(_extensionDir(), '..', '..', '..'));
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
        for (final id in kVendedSkills) {
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

    test('it carries the COMPLETE operator asset set — the governor agent-def '
        'and the harness settings, not just the skills. These were hand-copied '
        'into the station and drifted; vending them is what ends that', () {
      final governor = File(p.join(overlay, 'claude', 'agents', 'governor.md'));
      expect(governor.existsSync(), isTrue);
      expect(
        governor.readAsStringSync(),
        startsWith('---\n'),
        reason: 'stampable: the frontmatter must open on line 1',
      );
      expect(governor.readAsStringSync(), contains('name: governor'));
      expect(
        governor.readAsStringSync(),
        contains('`asset-author` — B-style in-tree provider composition'),
      );

      final settings = File(p.join(overlay, 'claude', 'settings.json'));
      expect(settings.existsSync(), isTrue);
      expect(
        jsonDecode(settings.readAsStringSync()),
        isA<Map<String, dynamic>>(),
        reason: 'stampable: a JSON object',
      );
      expect(settings.readAsStringSync(), contains('bd prime --hook-json'));
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

      final governor = File(
        p.join(overlay, 'claude', 'agents', 'governor.md'),
      ).readAsStringSync();
      expect(
        governor,
        contains('{{runner}} approve --actor <name> <bead-id>'),
        reason: 'the governor names the verb that replaced the guard',
      );
      expect(
        governor,
        contains('approval: unstamped label - approve with the approve verb'),
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
}
