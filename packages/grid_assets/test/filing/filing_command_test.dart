import 'dart:convert';

import 'package:test/test.dart';

import 'real_bd_store.dart';

void main() {
  test(
    'real bd filing passes all four requirements',
    skip: skipWithoutBd,
    () async {
      final store = await filingStore();
      await runBd(store, [
        'create',
        '--id',
        'filing-blocker',
        '--title',
        'blocker',
        '--type',
        'task',
        '--actor',
        'test',
      ]);
      await runBd(store, [
        'create',
        '--id',
        'filing-good',
        '--title',
        'good filing',
        '--type',
        'task',
        '--defer',
        '+1h',
        '--description',
        'Package: grid_assets',
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
        'filing-good',
        'filing-blocker',
        '--actor',
        'test',
      ]);

      final h = harness(store);
      expect(
        await h.runner.run(['filing', '--json', 'filing-good']),
        0,
        reason: '${h.out}\n${h.err}',
      );
      final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
      final rows = (report['requirements'] as List)
          .cast<Map<String, dynamic>>();
      expect(report['passed'], isTrue);
      expect(rows, hasLength(4));
      expect(rows.every((row) => row['passed'] == true), isTrue);
    },
  );

  test(
    'reports every failed requirement and exits non-zero',
    skip: skipWithoutBd,
    () async {
      final store = await filingStore();
      await runBd(store, [
        'create',
        '--id',
        'filing-bad',
        '--title',
        'bad filing',
        '--type',
        'epic',
        '--description',
        'No plan, no acceptance, not driveable.',
        '--metadata',
        '{"validation_plan":" "}',
        '--actor',
        'test',
      ]);
      // The one row a bead's own TEXT can no longer fail: the dependency row
      // is a projection of the rows bd holds, and bd holds none.
      await runBd(store, [
        'dep',
        'add',
        'filing-bad',
        'external:nowhere:cap',
        '--actor',
        'test',
      ]);

      final h = harness(store, armed: const {'the_grid'});
      expect(await h.runner.run(['filing', '--json', 'filing-bad']), 1);
      final report = jsonDecode(h.out.toString()) as Map<String, dynamic>;
      final rows = (report['requirements'] as List)
          .cast<Map<String, dynamic>>();
      expect(report['passed'], isFalse);
      expect(rows, hasLength(4));
      expect(rows.every((row) => row['passed'] == false), isTrue);
      expect(
        dependencyRow(h.out)['detail'],
        contains('external:nowhere:cap names "nowhere"'),
      );
    },
  );

  test(
    'AC-1 — over a REAL bd store, the two prose spellings agree',
    skip: skipWithoutBd,
    () async {
      final store = await filingStore();
      for (final (id, description) in const [
        ('filing-hyphen', 'Blocked-by: filing-x'),
        ('filing-spaced', 'Blocked by filing-x'),
      ]) {
        await runBd(store, [
          'create',
          '--id',
          id,
          '--title',
          'prose',
          '--type',
          'task',
          '--description',
          description,
          '--acceptance',
          '- [ ] dart test passes',
          '--metadata',
          '{"validation_plan":"dart test"}',
          '--actor',
          'test',
        ]);
      }

      final hyphen = harness(store);
      final spaced = harness(store);
      expect(await hyphen.runner.run(['filing', '--json', 'filing-hyphen']), 0);
      expect(await spaced.runner.run(['filing', '--json', 'filing-spaced']), 0);
      expect(dependencyRow(hyphen.out), dependencyRow(spaced.out));
      expect(
        dependencyRow(spaced.out)['detail'],
        'bd holds no blocking dependency rows',
      );
    },
  );

  test('usage and missing beads fail loudly', skip: skipWithoutBd, () async {
    final store = await filingStore();
    expect(await harness(store).runner.run(['filing']), 64);
    expect(
      await harness(store).runner.run(['filing', 'filing-a', 'filing-b']),
      64,
    );
    final missing = harness(store);
    expect(await missing.runner.run(['filing', '--json', 'filing-missing']), 1);
    final report = jsonDecode(missing.out.toString()) as Map<String, dynamic>;
    expect(report['passed'], isFalse);
    expect(report['requirements'], isEmpty);
    expect(report['error'], 'bead not found');
  });
}
