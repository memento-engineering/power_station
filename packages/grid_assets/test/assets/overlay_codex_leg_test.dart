// The CODEX leg of the vended overlay:
// `extension/station_overlay/agents/skills/<id>/SKILL.md`, mapped to
// `.agents/skills/<id>/SKILL.md` at install by the `agents -> .agents` head
// already in `kDefaultStationOverlayMappings`.
//
// The agents leg is an INDEPENDENT instruction source for the codex-style
// harnesses the station arms. It started life as a copy of the claude leg and
// MAY diverge from it: a harness may carry its own instructions (Nico,
// 2026-09-03), so a difference between the two legs is a harness-specific
// instruction, not drift. Identical content is permitted, never required —
// nothing here reads a SKILL.md's bytes.
//
// What this file DOES pin is STRUCTURE, which is harness-independent: both
// legs vend the same skill IDS (a skill present for one harness and absent
// for the other is a vending gap, not an instruction difference), the leg
// carries SKILL.md files and nothing else, and no copilot leg exists.
//
// The ONE instruction contract this file DOES compare across legs is
// `discover`'s advertised TRIGGER. That is not a harness-specific instruction —
// it is the answer to "who may reach this skill", and it has to be the same
// answer on both legs or a codex seat and a claude seat disagree about whether
// a task prompt is a front-door request. Comparing the two `description` values
// is therefore deliberately narrower than the byte-identity this file refuses
// to pin.
//
// Offline only — reads the bundled `extension/` files.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:grid_assets/station_asset_registry.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../support/package_root.dart';

/// The trigger sentence that made a BUILD SEAT's task prompt look like a front
/// door. It is the shape every seat's brief opens with — a bead id, then what
/// to do — so advertising it as this skill's DIRECTED form made the two
/// indistinguishable. The lunar_station-a7w round (2026-09-13) is the measured
/// cost: the codex builder loaded `discover`, ended its turn after one turn,
/// and shipped an empty diff into review.
const String _retiredDirectedTrigger =
    'A bead-id followed by an instruction is directed';

/// A build seat's task prompt, verbatim in shape: a bead id, then an
/// instruction, and no invocation of anything.
const String _buildSeatPrompt = 'pow-p8il Implement the accepted spec';

/// The frontmatter map of [leg]'s SKILL.md for [skillId].
YamlMap _frontmatter(String overlay, String leg, String skillId) {
  final template = File(
    p.join(overlay, leg, 'skills', skillId, 'SKILL.md'),
  ).readAsStringSync();
  expect(template, startsWith('---\n'));
  final fenceEnd = template.indexOf('\n---', 3);
  expect(fenceEnd, greaterThan(0), reason: 'the block is `---`-closed');
  return loadYaml(template.substring(4, fenceEnd)) as YamlMap;
}

/// The human phrases a [description] NAMES, in double quotes — read out of the
/// vended text rather than restated here, so this suite cannot drift from what
/// is actually shipped.
List<String> _namedHumanPhrases(String description) => RegExp('"([^"]+)"')
    .allMatches(description)
    .map((match) => match.group(1)!.toLowerCase())
    .toList(growable: false);

/// A TEST-ONLY reading of the advertised trigger contract: given [description],
/// would [prompt] reach this skill? The harness owns the real matcher; what
/// this pins is that the description can only be read ONE way — an explicit
/// `/discover`, or one of the human phrases it names, and nothing else.
bool _triggersDiscover(String description, String prompt) {
  final text = prompt.trim();
  if (text.startsWith('/discover')) return true;
  final lowered = text.toLowerCase();
  return _namedHumanPhrases(description).any(lowered.contains);
}

/// This package's `extension/` dir, off the shared cwd-independent package
/// root. Never a walk up from the process working
/// directory: that is a process property and `dart test` runs the suites
/// concurrently, so a walk from here could read a directory another file had
/// pointed somewhere else.
String _extensionDir() => p.join(packageRoot(), 'extension');

