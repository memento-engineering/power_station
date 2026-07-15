/// The DART-domain RELEASE service — the deterministic, UI-drivable substrate
/// under the operator `release` skill (the coupled skill+command pattern: the
/// skill CALLS this via the exported [ReleaseCommand], parses its structured
/// JSON, and never scrapes prose).
///
/// Codifies genesis's `docs/publishing.md` house rules, generalized to any Dart
/// repo: pre-1.0 version discipline (additive/fix/docs -> PATCH; breaking ->
/// MINOR pre-1.0 / MAJOR from 1.0), the per-package `<pub-name>-v<version>` tag,
/// the scrub gate (no internal refs in the published archive), dependency-order
/// publish resolution, the `dart pub publish --dry-run` gate, and the pub.dev
/// `latest`-version poll.
///
/// THIN-by-rule layering (the CLI-SDK redline): all logic lives HERE (a Flutter
/// UI could drive the same service); [ReleaseCommand] only parses argv and
/// renders these results. The two IO edges ride injected seams
/// ([ProcessRunner] / [HttpGetter]), so the whole service tests offline.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

/// The class of change a release carries — the input to the version bump
/// (genesis `publishing.md`: "Additive API, fixes, docs -> patch"; "Breaking ->
/// minor").
enum ReleaseChange {
  /// A docs-only refresh (README/CHANGELOG/dartdoc) — PATCH.
  docs,

  /// Additive public API — PATCH (still non-breaking pre-1.0).
  additive,

  /// A bug fix — PATCH.
  fix,

  /// A breaking change — MINOR pre-1.0 (`0.y.z` -> `0.(y+1).0`), MAJOR from 1.0.
  breaking;

  /// Parses a wire/flag [value]; null for an unknown one (the caller refuses
  /// rather than guessing — fail-closed, matching `PubLinkContext.parse`).
  static ReleaseChange? parse(String? value) => switch (value) {
    'docs' => ReleaseChange.docs,
    'additive' => ReleaseChange.additive,
    'fix' => ReleaseChange.fix,
    'breaking' => ReleaseChange.breaking,
    _ => null,
  };

  /// Whether this change breaks consumers (the MINOR/MAJOR bump + the leading
  /// `Breaking:` CHANGELOG entry). docs/additive/fix are all a PATCH.
  bool get isBreaking => this == ReleaseChange.breaking;
}

/// The computed version move for a release — the result of
/// [ReleaseService.planVersion].
class ReleaseVersionPlan {
  /// Wraps the [current] -> [next] move for [change].
  const ReleaseVersionPlan({
    required this.current,
    required this.next,
    required this.change,
  });

  /// The current published version.
  final Version current;

  /// The computed next version.
  final Version next;

  /// The change class that drove the bump.
  final ReleaseChange change;

  /// Whether the CHANGELOG entry must lead with `Breaking:` + a migration line
  /// (genesis `publishing.md`) — true iff [change] is breaking. The command
  /// FLAGS this; the skill FRAMES the prose.
  bool get requiresBreakingChangelog => change.isBreaking;

  /// JSON form — the structured contract the release skill consumes.
  Map<String, dynamic> toJson() => {
    'current': current.toString(),
    'next': next.toString(),
    'change': change.name,
    'requiresBreakingChangelog': requiresBreakingChangelog,
  };
}

/// One scrub-gate offence: a [file] + 1-based [line] where an internal
/// reference leaked into text the published archive ships or pub.dev renders.
class ScrubHit {
  /// Wraps a single offending line.
  const ScrubHit({
    required this.file,
    required this.line,
    required this.text,
    required this.match,
  });

  /// The offending file, relative to the scanned package dir.
  final String file;

  /// The 1-based line number.
  final int line;

  /// The offending line, trimmed.
  final String text;

  /// The matched internal-ref token.
  final String match;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'file': file,
    'line': line,
    'text': text,
    'match': match,
  };
}

/// The scrub gate's structured verdict over a package dir.
class ScrubResult {
  /// Wraps the [hits] found scanning [root]'s [filesScanned] files.
  const ScrubResult({
    required this.root,
    required this.hits,
    required this.filesScanned,
  });

