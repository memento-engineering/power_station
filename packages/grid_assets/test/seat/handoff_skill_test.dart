// The vended `/handoff` SKILL — the seat occupant's own session-end ritual,
// vended on BOTH overlay legs.
//
// Pins the acceptance:
//   - both legs ship `skills/handoff/SKILL.md`, and the id is vended with an
//     OPERATOR audience (a build agent's brief never names it);
//   - the frontmatter names both requesters (human `/handoff`, agent-initiated)
//     and the session boundary, and the `{{runner}}` hole renders like every
//     other skill's;
//   - the body carries SETTLE / WRITE (the ten sections, in order) / BANK /
//     INDEX / SIGNAL (ONE line, and the inner agent cannot restart itself) /
//     RESUME, citing the disc shape from
//     `the_grid#agent-disc-file-shape-and-home` and inventing no other;
//   - AC-5 (pow-d5ol) SIGNAL carries no `/clear` option and exactly one signal
//     line, and RESUME states that the LAUNCHER already consumed — the verb
//     stays named as the hand-recovery path, and none of the four retired
//     hand-delete phrases appears;
//   - AC-5, RULING 2026-09-13 (governor): the cut is HARD and station-wide —
//     NO vended file under `station_overlay/` instructs `/clear`, role
//     definitions included, and the two that did (`claude/agents/governor.md`,
//     `claude/agents/refiner.md`) now teach the same ending the skill does;
//   - the two legs are INDEPENDENT instruction sources (a harness-specific
//     instruction on each, per
//     `power_station#a-harness-may-carry-its-own-instructions`);
//   - AC-5 both legs teach the WORKING-MEMORY lifecycle — written once, picked
//     up and deleted within minutes, never amended — and route the one
//     completed note through `succession --write-handoff` before the index line;
//   - AC-2 no note kind is added: the kinds either leg authors are exactly
//     `handoff`, `lesson`, `receipt`, `observation`.
//
// Homed under `test/seat/` rather than `test/assets/` because it pins a SEAT
// surface: the bead's own validation plan is `dart test test/seat`, and the
// suite that pins AC-5 has to be inside it or the plan does not cover the
// deliverable it certifies.
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
        operatorSkillIds(GeneratedGridAssetRegistrant.registry),
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
        expect(description, contains('at a session boundary'));
        expect(
          description,
          isNot(contains('/clear')),
          reason: '/clear is retired as a handoff path (Nico, 2026-09-13)',
        );
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

      test('$leg: AC-5 SIGNAL is ONE line, exit is the only handoff path, and '
          'no /clear option survives', () {
        final body = legBody(leg);
        expect(
          body,
          contains('You cannot restart yourself'),
          reason: '$leg: the signal goes UP — that is the whole point',
        );
        // Exactly ONE signal line. The three cases collapsed: a compacted or
        // cleared context is the same occupant carrying on, not a successor,
        // so neither one hands off (Nico, 2026-09-13).
        expect(
          'Handoff written:'.allMatches(body).length,
          1,
          reason: '$leg: one signal line, not a menu',
        );
        expect(
          body,
          contains(
            '- `Handoff written: <path>; exit, the launcher relaunches this '
            'seat.`',
          ),
        );
        expect(
          body,
          isNot(contains('/clear')),
          reason: '$leg: /clear is RETIRED as a handoff path',
        );
        expect(body, isNot(contains('/compact')));
        expect(body, isNot(contains('**(a) Continue in place**')));
        expect(body, isNot(contains('**(b) Fresh start**')));
        expect(body, isNot(contains('**(c) Headless / launcher-driven**')));
        expect(body, contains('Exiting IS'));
        expect(
          body,
          contains("prime/launcher bead's deliverable"),
          reason: '$leg: the launcher is NOT this deliverable',
        );
        // The archive is no longer "none": an ignored disc gets a local one.
        expect(
          body,
          contains('.grid/seats/<seat>/.archive/<utc-stamp>/'),
          reason: '$leg: the second archive sink is named',
        );
        expect(body, contains('git history when the disc is tracked'));
        expect(body, contains('`PreCompact` guard'));
      });
    }
  });

  group('AC-5 the LAUNCHER consumed; the verb is the recovery path', () {
    test('RESUME states the consumption already happened and runs no verb', () {
      // The defect class this closes (pow-jhmu, four instances): the successor
      // was told to consume, and a successor that reads its own instructions
      // late, or whose disc is gitignored, never did. The launcher does it now,
      // before the successor exists.
      for (final leg in _legs) {
        final rendered = legBody(leg).replaceAll('{{runner}}', 'space');
        expect(rendered, contains('ALREADY CONSUMED'));
        expect(
          rendered,
          contains('body you were primed with IS that note'),
          reason: '$leg: the successor reads the primed body and acts',
        );
        expect(rendered, contains('There is nothing on the disc to consume'));
        expect(
          rendered,
          contains(
            'space succession <seat> --grid-home "<grid home>"` stays as the\n'
            'HAND-RECOVERY path only',
          ),
          reason: '$leg: the verb survives for a disc no launcher touched',
        );
        expect(rendered, contains('WOULD have deleted'));
        expect(rendered, contains('REFUSED'));
        // The archive fork is taught where the successor reads it.
        expect(rendered, contains('chore(seat): archive <seat> disc'));
        expect(rendered, contains('git add -f` is never used'));
        for (final retired in const [
          'handoff-*.md | sort | tail -1',
          'DELETE the file AND its `MEMORY.md` pointer',
          'git history is the archive',
          'deleted UNREAD',
          'CONSUME it, in the SAME turn that read it',
        ]) {
          expect(
            rendered,
            isNot(contains(retired)),
            reason: '$leg: the hand-performed ritual is RETIRED — "$retired"',
          );
        }
      }
    });
  });

  group('AC-5 the HARD CUT reaches every vended instruction', () {
    // RULING 2026-09-13 (governor): retiring `/clear` from the handoff skill
    // alone left the role definitions still teaching it — governor.md and
    // refiner.md each told the seat to write the handoff "and then /clear",
    // which is the path the launcher can no longer consume. An overlay that
    // contradicts itself is read as an option, so the grep is the acceptance.
    test('no file under station_overlay/ instructs /clear', () {
      final offenders = <String>[];
      for (final entity in Directory(overlay).listSync(recursive: true)) {
        if (entity is! File) continue;
        final body = utf8.decode(
          entity.readAsBytesSync(),
          allowMalformed: true,
        );
        if (body.toLowerCase().contains('/clear')) {
          offenders.add(p.relative(entity.path, from: overlay));
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'a seat hands off by ENDING; `grep -ri /clear` over the overlay '
            'returns nothing that instructs it',
      );
    });

    test('the two role definitions teach the ENDING the skill teaches', () {
      for (final role in const ['governor', 'refiner']) {
        // Markdown prose is hard-wrapped, so the phrases are matched against
        // the text with its wrapping collapsed — a re-wrap is not a change of
        // instruction and must not be read as one.
        final body = File(
          p.join(overlay, 'claude', 'agents', '$role.md'),
        ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
        expect(
          body,
          contains('handoff and then EXIT'),
          reason:
              '$role: the bullet that carried `/clear` still has to name the '
              'path that replaced it — a deletion alone leaves the seat with '
              'no ending at all',
        );
        expect(
          body,
          contains('relaunches this seat primed with it'),
          reason: '$role: the launcher is what makes ending safe',
        );
        expect(
          body,
          contains('Ending IS the handoff path; there is no in-place one.'),
          reason: '$role: stated, so the next reader cannot re-derive /clear',
        );
      }
    });
  });

  group('AC-5 the WORKING-MEMORY lifecycle is taught on both legs', () {
    for (final leg in _legs) {
      test('$leg: a handoff is written once, in minutes, never amended', () {
        final body = legBody(leg);
        // The defect: one governor note was rewritten across thirty commits
        // over nine hours, so the UTC stamp in its own file name was false.
        // The lifetime is the fix, and it is stated before the ritual starts.
        expect(
          body,
          contains(
            'A handoff is WORKING MEMORY — written once, picked up, and '
            'deleted within\nminutes.',
          ),
        );
        expect(body, contains('It is NEVER amended.'));
        expect(
          body,
          contains('The write verb REFUSES a second live'),
          reason: '$leg: the constraint is mechanical, not only advice',
        );
        expect(
          body,
          contains('Long-term memory stays THIN.'),
          reason:
              '$leg: beads, decisions and trajectories hold durable knowledge '
              'on demand, so a disc note must not duplicate one',
        );
      });

      test('$leg: the note is composed WHOLE, stamped once, then routed '
          'through the write verb', () {
        final rendered = legBody(leg).replaceAll('{{runner}}', 'space');
        expect(rendered, contains('Compose all ten sections below IN FULL'));
        expect(rendered, contains('resolve the stamp exactly once'));
        expect(
          rendered,
          contains(
            'space succession <seat> --grid-home "<grid home>" '
            '--write-handoff "handoff-<utc-stamp>-<slug>.md"',
          ),
          reason:
              '$leg: the skill CALLS the command rather than writing the file '
              'itself — the write-once gate is behind the verb',
        );
        expect(
          rendered,
          contains('`HANDOFF WRITTEN <path>` is the only success'),
        );
        // A refusal changes NOTHING: not the live note, not the index, and not
        // "the same note under a second name", which is the amendment in
        // disguise.
        expect(
          rendered,
          contains('Change NOTHING — not\nthat file, not the index'),
        );
        expect(rendered, contains('Never edit an existing handoff file'));
        expect(rendered, contains('never append to one'));
      });

      test('$leg: the index line is earned by a successful write', () {
        final body = legBody(leg);
        expect(body, contains('ONLY after `HANDOFF WRITTEN`, append ONE '));
        expect(
          body,
          contains('never rewrite the index around it'),
          reason:
              '$leg: the index is CHECKED, never rewritten wholesale '
              '(power_station#seat-disc-index-integrity-is-checked-not-written)',
        );
        expect(
          body,
          contains('After a `REFUSED` write there is no line to add'),
        );
      });

      test('$leg: AC-2 exactly four note kinds are authored, and none of '
          'them is a mid-shift channel', () {
        expect(
          {
            for (final match in RegExp(
              r'kind:\s*([a-z]+)',
            ).allMatches(legBody(leg)))
              match.group(1)!,
          },
          {'handoff', 'lesson', 'receipt', 'observation'},
          reason:
              '$leg: the ruling DISSOLVED the journal fork — the checkpoint is '
              'a handoff, cycled fast, so no fifth kind exists',
        );
        expect(legBody(leg), contains('there is no fifth kind'));
        expect(legBody(leg), contains('a checkpoint IS'));
      });
    }
  });

  group('the two legs are INDEPENDENT instruction sources', () {
    test('the claude leg names Claude Code\'s own exit verb; the agents leg '
        'names none and carries its own harness note', () {
      final claude = legBody('claude');
      final agents = legBody('agents');

      expect(claude, contains('Then EXIT — `/exit`'));
      expect(claude, isNot(contains('## Harness note')));

      expect(agents, isNot(contains('`/exit`')));
      expect(agents, contains('Then EXIT, however your harness exits.'));
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
      final vendingRoot = packageRoot();
      final report = await const OverlayInstallService().install(
        resolution: resolveGridAssets(
          registry: GeneratedGridAssetRegistrant.registry,
          snapshot: SubstationFactsSnapshot(<SubstationKey, SubstationFacts>{
            const SubstationKey('home'): SubstationFacts(
              root: vendingRoot,
              dartPackages: const <String>['grid_assets', 'grid_sdk'],
              packageRoots: <String, String>{'grid_assets': vendingRoot},
            ),
          }),
          substation: const SubstationKey('home'),
          renderArguments: const {'runner': 'space', 'gridHome': '/grid/home'},
        ),
        targetRoot: temp.path,
        sourceRef: 'testref',
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
}