void main() {
  final overlay = p.join(_extensionDir(), 'station_overlay');
  final claudeSkills = p.join(overlay, 'claude', 'skills');
  final agentsSkills = p.join(overlay, 'agents', 'skills');

  List<String> skillIdsIn(String dir) =>
      Directory(dir)
          .listSync()
          .whereType<Directory>()
          .map((d) => p.basename(d.path))
          .toList()
        ..sort();

  test('the agents leg vends EXACTLY the claude leg skill ids', () {
    expect(skillIdsIn(agentsSkills), vendedSkillIds);
    expect(skillIdsIn(agentsSkills), skillIdsIn(claudeSkills));
  });

  test('the agents leg carries SKILL.md files and nothing else — no operator '
      'seat asset, no loose file', () {
    final files =
        Directory(p.join(overlay, 'agents'))
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => p.relative(f.path, from: overlay))
            .toList()
          ..sort();
    expect(files, [
      for (final id in vendedSkillIds)
        p.join('agents', 'skills', id, 'SKILL.md'),
    ]);
  });

  test('no copilot leg is authored and no AGENTS.md is vended — Copilot CLI '
      'reads the claude and agents trees directly, and a loose root file is '
      'the one shape the per-asset-dir fence cannot cover', () {
    expect(Directory(p.join(overlay, 'copilot')).existsSync(), isFalse);
    expect(File(p.join(overlay, 'AGENTS.md')).existsSync(), isFalse);
    expect(kDefaultStationOverlayMappings.containsKey('copilot'), isFalse);
  });

  group("discover's advertised trigger is a HUMAN invocation", () {
    String descriptionOf(String leg) =>
        _frontmatter(overlay, leg, 'discover')['description'] as String;

    test('the skill is still DECLARED and VENDED — the overlay-scope decision '
        'stands, so this narrows the trigger and removes nothing', () {
      // `power_station#the-worktree-overlay-scope-widens-to-every-skill-tree`: a
      // codex build worktree receives the SAME vended skill trees a claude seat
      // does. Making `discover` unloadable from a build seat would reverse it.
      expect(vendedSkillIds, contains('discover'));
      expect(skillIdsIn(claudeSkills), contains('discover'));
      expect(skillIdsIn(agentsSkills), contains('discover'));
      expect(
        GeneratedGridAssetRegistrant.registry.assets.where(
          (asset) =>
              asset.assetKey.kind == AssetKind.skill &&
              asset.assetKey.id == 'discover',
        ),
        hasLength(1),
        reason: 'the generated manifest still carries the declaration',
      );
    });

    test('both legs advertise the IDENTICAL trigger — who may reach a skill is '
        'not a harness-specific instruction', () {
      expect(descriptionOf('agents'), descriptionOf('claude'));
    });

    test(
      'the retired bead-id-plus-instruction trigger is gone from both legs',
      () {
        for (final leg in const ['claude', 'agents']) {
          expect(
            descriptionOf(leg),
            isNot(contains(_retiredDirectedTrigger)),
            reason:
                '$leg still advertises a build seat task prompt as directed',
          );
        }
      },
    );

    test('the DIRECTED form survives — it just has to be invoked', () {
      for (final leg in const ['claude', 'agents']) {
        expect(
          descriptionOf(leg),
          contains('/discover <bead-id> <instruction>'),
        );
      }
      // And the skill BODY's dispatch is untouched: once invoked, a bead-id
      // with a prompt after it still acts.
      final body = PackagedAssetLoader(
        root: _extensionDir(),
      ).renderSkill('discover', args: const {'runner': 'space'});
      expect(body, contains('## Dispatch'));
      expect(body, contains('*Directed* (carry out the instruction)'));
    });

    test('a build seat task prompt does NOT trigger it; an explicit invocation '
        'and every named human phrase do', () {
      final description = descriptionOf('claude');
      final phrases = _namedHumanPhrases(description);
      expect(phrases, <String>[
        "let's build",
        'i have an idea',
        'plan this',
        'design this',
        "what's the state of <bead>",
        'what should i do with <bead>',
        'have we already decided this',
      ]);

      expect(
        _triggersDiscover(description, _buildSeatPrompt),
        isFalse,
        reason: 'the shape that cost the lunar_station-a7w round',
      );
      expect(
        _triggersDiscover(description, '/discover $_buildSeatPrompt'),
        isTrue,
      );
      expect(_triggersDiscover(description, '/discover pow-p8il'), isTrue);
      expect(_triggersDiscover(description, '/discover'), isTrue);
      for (final phrase in phrases) {
        expect(
          _triggersDiscover(description, phrase),
          isTrue,
          reason: 'the description names "$phrase" as a trigger',
        );
      }
    });
  });
}
