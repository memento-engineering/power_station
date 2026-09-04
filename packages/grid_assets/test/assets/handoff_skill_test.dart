// The vended `/handoff` SKILL — the seat occupant's own session-end ritual,
// vended on BOTH overlay legs.
//
// Pins the acceptance:
//   - both legs ship `skills/handoff/SKILL.md`, and the id is vended with an
//     OPERATOR audience (a build agent's brief never names it);
//   - the frontmatter names both requesters (human `/handoff`, agent-initiated)
//     and the three boundaries (compaction, clear, relaunch), and the
//     `{{runner}}` hole renders like every other skill's;
//   - the body carries SETTLE / WRITE (the ten sections, in order) / BANK /
//     INDEX / SIGNAL (three cases, and the inner agent cannot restart itself) /
//     RESUME (delete-on-consume), citing the disc shape from
//     `the_grid#agent-disc-file-shape-and-home` and inventing no other;
//   - the two legs are INDEPENDENT instruction sources (a harness-specific
//     instruction on each, per
//     `power_station#a-harness-may-carry-its-own-instructions`);
//   - the governor def names `/handoff` at session end and the successor read
//     at session start.
//
// Offline only — reads the bundled `extension/` files; no live anything.
import 'dart:io';

import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// This package's `extension/` dir, resolved the CWD-INDEPENDENT way (the
/// loader's own package-config resolution), exactly as
/// `overlay_install_test.dart` does. Never a cwd walk: `Directory.current` is
/// process-global and the suites run concurrently, so a sibling suite that
/// chdirs would race a walk done here.
String _extensionDir() => PackagedAssetLoader().root;

/// The two overlay legs this skill ships on — independent instruction
/// sources.
const List<String> _legs = ['claude', 'agents'];