  /// The scanned package dir.
  final String root;

  /// Every offence, sorted by (file, line).
  final List<ScrubHit> hits;

  /// How many files were actually read (the coverage denominator).
  final int filesScanned;

  /// The gate passes iff nothing leaked (genesis `publishing.md`: expect empty).
  bool get clean => hits.isEmpty;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'root': root,
    'clean': clean,
    'filesScanned': filesScanned,
    'hits': [for (final h in hits) h.toJson()],
  };
}

/// The dependency-order publish sequence — the result of
/// [ReleaseService.publishOrder].
class PublishOrder {
  /// Wraps the resolved [order] (publish first -> last).
  const PublishOrder(this.order);

  /// The packages in publish order: a package's in-set dependencies all
  /// precede it.
  final List<String> order;

  /// JSON form.
  Map<String, dynamic> toJson() => {'order': order};
}

/// The `dart pub publish --dry-run` gate's structured verdict (genesis
/// `publishing.md` gate 5: 0 warnings).
class DryRunResult {
  /// Wraps the dry-run outcome for [package].
  const DryRunResult({
    required this.package,
    required this.exitCode,
    required this.warningCount,
    required this.warnings,
  });

  /// The package the dry-run ran for (informational; may be empty).
  final String package;

  /// The `dart pub publish --dry-run` exit code.
  final int exitCode;

  /// How many warnings pub reported (`Package has N warnings.`).
  final int warningCount;

  /// The warning detail lines pub printed (the `* ...` bullets).
  final List<String> warnings;

  /// The gate passes iff the process succeeded with zero warnings.
  bool get clean => exitCode == 0 && warningCount == 0;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'package': package,
    'exitCode': exitCode,
    'warningCount': warningCount,
    'clean': clean,
    'warnings': warnings,
  };
}

/// The pub.dev `latest`-version poll's structured verdict (genesis
/// `publishing.md`: poll until the new version is `latest` before publishing a
/// dependent).
class PollResult {
  /// Wraps the poll for [package] at the [wanted] version.
  const PollResult({
    required this.package,
    required this.wanted,
    required this.latest,
    required this.isPublished,
  });

  /// The polled package.
  final String package;

  /// The version the caller is waiting for.
  final String wanted;

  /// The pub.dev `latest` version, or null when the API had no version / the
  /// fetch failed (a not-yet-resolvable package is `null`, never an error).
  final String? latest;

  /// True iff [latest] equals [wanted] — the "safe to publish a dependent"
  /// signal.
  final bool isPublished;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'package': package,
    'wanted': wanted,
    'latest': latest,
    'isPublished': isPublished,
  };
}

/// A minimal HTTP GET result (the [HttpGetter] seam's return) — status + body,
/// so the poll parses offline with a Fake.
class HttpFetch {
  /// Wraps a fetch [statusCode] + [body].
  const HttpFetch({required this.statusCode, required this.body});

  /// The HTTP status code.
  final int statusCode;

  /// The response body (UTF-8 decoded).
  final String body;
}

/// The process seam — runs a subprocess and yields its [ProcessResult]. The
/// default is [Process.run]; tests inject a Fake that records argv and returns
/// canned output (Fakes, not mocks).
typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// The fetch seam — GETs a URL and yields an [HttpFetch]. The default uses
/// `dart:io`'s [HttpClient] (dependency-light — no `http` package); tests
/// inject a Fake.
typedef HttpGetter = Future<HttpFetch> Function(Uri url);

Future<ProcessResult> _defaultProcessRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.run(executable, arguments, workingDirectory: workingDirectory);

Future<HttpFetch> _defaultHttpGetter(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return HttpFetch(statusCode: response.statusCode, body: body);
  } finally {
    client.close(force: true);
  }
}

