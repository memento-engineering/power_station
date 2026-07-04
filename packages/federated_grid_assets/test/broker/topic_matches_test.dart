// Pure-logic proof of MQTT-shaped topic matching (`+`/`#` wildcards) — the
// predicate the in-memory broker (and any future wire impl behind the same
// seam) uses for both retained-replay and live fan-out.
import 'package:federated_grid_assets/federated_grid_assets.dart';
import 'package:test/test.dart';

void main() {
  group('topicMatches', () {
    test('an exact filter matches only the identical topic', () {
      expect(topicMatches('grid/presence', 'grid/presence'), isTrue);
      expect(topicMatches('grid/presence', 'grid/claim'), isFalse);
      expect(topicMatches('grid/presence', 'grid/presence/extra'), isFalse);
    });

    test('+ matches exactly one level', () {
      expect(topicMatches('grid/+/presence', 'grid/studio/presence'), isTrue);
      expect(topicMatches('grid/+/presence', 'grid/presence'), isFalse);
      expect(
        topicMatches('grid/+/presence', 'grid/studio/extra/presence'),
        isFalse,
      );
    });

    test('multiple + segments each match one level', () {
      expect(topicMatches('grid/+/claim/+', 'grid/a/claim/b'), isTrue);
      expect(topicMatches('grid/+/claim/+', 'grid/a/claim/b/c'), isFalse);
    });

    test('# matches all remaining levels, INCLUDING the parent level itself '
        '(standard MQTT semantics — "sport/#" matches "sport" too)', () {
      expect(topicMatches('grid/claim/#', 'grid/claim/unclaimed'), isTrue);
      expect(
        topicMatches('grid/claim/#', 'grid/claim/unclaimed/abc123'),
        isTrue,
      );
      expect(topicMatches('grid/claim/#', 'grid/claim'), isTrue);
      expect(topicMatches('grid/claim/#', 'grid/claimant'), isFalse);
    });

    test('# and + compose', () {
      expect(
        topicMatches('grid/+/claim/#', 'grid/studio/claim/unclaimed/x'),
        isTrue,
      );
    });

    test('a bare # matches everything', () {
      expect(topicMatches('#', 'grid/claim/unclaimed/x'), isTrue);
      expect(topicMatches('#', 'grid'), isTrue);
    });
  });
}