void main() {
  final root = _extensionDir();
  final overlay = p.join(root, 'station_overlay');
  final loader = PackagedAssetLoader(root: root);

  File legFile(String leg) =>
      File(p.join(overlay, leg, 'skills', 'handoff', 'SKILL.md'));

  String legBody(String leg) => legFile(leg).readAsStringSync();

  /// Asserts every phrase in [ordered] is present in [body] and each one
  /// starts AFTER the one before it — order, not just presence.
  void expectInOrder(String body, List<String> ordered, {required String on}) {
    var at = -1;
    for (final phrase in ordered) {
      final next = body.indexOf(phrase);
      expect(
        next,
        greaterThan(at),
        reason: '$on: "$phrase" is authored, after the section before it',
      );
      at = next;
    }
  }

  group('the handoff skill is VENDED on both legs', () {
    test('the id is enumerated, operator-audience, and present under '
        'claude/skills and agents/skills', () {
      expect(vendedSkillIds, contains('handoff'));
      expect(
        operatorSkillIds,
        contains('handoff'),
        reason:
            "a build agent's brief never names it: the disc it writes lives "
            'at a grid home, not in a bead worktree, and it ends a turn asking '
            'the outer harness to relaunch the seat',
      );
      for (final leg in _legs) {
        expect(
          legFile(leg).existsSync(),
          isTrue,
          reason: '$leg leg vends skills/handoff/SKILL.md',
        );
      }
    });

    test('the frontmatter names itself, BOTH requesters, and the three '
        'boundaries', () {
      for (final leg in _legs) {
        final body = legBody(leg);
        expect(body, startsWith('---\n'), reason: '$leg opens frontmatter');
        final fenceEnd = body.indexOf('\n---', 3);
        expect(fenceEnd, greaterThan(0), reason: '$leg closes frontmatter');
        final frontmatter = loadYaml(body.substring(4, fenceEnd)) as YamlMap;
        expect(frontmatter['name'], 'handoff');
        final description = '${frontmatter['description']}';
        expect(description, contains('/handoff'));
        expect(description, contains('self-initiates'));
        expect(description, contains('before compaction, clear, or relaunch'));
      }
    });

    test('renderSkill binds the one declared hole — no residue reaches a '
        'seat', () {
      final rendered = loader.renderSkill('handoff', args: {'runner': 'space'});
      expect(rendered, isNot(contains('{{')));
      expect(rendered, contains('space status --state-workspace <grid home>'));
    });

    test('the manifest declares it at its claude-leg path with EXACTLY the '
        'holes each leg carries', () {
      final manifest =
          loadYaml(File(p.join(root, 'mcp', 'config.yaml')).readAsStringSync())
              as YamlMap;
      final skills = (manifest['skills'] as YamlList).cast<YamlMap>();
      final declared = skills.firstWhere(
        (s) => s['id'] == 'handoff',
        orElse: () => fail('the `handoff` skill must be declared'),
      );
      expect(
        declared['path'],
        'station_overlay/claude/skills/handoff/SKILL.md',
      );
      expect(declared['visibility'], 'public');
      expect(declared['audience'], 'operator');
      final args = (declared['args'] as YamlList).cast<YamlMap>();
      expect({for (final a in args) a['name'] as String}, {'runner'});

      for (final leg in _legs) {
        final holes = {
          for (final m in RegExp(r'\{\{(\w+)\}\}').allMatches(legBody(leg)))
            m.group(1)!,
        };
        expect(holes, {'runner'}, reason: '$leg carries its declared arg only');
      }
    });
  });

  group('the ritual body — SETTLE, WRITE, BANK, INDEX, SIGNAL, RESUME', () {
    for (final leg in _legs) {
      test('$leg: the five stages are authored in order, then the successor '
          'RESUME', () {
        expectInOrder(legBody(leg), const [
          '## 1. SETTLE',
          '## 2. WRITE the handoff onto the disc',
          '## 3. BANK the durable learnings',
          '## 4. INDEX it',
          '## 5. SIGNAL the outer harness',
          '## Resume — the successor',
        ], on: leg);
      });

      test('$leg: the ten WRITE sections are authored in order', () {
        final body = legBody(leg);
        expectInOrder(body, const [
          '1. **Header**',
          '2. **Rulings**',
          '3. **Board state**',
          '4. **In flight**',
          '5. **Tried and failed — do not retry**',
          '6. **Promises to the human**',
          '7. **Context the successor must not re-derive**',
          '8. **Unfiled observations**',
          '9. **Resume here**',
          '10. **Ready**',
        ], on: leg);
        expect(
          body,
          contains('UTC **and** local'),
          reason: '$leg: the header stamp is dual — the skew caused misreads',
        );
      });

      test('$leg: SETTLE parks the work and NAMES what the seat owns', () {
        final body = legBody(leg);
        expect(body, contains('Nothing half-written'));
        expect(body, contains('NAME every resource this seat owns'));
      });

      test(
        '$leg: the disc shape is CITED from the_grid, never re-invented',
        () {
          final body = legBody(leg);
          expect(body, contains('<grid home>/.grid/seats/<seat>/'));
          expect(body, contains('kind: handoff'));
          expect(body, contains('the_grid#agent-disc-file-shape-and-home'));
          expect(body, contains('This skill invents no shape'));
          expect(body, contains('never graduates'));
        },
      );

      test('$leg: BANK writes separate disc notes, never a pasted handoff', () {
        final body = legBody(leg);
        expect(body, contains('kind: lesson'));
        expect(body, contains('Never bank by pasting the handoff'));
      });

      test('$leg: INDEX adds one MEMORY.md pointer line', () {
        final body = legBody(leg);
        expect(body, contains('MEMORY.md'));
        expect(body, contains('](handoff-<utc-stamp>-<slug>.md)'));
      });

      test('$leg: SIGNAL states the inner agent cannot restart itself, and '
          'gives three cases', () {
        final body = legBody(leg);
        expect(
          body,
          contains('You cannot compact, clear, or restart yourself'),
          reason: '$leg: the signal goes UP — that is the whole point',
        );
        expect(body, contains('**(a) Continue in place**'));
        expect(body, contains('Run /compact now'));
        expect(body, contains('**(b) Fresh start**'));
        expect(body, contains('Run /clear'));
        expect(body, contains('**(c) Headless / launcher-driven**'));
        expect(
          body,
          contains("prime/launcher bead's deliverable"),
          reason: '$leg: the launcher and the hook are NOT this deliverable',
        );
        expect(body, contains('no archive directory'));
        expect(body, contains('`PreCompact` guard'));
      });

      test('$leg: the successor DELETES the handoff and its index line in the '
          'same turn', () {
        final body = legBody(leg);
        expect(body, contains('handoff-*.md | sort | tail -1'));
        expect(body, contains('DELETE the file AND its `MEMORY.md` pointer'));
        expect(body, contains('git history is the archive'));
        expect(
          body,
          contains('deleted UNREAD'),
          reason: '$leg: a superseded handoff is never acted on',
        );
      });
    }
  });

  group('the two legs are INDEPENDENT instruction sources', () {
    test('the claude leg names the Claude Code relaunch flag; the agents leg '
        'names none and carries its own harness note', () {
      final claude = legBody('claude');
      final agents = legBody('agents');

      expect(claude, contains('claude --append-system-prompt-file <path>'));
      expect(claude, isNot(contains('## Harness note')));

      expect(agents, isNot(contains('--append-system-prompt-file')));
      expect(agents, contains('## Harness note'));
      expect(agents, contains('codex-style harness'));
    });
  });

  group('assets install lands it on BOTH harness skill trees', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('handoff-install-'));
    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('a grid home gets .claude/skills/handoff and .agents/skills/handoff, '
        'both fully bound', () async {
      final report = await const OverlayInstallService().install(
        overlayRoots: [overlay],
        targetRoot: temp.path,
        sourceRef: 'testref',
        args: {'runner': 'space', 'gridHome': '/grid/home'},
      );

      expect(report.refused, isEmpty);
      expect(report.blocked, isEmpty);
      for (final home in const ['.claude', '.agents']) {
        final installed = File(
          p.join(temp.path, home, 'skills', 'handoff', 'SKILL.md'),
        );
        expect(
          installed.existsSync(),
          isTrue,
          reason: '$home/skills/handoff/SKILL.md is materialized',
        );
        final body = installed.readAsStringSync();
        expect(body, isNot(contains('{{')), reason: '$home: no residue');
        expect(body, contains('space status --state-workspace <grid home>'));
      }
    });
  });

  group('the governor def names the ritual at BOTH ends of a session', () {
    final governor = File(
      p.join(overlay, 'claude', 'agents', 'governor.md'),
    ).readAsStringSync();

    test('the Record step ends a session through /handoff and starts one by '
        'reading the newest handoff note', () {
      expect(governor, contains('A session ENDS through `/handoff`'));
      expect(governor, contains('STARTS by reading the newest'));
      expect(governor, contains('`kind: handoff` note on that disc'));
    });

    test('the Record step is the ONLY place it changed — the diagnosis-skill '
        'menu at the foot is untouched', () {
      expect(
        governor,
        contains('`asset-author` — B-style in-tree provider composition'),
      );
      expect(
        governor,
        isNot(contains('- `handoff` —')),
        reason: 'handoff is not one of the loop-step-2 diagnosis skills',
      );
    });
  });
}