/// The reusable, UI-drivable RELEASE service — the deterministic half of the
/// coupled `release` skill+command (ADR-0001). Pure version/tag/scrub/order
/// logic plus two thin IO edges behind injected seams.
class ReleaseService {
  /// Creates the service over the [runProcess] + [httpGet] seams (defaults hit
  /// the real process/network; tests inject Fakes).
  const ReleaseService({
    ProcessRunner runProcess = _defaultProcessRunner,
    HttpGetter httpGet = _defaultHttpGetter,
  }) : _run = runProcess,
       _http = httpGet;

  final ProcessRunner _run;
  final HttpGetter _http;

  /// The scrub pattern (genesis `publishing.md`): internal refs no published
  /// archive may carry — an ADR/register number, a bare `A<n>` amendment id,
  /// `register`, or `spike`. Case-insensitive (the `-i` grep flag).
  static final RegExp _internalRef = RegExp(
    r'ADR-?[0-9]|register|\bA[0-9]{1,2}\b|spike',
    caseSensitive: false,
  );

  /// The one sanctioned false positive: a line naming `A2UI` (a real wire
  /// vocabulary) is exempt WHOLE, matching `... | grep -viE "A2UI"`.
  static final RegExp _sanctioned = RegExp('A2UI', caseSensitive: false);

  /// Warnings-count marker in `dart pub publish --dry-run` output.
  static final RegExp _warningCount = RegExp(r'Package has (\d+) warning');

  /// Computes the next version for [change] off [current], per genesis
  /// `publishing.md`'s pre-1.0 discipline: docs/additive/fix -> PATCH; breaking
  /// -> MINOR pre-1.0 (`0.y.z` -> `0.(y+1).0`, escaping pub's `^0.1.0` =
  /// `>=0.1.0 <0.2.0` caret range), MAJOR from 1.0. A non-semver [current] is a
  /// LOUD [ArgumentError] (never a guessed bump).
  ReleaseVersionPlan planVersion({
    required String current,
    required ReleaseChange change,
  }) {
    final Version now;
    try {
      now = Version.parse(current);
    } on FormatException catch (e) {
      throw ArgumentError.value(
        current,
        'current',
        'not a semantic version: ${e.message}',
      );
    }
    final next = switch (change.isBreaking) {
      false => now.nextPatch,
      true => now.major == 0 ? now.nextMinor : now.nextMajor,
    };
    return ReleaseVersionPlan(current: now, next: next, change: change);
  }

  /// The per-package git tag `<package>-v<version>` (genesis `publishing.md`:
  /// `genesis_tree-v0.1.5`) — the house convention, NOT lenny's drifted
  /// repo-level `v0.1.1` (the anti-pattern the skill migrates away from).
  String tagFor({required String package, required String version}) =>
      '$package-v$version';

