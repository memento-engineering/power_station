import 'package:test/test.dart';

import 'real_bd_store.dart';

/// The filing verb over CROSS-STORE blockers, end to end against a real `bd`.
///
/// A cross-store blocker is an `external:<project>:<capability>` DEPENDENCY ROW
/// — what `bd dep add` writes and what the station's `link` verb is sugar over
/// (`the_grid` #445). The open `type=link` state bead this suite used to drive
/// is retired with the prose declaration grammar
/// (`power_station#the-dependencies-row-is-a-projection-of-bd-dependency-rows`),
/// so what is asserted here is the row, its roster resolution, and the two
/// ways that resolution can refuse.
///
/// These cases are deliberately NOT in `filing_command_test.dart`: that suite
/// proves the four requirements over a bead's own fields, and this one proves
/// the one requirement that reaches past them to the station's posture.
void main() {
  test(
    'AC-2 — a REAL external: row is a blocker with its roster state',
    skip: skipWithoutBd,
    () async {
      final store = await filingStore();
      await runBd(store, [
        'create',
        '--id',
        'filing-consumer',
        '--title',
        'consumer',
        '--type',
        'task',
        '--description',
        'Needs a capability from another project.',
        '--acceptance',
        '- [ ] dart test passes',
        '--metadata',
        '{"validation_plan":"dart test"}',
        '--actor',
        'test',
      ]);
      await runBd(store, [
        'dep',
        'add',
        'filing-consumer',
        'external:the_grid:tg-xh5d',
        '--actor',
        'test',
      ]);

      // ARMED: the row is reported as a blocker, and the row passes.
      final armed = harness(store, armed: const {'the_grid'});
      expect(
        await armed.runner.run(['filing', '--json', 'filing-consumer']),
        0,
        reason: '${armed.out}${armed.err}',
      );
      expect(
        dependencyRow(armed.out)['detail'],
        'bd dependency rows: external:the_grid:tg-xh5d (armed)',
      );

      // NOT ARMED: the same row, refused fail-closed and named.
      final unarmed = harness(store, armed: const {'space'});
      expect(
        await unarmed.runner.run(['filing', '--json', 'filing-consumer']),
        1,
      );
      expect(dependencyRow(unarmed.out)['passed'], isFalse);
      expect(
        dependencyRow(unarmed.out)['detail'],
        contains('external:the_grid:tg-xh5d names "the_grid"'),
      );
    },
  );

  test(
    'AC-2 — with NO roster supplied the same row refuses, and says which '
    'condition it is',
    skip: skipWithoutBd,
    () async {
      final store = await filingStore();
      await runBd(store, [
        'create',
        '--id',
        'filing-unconsulted',
        '--title',
        'consumer',
        '--type',
        'task',
        '--description',
        'Needs a capability from another project.',
        '--acceptance',
        '- [ ] dart test passes',
        '--metadata',
        '{"validation_plan":"dart test"}',
        '--actor',
        'test',
      ]);
      await runBd(store, [
        'dep',
        'add',
        'filing-unconsulted',
        'external:the_grid:tg-xh5d',
        '--actor',
        'test',
      ]);

      // No roster: fail-closed exactly as NOT ARMED is, but named as its own
      // condition, because the correction is the STATION's and not the bead's.
      final h = harness(store);
      expect(await h.runner.run(['filing', '--json', 'filing-unconsulted']), 1);
      expect(dependencyRow(h.out)['passed'], isFalse);
      expect(
        dependencyRow(h.out)['detail'],
        contains('no station roster was supplied'),
      );
      expect(
        dependencyRow(h.out)['detail'],
        contains('passes its armed roster in as armedSubstations'),
        reason: 'the refusal names the remedy, not just the condition',
      );
    },
  );
}
