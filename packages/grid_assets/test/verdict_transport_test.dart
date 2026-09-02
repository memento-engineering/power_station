import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart' show Bead;
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

void main() {
  group('atomic verdict prompt contract', () {
    final bead = Bead(id: 'tg-1', title: 'Atomic verdict transport');
    final prompts = <String>[
      const CriticCapability().buildCriticPrompt(
        bead,
        'spec-adherence',
        'tg-1/review/spec-adherence',
        '/w/tg-1',
        round: 0,
      ),
      const SpecCriticCapability().buildSpecCriticPrompt(
        bead,
        'coherence',
        'tg-1/spec_review/coherence',
        '/w/tg-1',
        round: 0,
      ),
      const ReadinessCriticCapability().buildReadinessPrompt(
        bead,
        kReadinessRubric,
        'tg-1/spec_review/readiness',
        '/w/tg-1',
        round: 0,
      ),
    ];

    test('every critic ends with same-directory atomic replacement', () {
      for (final prompt in prompts) {
        expect(prompt, contains('Do NOT write JSON directly'));
        expect(prompt, contains('mktemp "/w/tg-1/.grid/critique/'));
        expect(prompt, contains('mv -f -- "\$verdict_tmp"'));
        expect(
          prompt.trimRight(),
          endsWith(
            'never reuse one writer\'s temporary path in another writer.',
          ),
        );
        expect(prompt, isNot(contains('You MUST write that JSON to')));
      }
    });

    test('ONLY the spec critic is taught the owner column', () {
      expect(prompts[1], contains('"$kVerdictOwnerKey":"<architect|author>"'));
      expect(prompts[1], contains(kVerdictOwnerInstruction));
      for (final other in [prompts[0], prompts[2]]) {
        expect(other, isNot(contains('"$kVerdictOwnerKey":')));
        expect(other, isNot(contains(kVerdictOwnerInstruction)));
      }
    });
  });

  test('concurrent atomic verdict replacement stays parseable', () async {
    final dir = await Directory.systemTemp.createTemp('verdict-transport-');
    addTearDown(() async => dir.delete(recursive: true));
    final destination = File('${dir.path}/verdict.json');
    final payloads = [
      {'writer': 'one', 'rationale': List.filled(4000, 'alpha').join(' ')},
      {'writer': 'two', 'rationale': List.filled(4000, 'bravo').join(' ')},
    ];
    await destination.writeAsString(jsonEncode(payloads.first));

    Future<ProcessResult> writer(Map<String, Object> payload) async {
      final encoded = jsonEncode(payload);
      return Process.run('/bin/sh', [
        '-c',
        'verdict_tmp=\$(mktemp "\$1/.verdict.json.XXXXXX") && '
            'printf %s "\$2" > "\$verdict_tmp" && '
            'mv -f -- "\$verdict_tmp" "\$1/verdict.json"',
        'writer',
        dir.path,
        encoded,
      ]);
    }

    final writers = Future.wait([
      for (final payload in payloads) writer(payload),
    ]);
    while (true) {
      final observed = jsonDecode(await destination.readAsString());
      expect(
        payloads.any((payload) => jsonEncode(payload) == jsonEncode(observed)),
        isTrue,
      );
      final complete = await Future.any<Object?>([
        writers.then<Object?>((value) => value),
        Future<void>.delayed(const Duration(milliseconds: 1)),
      ]);
      if (complete is List<ProcessResult>) break;
    }
    final results = await writers;
    for (final result in results) {
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }
    final finalDocument = jsonDecode(await destination.readAsString());
    expect(
      payloads.any(
        (payload) => jsonEncode(payload) == jsonEncode(finalDocument),
      ),
      isTrue,
    );
  });

  group('ledger session ownership', () {
    test('rejects and deletes a retired root', () async {
      final dir = await Directory.systemTemp.createTemp('ledger-retired-');
      addTearDown(() async => dir.delete(recursive: true));
      writeRespecLedger(
        dir.path,
        const RespecLedger(
          sessionRoot: 'retired-1',
          round: 3,
          lanes: [
            RespecLane(
              rubric: 'plan-completeness',
              grade: 'D',
              rationale: 'retired rationale',
            ),
          ],
        ),
      );

      expect(
        readRespecLedger(dir.path, expectedSessionRoot: 'current-1'),
        isNull,
      );
      expect(File(respecLedgerPath(dir.path)).existsSync(), isFalse);
    });

    test('round-trips the current root', () async {
      final dir = await Directory.systemTemp.createTemp('ledger-current-');
      addTearDown(() async => dir.delete(recursive: true));
      writeRespecLedger(
        dir.path,
        const RespecLedger(
          sessionRoot: 'current-1',
          round: 2,
          lanes: [
            RespecLane(
              rubric: 'plan-completeness',
              grade: 'D',
              rationale: 'verbatim rationale',
            ),
          ],
        ),
      );

      final ledger = readRespecLedger(
        dir.path,
        expectedSessionRoot: 'current-1',
      );
      expect(ledger?.sessionRoot, 'current-1');
      expect(ledger?.round, 2);
      expect(ledger?.lanes.single.rationale, 'verbatim rationale');
    });
  });
}
