/// The split distribution — sample count, session count, p50/p90/p99/max, and
/// the worst session behind the max. Pure: built from samples, never from IO.
library;

/// One observation: a value and the session it came from, so the max can name
/// its worst session.
typedef MetricSample = ({num value, String sessionId});

/// The sparse-split floor — a split with fewer than this many SAMPLED
/// SESSIONS reports insufficient-data instead of percentiles. ONE named
/// constant, echoed in the report's human face and its JSON.
const int kDefaultSparseSampleThreshold = 5;

/// The default headroom a recommended high-water mark carries.
const double kDefaultHeadroomFactor = 1.5;

/// A distribution over [MetricSample]s.
class Distribution {
  const Distribution._({
    required this.sampleCount,
    required this.sessionCount,
    required this.threshold,
    this.p50,
    this.p90,
    this.p99,
    this.max,
    this.worstSessionId,
  });

  /// Builds the distribution of [samples] against [threshold].
  ///
  /// A sample whose metric was absent is NEVER passed in as a zero — the
  /// caller drops it, so an unreported metric shows as a low session count
  /// (and, below [threshold], as insufficient-data) rather than a false zero.
  factory Distribution.from(
    List<MetricSample> samples, {
    int threshold = kDefaultSparseSampleThreshold,
  }) {
    if (threshold < 1) {
      throw ArgumentError.value(
        threshold,
        'threshold',
        'Distribution.from: threshold must be a positive integer',
      );
    }
    final sessions = <String>{for (final sample in samples) sample.sessionId};
    if (sessions.length < threshold) {
      return Distribution._(
        sampleCount: samples.length,
        sessionCount: sessions.length,
        threshold: threshold,
      );
    }
    final sorted = [...samples]
      ..sort((a, b) {
        final byValue = a.value.compareTo(b.value);
        return byValue != 0 ? byValue : a.sessionId.compareTo(b.sessionId);
      });
    final worst = sorted.last;
    return Distribution._(
      sampleCount: samples.length,
      sessionCount: sessions.length,
      threshold: threshold,
      p50: _percentile(sorted, 50),
      p90: _percentile(sorted, 90),
      p99: _percentile(sorted, 99),
      max: worst.value,
      worstSessionId: worst.sessionId,
    );
  }

  /// Nearest-rank percentile over the ascending [sorted] samples: rank is
  /// `ceil(percentile/100 * n)` clamped to `[1, n]`. No interpolation — a
  /// reported percentile is always a value that actually occurred.
  static num _percentile(List<MetricSample> sorted, int percentile) {
    final raw = (sorted.length * percentile / 100).ceil();
    final rank = raw < 1 ? 1 : (raw > sorted.length ? sorted.length : raw);
    return sorted[rank - 1].value;
  }

  /// How many observations fed this distribution.
  final int sampleCount;

  /// How many DISTINCT sessions those observations came from — the count the
  /// sparse threshold is measured in.
  final int sessionCount;

  /// The sparse floor this distribution was built against.
  final int threshold;

  /// The median, or null when [insufficientData].
  final num? p50;

  /// The 90th percentile, or null when [insufficientData].
  final num? p90;

  /// The 99th percentile, or null when [insufficientData].
  final num? p99;

  /// The maximum, or null when [insufficientData].
  final num? max;

  /// The session behind [max] — the worst-session provenance.
  final String? worstSessionId;

  /// True when too few sessions sampled to report percentiles honestly.
  bool get insufficientData => sessionCount < threshold;

  /// The sentence a sparse split prints in place of its numbers.
  String get insufficientDataReason =>
      'insufficient-data: $sessionCount session(s) '
      '($sampleCount observation(s)) below the threshold of $threshold';

  /// JSON form. A sparse split emits its counts and the reason — never a
  /// percentile, never a zero, and never nothing.
  Map<String, dynamic> toJson() => insufficientData
      ? {
          'sampleCount': sampleCount,
          'sessionCount': sessionCount,
          'threshold': threshold,
          'insufficientData': true,
          'reason': insufficientDataReason,
        }
      : {
          'sampleCount': sampleCount,
          'sessionCount': sessionCount,
          'threshold': threshold,
          'insufficientData': false,
          'p50': p50,
          'p90': p90,
          'p99': p99,
          'max': max,
          'worstSessionId': worstSessionId,
        };
}
