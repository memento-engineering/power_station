import 'package:beads_dart/beads_dart.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:test/test.dart';

void main() {
  const base = Bead(
    id: 'al-1',
    title: 'title',
    description: 'description',
    design: 'design',
    acceptanceCriteria: 'acceptance',
    notes: 'notes',
    closeReason: 'close',
  );

  test('changes exactly the six embedded fields', () {
    expect(embeddingChangeKey(base), embeddingChangeKey(base));
    final mutations = [
      base.copyWith(title: 'changed'),
      base.copyWith(description: 'changed'),
      base.copyWith(design: 'changed'),
      base.copyWith(acceptanceCriteria: 'changed'),
      base.copyWith(notes: 'changed'),
      base.copyWith(closeReason: 'changed'),
    ];
    for (final mutation in mutations) {
      expect(embeddingChangeKey(mutation), isNot(embeddingChangeKey(base)));
    }
    expect(
      embeddingChangeKey(base.copyWith(status: BeadStatus.closed)),
      embeddingChangeKey(base),
    );
    expect(
      embeddingChangeKey(base.copyWith(labels: const ['changed'])),
      embeddingChangeKey(base),
    );
  });

  test('length delimiters distinguish adjacent-field boundaries', () {
    final left = base.copyWith(title: 'a', description: 'bc');
    final right = base.copyWith(title: 'ab', description: 'c');
    expect(embeddingChangeKey(left), isNot(embeddingChangeKey(right)));
  });
}
