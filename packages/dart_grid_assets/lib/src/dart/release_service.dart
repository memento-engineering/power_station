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

import 'pub_links.dart';

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
  breaking,

  /// A breaking-release candidate — the next breaking stable base as `rc.N`.
  rc;

  /// Parses a wire/flag [value]; null for an unknown one (the caller refuses
  /// rather than guessing — fail-closed, matching `PubLinkContext.parse`).
  static ReleaseChange? parse(String? value) => switch (value) {
    'docs' => ReleaseChange.docs,
    'additive' => ReleaseChange.additive,
    'fix' => ReleaseChange.fix,
    'breaking' => ReleaseChange.breaking,
    'rc' => ReleaseChange.rc,
    _ => null,
  };

  /// Whether this change breaks consumers (the MINOR/MAJOR bump + the leading
  /// `Breaking:` CHANGELOG entry). docs/additive/fix are all a PATCH.
  bool get isBreaking => switch (this) {
    ReleaseChange.breaking || ReleaseChange.rc => true,
    ReleaseChange.docs || ReleaseChange.additive || ReleaseChange.fix => false,
  };

  /// Whether this change plans a pre-release version.
  bool get isPreRelease => this == ReleaseChange.rc;
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

/// The private git-tag operation's structured result.
class ReleaseTagResult {
  /// Wraps the tag attempt for [tag] inside [repoDir].
  const ReleaseTagResult({
    required this.tag,
    required this.repoDir,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// The tag that was requested.
  final String tag;

  /// The repository directory where `git tag` ran.
  final String repoDir;

  /// The `git tag` process exit code.
  final int exitCode;

  /// The process stdout.
  final String stdout;

  /// The process stderr.
  final String stderr;

  /// True iff the tag command succeeded.
  bool get created => exitCode == 0;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'tag': tag,
    'repoDir': repoDir,
    'exitCode': exitCode,
    'created': created,
    'stdout': stdout,
    'stderr': stderr,
  };
}

/// One downstream consumer to validate against a candidate rc tag.
class ReleaseConsumer {
  /// Creates a consumer manifest entry.
  const ReleaseConsumer({
    required this.name,
    required this.directory,
    required this.links,
  });

  /// A human-readable consumer name for reports.
  final String name;

  /// The consumer checkout directory where commands run.
  final String directory;

  /// The producer package links to pin to the candidate rc.
  final List<PubLink> links;

  /// Parses a consumer manifest entry.
  static ReleaseConsumer fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final directory = json['directory'];
    final rawLinks = json['links'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('consumer requires a non-empty name');
    }
    if (directory is! String || directory.isEmpty) {
      throw const FormatException('consumer requires a non-empty directory');
    }
    if (rawLinks is! List) {
      throw const FormatException('consumer requires a links list');
    }
    return ReleaseConsumer(
      name: name,
      directory: directory,
      links: [
        for (final entry in rawLinks)
          if (entry is Map)
            PubLink.fromJson(entry.cast<String, Object?>())
          else
            throw const FormatException(
              'consumer link entries must be objects',
            ),
      ],
    );
  }

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'name': name,
    'directory': directory,
    'links': [for (final link in links) link.toJson()],
  };
}

/// The validation result for one consumer.
class ConsumerValidationResult {
  /// Wraps the analyze/test results for one consumer.
  const ConsumerValidationResult({
    required this.name,
    required this.directory,
    required this.overridePath,
    required this.analyzeExitCode,
    required this.testExitCode,
    required this.stdout,
    required this.stderr,
  });

  /// The consumer name.
  final String name;

  /// The consumer checkout directory.
  final String directory;

  /// The `pubspec_overrides.yaml` path written for the rc pin.
  final String overridePath;

  /// The `dart analyze` exit code.
  final int analyzeExitCode;

  /// The `dart test` exit code, or null when analyze failed and tests were
  /// skipped.
  final int? testExitCode;

  /// Combined stdout from analyze and test.
  final String stdout;

  /// Combined stderr from analyze and test.
  final String stderr;

  /// True iff both analyze and test passed.
  bool get passed => analyzeExitCode == 0 && testExitCode == 0;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'name': name,
    'directory': directory,
    'overridePath': overridePath,
    'analyzeExitCode': analyzeExitCode,
    'testExitCode': testExitCode,
    'passed': passed,
    'stdout': stdout,
    'stderr': stderr,
  };

  /// Parses a validation result emitted by the command.
  static ConsumerValidationResult fromJson(Map<String, Object?> json) =>
      ConsumerValidationResult(
        name: json['name'] as String,
        directory: json['directory'] as String,
        overridePath: json['overridePath'] as String,
        analyzeExitCode: json['analyzeExitCode'] as int,
        testExitCode: json['testExitCode'] as int?,
        stdout: json['stdout'] as String? ?? '',
        stderr: json['stderr'] as String? ?? '',
      );
}

/// The all-consumer validation report for a candidate rc tag.
class ConsumerValidationReport {
  /// Creates a report for [rcTag].
  const ConsumerValidationReport({required this.rcTag, required this.results});

  /// The candidate rc tag that consumers resolved against.
  final String rcTag;

  /// One result per consumer.
  final List<ConsumerValidationResult> results;

