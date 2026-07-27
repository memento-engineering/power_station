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
//   - on the human's yes it files a bead (ephemeral + staged, `bd create`)
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
    });

    test('never re-derives cross-store search by inference — the ad-hoc bd '
        'query forms are absent from the skill body', () {
      // The fence: the skill must not instruct (or even name) the ad-hoc
      // sweep forms — coverage rides the deterministic Command exclusively.
      expect(rendered, isNot(contains('bd search')));
      expect(rendered, isNot(contains('bd list')));
      expect(rendered, isNot(contains('bd export')));
      expect(rendered, isNot(contains('bd ready')));
      // The one sanctioned anchored read is the one-shot, human-present
      // `bd show` — present, but explicitly cautioned against looping.
      expect(rendered, contains('bd show'));
      expect(rendered.toLowerCase(), contains('never loop'));
    });

    test('on the human\'s yes it files an EPHEMERAL, STAGED bead through the '
        'bd CLI with the governor actor', () {
      expect(rendered, contains('bd create'));
      expect(rendered, contains('--ephemeral'));
      expect(rendered, contains('--defer'));
      expect(rendered, contains('--actor governor'));
      // Filing scope: target substation store first, grid-home fallback.
      expect(
        rendered,
        contains('the substation whose repo the work would change'),
      );
      expect(rendered, contains("the grid home's own store"));
      // Promote-later: the design conversation ends in the persistent flip.
      expect(rendered, contains('--persistent'));
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
      'station-operations': {'runner'},
      'gate-medicine': {'runner'},
      'harvest-review': {'runner'},
      'intake-refinement': <String>{},
      'release': {'runner'},
    };

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

      final settings = File(p.join(overlay, 'claude', 'settings.json'));
      expect(settings.existsSync(), isTrue);
      expect(
        jsonDecode(settings.readAsStringSync()),
        isA<Map<String, dynamic>>(),
        reason: 'stampable: a JSON object',
      );
      expect(settings.readAsStringSync(), contains('bd prime --hook-json'));
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