  /// Scans one file's [content] for internal refs, line by line — the pure
  /// heart of the scrub gate. A line carrying `A2UI` is exempt WHOLE (the
  /// sanctioned false positive). Returns the offences with 1-based line
  /// numbers, in file order.
  List<ScrubHit> scrubContent(String content, {String file = ''}) {
    final out = <ScrubHit>[];
    final lines = const LineSplitter().convert(content);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_sanctioned.hasMatch(line)) continue;
      final match = _internalRef.firstMatch(line);
      if (match != null) {
        out.add(
          ScrubHit(
            file: file,
            line: i + 1,
            text: line.trim(),
            match: match.group(0)!,
          ),
        );
      }
    }
    return out;
  }

  /// Scans the publish-visible surface of [packageDir] — `README.md`,
  /// `CHANGELOG.md`, and every `.dart` under `lib/` and `example/` (the
  /// archived-and-rendered text set, genesis `publishing.md` scrub gate) — for
  /// internal refs. Missing files/dirs are skipped (not every package ships an
  /// `example/`). Deterministic: hits sorted by (file, line).
  ScrubResult scrubDir(String packageDir) {
    final targets = <File>[
      File(p.join(packageDir, 'README.md')),
      File(p.join(packageDir, 'CHANGELOG.md')),
    ];
    for (final sub in const ['lib', 'example']) {
      final dir = Directory(p.join(packageDir, sub));
      if (dir.existsSync()) {
        targets.addAll(
          dir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
        );
      }
    }
    final hits = <ScrubHit>[];
    var scanned = 0;
    for (final file in targets) {
      if (!file.existsSync()) continue;
      scanned++;
      final rel = p.relative(file.path, from: packageDir);
      hits.addAll(scrubContent(file.readAsStringSync(), file: rel));
    }
    hits.sort(
      (a, b) => a.file != b.file ? a.file.compareTo(b.file) : a.line - b.line,
    );
    return ScrubResult(root: packageDir, hits: hits, filesScanned: scanned);
  }

  /// Resolves the dependency-order publish sequence for [deps] — a map of
  /// package -> the SAME-RELEASE-SET packages it depends on. Kahn topological
  /// sort with ties broken alphabetically (deterministic); a dep on a package
  /// NOT in [deps] is an external/hosted dep and ignored. A CYCLE is a LOUD
  /// [StateError] — never a partial order (guards LOUD or GONE).
  PublishOrder publishOrder(Map<String, List<String>> deps) {
    final nodes = deps.keys.toList()..sort();
    final indegree = {for (final n in nodes) n: 0};
    final dependents = {for (final n in nodes) n: <String>[]};
    for (final node in nodes) {
      for (final dep in deps[node]!) {
        if (!indegree.containsKey(dep)) continue; // external dep
        indegree[node] = indegree[node]! + 1;
        dependents[dep]!.add(node);
      }
    }
    final ready = [for (final n in nodes) if (indegree[n] == 0) n]..sort();
    final order = <String>[];
    while (ready.isNotEmpty) {
      final node = ready.removeAt(0);
      order.add(node);
      for (final dependent in dependents[node]!) {
        indegree[dependent] = indegree[dependent]! - 1;
        if (indegree[dependent] == 0) {
          ready
            ..add(dependent)
            ..sort();
        }
      }
    }
    if (order.length != nodes.length) {
      final cyclic = [for (final n in nodes) if (!order.contains(n)) n];
      throw StateError(
        'publish order has a dependency cycle among: ${cyclic.join(', ')}',
      );
    }
    return PublishOrder(order);
  }

  /// Runs `dart pub publish --dry-run` in [packageDir] via the [ProcessRunner]
  /// seam and parses the gate verdict (genesis `publishing.md` gate 5). Thin:
  /// no live pub in tests — the seam is injected.
  Future<DryRunResult> dryRun({
    required String packageDir,
    String package = '',
  }) async {
    final result = await _run(
      'dart',
      const ['pub', 'publish', '--dry-run'],
      workingDirectory: packageDir,
    );
    final text = '${result.stdout}\n${result.stderr}';
    final match = _warningCount.firstMatch(text);
    final warningCount = match != null
        ? int.parse(match.group(1)!)
        : (result.exitCode == 0 ? 0 : 1);
    final warnings = [
      for (final line in const LineSplitter().convert(text))
        if (line.trimLeft().startsWith('* ')) line.trim(),
    ];
    return DryRunResult(
      package: package,
      exitCode: result.exitCode,
      warningCount: warningCount,
      warnings: warnings,
    );
  }

  /// Polls `https://pub.dev/api/packages/<package>` ONCE via the [HttpGetter]
  /// seam and reports whether [version] is now `latest` (genesis
  /// `publishing.md`: poll before publishing a dependent). ONE probe — the
  /// skill loops it between dependency-order publishes. Thin: no live network
  /// in tests.
  Future<PollResult> poll({
    required String package,
    required String version,
  }) async {
    final fetch = await _http(
      Uri.parse('https://pub.dev/api/packages/$package'),
    );
    String? latest;
    if (fetch.statusCode == 200) {
      try {
        final decoded = jsonDecode(fetch.body);
        if (decoded is Map) {
          final latestField = decoded['latest'];
          if (latestField is Map && latestField['version'] is String) {
            latest = latestField['version'] as String;
          }
        }
      } on FormatException {
        latest = null; // a non-JSON body is "not resolvable yet", not a crash
      }
    }
    return PollResult(
      package: package,
      wanted: version,
      latest: latest,
      isPublished: latest == version,
    );
  }
}