  /// True iff there is at least one consumer and every consumer passed.
  bool get allPassed => results.isNotEmpty && results.every((r) => r.passed);

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'rcTag': rcTag,
    'allPassed': allPassed,
    'results': [for (final result in results) result.toJson()],
  };

  /// Parses a validation report emitted by the command.
  static ConsumerValidationReport fromJson(Map<String, Object?> json) =>
      ConsumerValidationReport(
        rcTag: json['rcTag'] as String,
        results: [
          for (final entry in json['results'] as List)
            ConsumerValidationResult.fromJson(
              (entry as Map).cast<String, Object?>(),
            ),
        ],
      );
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
  /// archive may carry — an ADR number, a bare `A<n>` amendment id,
  /// decision-register vocabulary, or `spike`. The generic verb `register`
  /// is deliberately not an offence. Case-insensitive (the `-i` grep flag).
  static final RegExp _internalRef = RegExp(
    r'ADR-?[0-9]|\b(?:the\s+register|decision(?:-|\s+)register)\b|'
    r'\bA[0-9]{1,2}\b|spike',
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
    final next = switch (change) {
      ReleaseChange.docs ||
      ReleaseChange.additive ||
      ReleaseChange.fix => now.nextPatch,
      ReleaseChange.breaking => now.major == 0 ? now.nextMinor : now.nextMajor,
      ReleaseChange.rc => _nextRc(now),
    };
    return ReleaseVersionPlan(current: now, next: next, change: change);
  }

  Version _nextRc(Version now) {
    if (now.preRelease.isEmpty) {
      final stableBase = now.major == 0 ? now.nextMinor : now.nextMajor;
      return Version(
        stableBase.major,
        stableBase.minor,
        stableBase.patch,
        pre: 'rc.1',
      );
    }
    final pre = now.preRelease;
    if (pre.length == 2 && pre[0] == 'rc' && pre[1] is int) {
      return Version(
        now.major,
        now.minor,
        now.patch,
        pre: 'rc.${(pre[1] as int) + 1}',
      );
    }
    throw ArgumentError.value(
      now.toString(),
      'current',
      'pre-release current must be an rc.N version to plan the next rc',
    );
  }

  /// The per-package git tag `<package>-v<version>` (genesis `publishing.md`:
  /// `genesis_tree-v0.1.5`) — the house convention, NOT lenny's drifted
  /// repo-level `v0.1.1` (the anti-pattern the skill migrates away from).
  String tagFor({required String package, required String version}) =>
      '$package-v$version';

  /// Cuts a private git release [tag] in [repoDir].
  Future<ReleaseTagResult> createGitTag({
    required String repoDir,
    required String tag,
  }) async {
    final result = await _run('git', ['tag', tag], workingDirectory: repoDir);
    return ReleaseTagResult(
      tag: tag,
      repoDir: repoDir,
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }

  /// Pins every [consumers] link to [rcTag], writes `pubspec_overrides.yaml`,
  /// then runs `dart analyze && dart test` per consumer.
  Future<ConsumerValidationReport> validateConsumers({
    required String rcTag,
    required List<ReleaseConsumer> consumers,
  }) async {
    final results = <ConsumerValidationResult>[];
    for (final consumer in consumers) {
      final pinned = PubLinkConfig(
        links: [
          for (final link in consumer.links)
            PubLink(
              package: link.package,
              devPath: link.devPath,
              hosted: link.hosted,
              gitUrl: link.gitUrl,
              gitRef: rcTag,
            ),
        ],
      );
      final overrides = pubspecOverridesFor(pinned, PubLinkContext.stable);
      if (overrides == null) {
        throw StateError(
          'consumer "${consumer.name}" has no git-pinned links to validate '
          'against $rcTag',
        );
      }
      final overrideFile = File(
        p.join(consumer.directory, 'pubspec_overrides.yaml'),
      );
      overrideFile.writeAsStringSync(overrides);
      final analyze = await _run('dart', const [
        'analyze',
      ], workingDirectory: consumer.directory);
      ProcessResult? test;
      if (analyze.exitCode == 0) {
        test = await _run('dart', const [
          'test',
        ], workingDirectory: consumer.directory);
      }
      results.add(
        ConsumerValidationResult(
          name: consumer.name,
          directory: consumer.directory,
          overridePath: overrideFile.path,
          analyzeExitCode: analyze.exitCode,
          testExitCode: test?.exitCode,
          stdout: '${analyze.stdout}\n${test?.stdout ?? ''}',
          stderr: '${analyze.stderr}\n${test?.stderr ?? ''}',
        ),
      );
    }
    return ConsumerValidationReport(rcTag: rcTag, results: results);
  }

  /// Cuts [stableTag] only after [validation] reports every consumer passed.
  Future<ReleaseTagResult> promoteTag({
    required String repoDir,
    required String stableTag,
    required ConsumerValidationReport validation,
  }) async {
    if (!validation.allPassed) {
      final failed = validation.results
          .where((result) => !result.passed)
          .map((result) => result.name)
          .join(', ');
      throw StateError(
        failed.isEmpty
            ? 'promote refused: no passing consumer validation results'
            : 'promote refused: failing consumers: $failed',
      );
    }
    return createGitTag(repoDir: repoDir, tag: stableTag);
  }

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
    final ready = [
      for (final n in nodes)
        if (indegree[n] == 0) n,
    ]..sort();
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
      final cyclic = [
        for (final n in nodes)
          if (!order.contains(n)) n,
      ];
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
    final result = await _run('dart', const [
      'pub',
      'publish',
      '--dry-run',
    ], workingDirectory: packageDir);
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
