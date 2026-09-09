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

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

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

/// One direct workspace-sibling dependency and the exact floor under test.
class DeclaredFloorPin {
  /// Creates a pin derived from [declaredConstraint].
  const DeclaredFloorPin({
    required this.package,
    required this.declaredConstraint,
    required this.floor,
  });

  /// The workspace sibling's pub package name.
  final String package;

  /// The constraint authored in the candidate's `dependencies` map.
  final String declaredConstraint;

  /// The inclusive minimum extracted from [declaredConstraint].
  final String floor;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'package': package,
    'declaredConstraint': declaredConstraint,
    'floor': floor,
  };
}

/// The candidate's analyze verdict when every direct workspace sibling is
/// exact-pinned at its DECLARED floor.
///
/// [ConsumerValidationResult] proves a consumer accepts the new version;
/// this proves the candidate itself compiles against the minimums it
/// PROMISES — the leg a pub workspace hides, because siblings resolve by path
/// and a member added in one package is instantly visible in another.
class DeclaredFloorsValidationResult {
  /// Creates the structured declared-floors verdict.
  const DeclaredFloorsValidationResult({
    required this.candidate,
    required this.pins,
    required this.pubGetExitCode,
    required this.analyzeExitCode,
    required this.stdout,
    required this.stderr,
  });

  /// The candidate pub package name.
  final String candidate;

  /// The exact sibling floors installed in `pubspec_overrides.yaml`.
  final List<DeclaredFloorPin> pins;

  /// The `dart pub get` exit code.
  final int pubGetExitCode;

  /// The `dart analyze` exit code, or null when pub get failed.
  final int? analyzeExitCode;

  /// Combined process stdout.
  final String stdout;

  /// Combined process stderr.
  final String stderr;

  /// Whether resolution and analysis both passed.
  bool get passed => pubGetExitCode == 0 && analyzeExitCode == 0;

  /// A self-contained diagnostic naming every sibling floor and raw tool
  /// output — so a failure reads as "symbol X, sibling Y, floor Z".
  String get message {
    final floors = pins.isEmpty
        ? 'no direct workspace-sibling dependencies'
        : pins
              .map(
                (pin) =>
                    '${pin.package}@${pin.floor} '
                    '(declared ${pin.declaredConstraint})',
              )
              .join(', ');
    final summary = passed
        ? 'declared-floor validation passed for $candidate at $floors'
        : 'declared-floor validation failed for $candidate at $floors';
    final diagnostics = [
      stderr.trim(),
      stdout.trim(),
    ].where((value) => value.isNotEmpty).join('\n');
    return diagnostics.isEmpty ? summary : '$summary\n$diagnostics';
  }

  /// JSON form consumed inside the release scrub result.
  Map<String, dynamic> toJson() => {
    'candidate': candidate,
    'pins': [for (final pin in pins) pin.toJson()],
    'pubGetExitCode': pubGetExitCode,
    'analyzeExitCode': analyzeExitCode,
    'passed': passed,
    'message': message,
    'stdout': stdout,
    'stderr': stderr,
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
  /// Wraps the [hits] found scanning [root]'s [filesScanned] files, plus the
  /// [declaredFloors] verdict when the complete gate ran.
  const ScrubResult({
    required this.root,
    required this.hits,
    required this.filesScanned,
    this.declaredFloors,
  });

  /// The scanned package dir.
  final String root;

  /// Every offence, sorted by (file, line).
  final List<ScrubHit> hits;

  /// How many files were actually read (the coverage denominator).
  final int filesScanned;

  /// Present when the complete release scrub gate ran (i.e. through
  /// [ReleaseService.scrubPackage]); null for a content-only
  /// [ReleaseService.scrubDir] scan.
  final DeclaredFloorsValidationResult? declaredFloors;

  /// The gate passes iff nothing leaked (genesis `publishing.md`: expect empty)
  /// AND — when it ran — the candidate compiled at its declared floors.
  bool get clean =>
      hits.isEmpty && (declaredFloors == null || declaredFloors!.passed);

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'root': root,
    'clean': clean,
    'filesScanned': filesScanned,
    'hits': [for (final h in hits) h.toJson()],
    if (declaredFloors != null) 'declaredFloors': declaredFloors!.toJson(),
  };
}

/// The read-only WORKSPACE DISCOVERY answer — "what does this workspace need
/// to release" — read off melos, which already knows it, instead of a
/// per-package pub.dev curl plus a per-package
/// `git log <ref>..HEAD -- packages/<pkg>` sweep.
///
/// [candidates] and [changed] answer DIFFERENT questions and are not
/// interchangeable: a package can be unpublished without having changed since
/// a ref (a version authored days ago and never tagged), and can have changed
/// without being a candidate (an edit nobody bumped yet). Neither replaces the
/// authoritative pub.dev predecessor check
/// [ReleaseService.publishWorkspace] runs — this is the operator's PREFLIGHT,
/// not the pre-publish gate.
class ReleaseDiscovery {
  /// Wraps the discovery over [workspaceRoot] against [diff], with its sorted
  /// [candidates] and [changed] package names.
  const ReleaseDiscovery({
    required this.workspaceRoot,
    required this.diff,
    required this.candidates,
    required this.changed,
  });

  /// The normalized absolute pub workspace root both queries ran in.
  final String workspaceRoot;

  /// The git ref the change query compared HEAD against.
  final String diff;

  /// The publishable members whose AUTHORED version is not on pub.dev, sorted
  /// (`melos list --no-published`).
  final List<String> candidates;

  /// The publishable members that changed since [diff], sorted
  /// (`melos list --diff=<ref>`).
  final List<String> changed;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'workspaceRoot': workspaceRoot,
    'diff': diff,
    'candidates': candidates,
    'changed': changed,
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

/// The pub.dev version poll's structured verdict.
class PollResult {
  /// Wraps the poll for [package] at the [wanted] version.
  const PollResult({
    required this.package,
    required this.wanted,
    required this.statusCode,
    required this.versions,
    required this.latest,
    required this.isPublished,
  });

  /// The polled package.
  final String package;

  /// The version the caller is waiting for.
  final String wanted;

  /// The pub.dev API status code for this probe — 200 for a listed package,
  /// 404 for one that has never been published, anything else a fetch the
  /// caller must refuse rather than read as "not yet".
  final int statusCode;

  /// Every version string pub.dev listed, in API order (empty when the fetch
  /// was not a parseable 200). The complete list, so a caller can pick a
  /// predecessor without a second pub.dev parser.
  final List<String> versions;

  /// The pub.dev `latest` version, or null when the API had no version / the
  /// fetch failed (a not-yet-resolvable package is `null`, never an error).
  final String? latest;

  /// True iff [wanted] occurs in pub.dev's complete `versions` list — the
  /// "safe to publish a dependent" signal.
  final bool isPublished;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'package': package,
    'wanted': wanted,
    'statusCode': statusCode,
    'versions': versions,
    'latest': latest,
    'isPublished': isPublished,
  };
}

/// The public-API delta a release actually CARRIES — the requirement half of
/// the classification pair (what the code did to consumers, read off the
/// published baseline rather than off a commit message).
enum ReleaseRequiredChange {
  /// No public API moved between the baseline and HEAD.
  none,

  /// Public API grew, and nothing a consumer already reaches went away — a
  /// PATCH covers it pre-1.0 (genesis `publishing.md`).
  additive,

  /// Public API a consumer may already call was removed or narrowed: a
  /// caret-compatible upgrade would stop compiling.
  breaking,
}

/// The version bump a release DECLARES — the declaration half of the pair,
/// derived from the published baseline -> authored HEAD move (NOT from a
/// commit message: a breaking change that carries no `!` and no
/// `BREAKING CHANGE:` footer still declares whatever the pubspec says).
enum ReleaseDeclaredChange {
  /// The PATCH component moved (`0.3.1` -> `0.3.2`).
  patch,

  /// The MINOR component moved (`0.3.1` -> `0.4.0`).
  minor,

  /// The MAJOR component moved (`0.3.1` -> `1.0.0`).
  major,

  /// HEAD is itself a pre-release (`0.4.0-rc.1`) — the rc-first lane.
  prerelease,

  /// HEAD drops the baseline's pre-release suffix at the same core version
  /// (`0.4.0-rc.1` -> `0.4.0`): a promotion, not a fresh bump.
  promotion;

  /// The noun the classification message uses ("declared 0.3.2 is a patch").
  String get label => switch (this) {
    ReleaseDeclaredChange.patch => 'patch',
    ReleaseDeclaredChange.minor => 'minor',
    ReleaseDeclaredChange.major => 'major',
    ReleaseDeclaredChange.prerelease => 'prerelease',
    ReleaseDeclaredChange.promotion => 'prerelease promotion',
  };
}

/// Whether the declared bump COVERS the API delta the code carries.
enum ReleaseClassificationVerdict {
  /// The declared bump is at least as large as the delta requires.
  ok,

  /// The delta requires more than the declared bump gives — publishing this
  /// version would break consumers on a caret-compatible upgrade.
  understated,
}

/// The release CLASSIFICATION: the public API delta since the LAST PUBLISHED
/// release, paired with the version bump this release declares.
///
/// The pairing is the point. A diff alone says "a symbol changed", which the
/// git diff already said; a declared bump alone says nothing about the code.
/// Together they answer the only question a release gate cares about: does
/// what consumers will resolve still compile against what they already call.
@immutable
class ReleaseClassification {
  /// Wraps the classification of [package] at [head] against [baseline].
  const ReleaseClassification({
    required this.package,
    required this.baseline,
    required this.head,
    required this.removed,
    required this.changed,
    required this.added,
    required this.requiredChange,
    required this.declaredChange,
    required this.verdict,
    required this.message,
  });

  /// The classified package.
  final String package;

  /// The last published version the delta was measured against — what a
  /// consumer resolves TODAY, never a golden file checked into the repo.
  final Version baseline;

  /// The version this working tree authors.
  final Version head;

  /// Removals, `<symbol>: <change>` each, sorted.
  final List<String> removed;

  /// Changes that are neither a plain removal nor a plain addition (an
  /// unfamiliar change code lands here rather than being discarded), sorted.
  final List<String> changed;

  /// Additions, `<symbol>: <change>` each, sorted.
  final List<String> added;

  /// The change class the delta REQUIRES.
  final ReleaseRequiredChange requiredChange;

  /// The change class the authored version DECLARES.
  final ReleaseDeclaredChange declaredChange;

  /// Whether the declaration covers the requirement.
  final ReleaseClassificationVerdict verdict;

  /// The one-line verdict — it names the SYMBOL and the CONSEQUENCE, never
  /// just "something changed".
  final String message;

  /// JSON form — the structured contract the release skill consumes.
  Map<String, dynamic> toJson() => {
    'package': package,
    'baseline': baseline.toString(),
    'head': head.toString(),
    'removed': removed,
    'changed': changed,
    'added': added,
    'requiredChange': requiredChange.name,
    'declaredChange': declaredChange.name,
    'verdict': verdict.name,
    'message': message,
  };
}

/// Where a workspace release wave stopped — the structured frontier a
/// [ReleaseWaveFailure] names, so an operator reads "which stage, which
/// package" without scraping prose.
enum ReleaseWaveStage {
  /// Reading and validating the workspace root and its members.
  workspace,

  /// Computing the changed-package set against pub.dev.
  discovery,

  /// Planning the wave itself (the change class is refused here).
  plan,

  /// The scrub gate over one changed package.
  scrub,

  /// Resolving the dependency-order publish sequence.
  order,

  /// The `dart pub publish --dry-run` gate over one ordered package.
  dryRun,

  /// Resolving the origin-reachable release commit the wave validates at.
  releaseCommit,

  /// The consumer validation a direct stable wave must pass before any tag.
  validateConsumers,

  /// Cutting one package's git tag.
  tag,

  /// Pushing one package's git tag (the push IS the publish).
  push,

  /// Waiting for one package's version to propagate to pub.dev.
  poll;

  /// The wire name the structured failure carries.
  String get wireName => switch (this) {
    ReleaseWaveStage.workspace => 'workspace',
    ReleaseWaveStage.discovery => 'discovery',
    ReleaseWaveStage.plan => 'plan',
    ReleaseWaveStage.scrub => 'scrub',
    ReleaseWaveStage.order => 'order',
    ReleaseWaveStage.dryRun => 'dry-run',
    ReleaseWaveStage.releaseCommit => 'release-commit',
    ReleaseWaveStage.validateConsumers => 'validate-consumers',
    ReleaseWaveStage.tag => 'tag',
    ReleaseWaveStage.push => 'push',
    ReleaseWaveStage.poll => 'poll',
  };
}

/// A workspace release wave that STOPPED — the named [stage], the [package] it
/// stopped on (null for a wave-level stop), and a self-contained [message].
///
/// A wave never degrades: every gate, process and propagation failure raises
/// this, so every package ordered after the stop stays untagged and unpushed.
@immutable
class ReleaseWaveFailure implements Exception {
  /// Creates the structured stop.
  const ReleaseWaveFailure({
    required this.stage,
    required this.message,
    this.package,
  });

  /// The stage that refused.
  final ReleaseWaveStage stage;

  /// The package the stage was working on, or null for a wave-level stop
  /// (workspace, order, release commit, consumer validation).
  final String? package;

  /// The self-contained diagnostic, naming what failed and what to do.
  final String message;

  /// JSON form — the structured contract the release skill parses.
  Map<String, dynamic> toJson() => {
    'stage': stage.wireName,
    'package': package,
    'message': message,
  };

  @override
  String toString() => package == null
      ? 'release wave stopped at ${stage.wireName}: $message'
      : 'release wave stopped at ${stage.wireName} for $package: $message';
}

/// One package in a workspace release wave: what it is, where it lives, the
/// published version it moves off, and the tag whose push publishes it.
@immutable
class ReleaseWavePackage {
  /// Creates the wave entry for [package].
  const ReleaseWavePackage({
    required this.package,
    required this.directory,
    required this.publishedPredecessor,
    required this.localVersion,
    required this.dependencies,
    required this.tag,
  });

  /// The pub package name.
  final String package;

  /// The member directory, relative to the workspace root.
  final String directory;

  /// The published version [localVersion] bumps off, or null when this is a
  /// first release (pub.dev has never seen the package).
  final Version? publishedPredecessor;

  /// The version authored in the member's `pubspec.yaml` — the one the wave
  /// publishes.
  final Version localVersion;

  /// The IN-WAVE packages this one depends on, sorted — the edges the publish
  /// order is resolved from.
  final List<String> dependencies;

  /// The `<package>-v<version>` tag whose push publishes this package.
  final String tag;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'package': package,
    'directory': directory,
    'publishedPredecessor': publishedPredecessor?.toString(),
    'localVersion': localVersion.toString(),
    'dependencies': dependencies,
    'tag': tag,
  };
}

/// A workspace release wave: the dependency-ordered set of packages whose
/// authored versions are not on pub.dev yet, for one change class.
@immutable
class ReleaseWavePlan {
  /// Creates the wave plan.
  const ReleaseWavePlan({
    required this.workspaceRoot,
    required this.change,
    required this.dryRun,
    required this.packages,
  });

  /// The absolute, normalized workspace root the wave ran from.
  final String workspaceRoot;

  /// The change class every package in the wave moves by.
  final ReleaseChange change;

  /// Whether the wave stopped after its gates (no tag, no push, no poll).
  final bool dryRun;

  /// The changed packages, dependency-first: a package's in-wave dependencies
  /// all precede it.
  final List<ReleaseWavePackage> packages;

  /// JSON form — the structured contract the release skill parses.
  Map<String, dynamic> toJson() => {
    'workspaceRoot': workspaceRoot,
    'change': change.name,
    'dryRun': dryRun,
    'packages': [for (final package in packages) package.toJson()],
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

/// The wait seam — the pause a release wave takes between propagation polls.
/// The default is [Future.delayed]; tests inject a Fake that records the
/// requested durations and returns instantly, so a wave suite never sleeps.
typedef ReleaseWait = Future<void> Function(Duration duration);

Future<ProcessResult> _defaultProcessRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.run(executable, arguments, workingDirectory: workingDirectory);

Future<void> _defaultWait(Duration duration) => Future<void>.delayed(duration);

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
  /// Creates the service over the [runProcess] + [httpGet] + [wait] seams
  /// (defaults hit the real process/network/clock; tests inject Fakes).
  const ReleaseService({
    ProcessRunner runProcess = _defaultProcessRunner,
    HttpGetter httpGet = _defaultHttpGetter,
    ReleaseWait wait = _defaultWait,
  }) : _run = runProcess,
       _http = httpGet,
       _wait = wait;

  final ProcessRunner _run;
  final HttpGetter _http;
  final ReleaseWait _wait;

  /// Internal vocabulary working documents may not carry: explicit
  /// decision-register prose or `spike`. Case-insensitive, matching the
  /// genesis `publishing.md` scrub gate.
  static final RegExp _internalRef = RegExp(
    r'\b(?:the\s+register|decision(?:-|\s+)register)\b|spike',
    caseSensitive: false,
  );

  /// Working-document references that are internal outside public Dart
  /// source and standalone Dartdoc: ADRs and amendment-shaped tokens.
  static final RegExp _workingDocRef = RegExp(
    r'ADR-?[0-9]|\bA[0-9]{1,2}\b',
    caseSensitive: false,
  );

  /// The one sanctioned false positive: a line naming `A2UI` (a real wire
  /// vocabulary) is exempt WHOLE, matching `... | grep -viE "A2UI"`.
  static final RegExp _sanctioned = RegExp('A2UI', caseSensitive: false);

  /// Warnings-count marker in `dart pub publish --dry-run` output.
  static final RegExp _warningCount = RegExp(r'Package has (\d+) warning');

  /// The external API-diff tool the classification gate shells out to. It is
  /// NOT a dependency of this package — an unadopted analyzer has no business
  /// in the org's release-gate dependency graph — so it is invoked as an
  /// executable through the [ProcessRunner] seam and swapping it is one change
  /// at one seam.
  static const String _apiTool = 'dart-apitool';

  /// The activation every "analyzer missing" refusal carries, so the operator
  /// reads the fix in the failure rather than hunting for it.
  static const String _apiToolActivation =
      'dart pub global activate dart_apitool';

  /// POSIX "command not found" — the shape a missing [_apiTool] takes when the
  /// runner reports an exit code instead of throwing.
  static const int _commandNotFound = 127;

  /// `dart-apitool` change codes that take something AWAY from consumers.
  static const Set<String> _apiRemovalCodes = {
    'CI01', // interface removed
    'CI05', // supertype removed
    'CI08', // type parameter removed
    'CE01', // executable parameters removed
    'CE10', // executable removed
    'CP02', // entry point removed
    'CF01', // field removed
    'CPI02', // iOS platform removed
    'CPA02', // Android platform removed
    'CPA04', // Android platform min SDK removed
    'CPA07', // Android platform target SDK removed
    'CPA10', // Android platform compile SDK removed
    'CD02', // dependency removed
  };

  /// `dart-apitool` change codes that GIVE consumers something new.
  static const Set<String> _apiAdditionCodes = {
    'CI02', // interface added
    'CI04', // supertype added
    'CI07', // type parameter added
    'CE02', // executable parameters added
    'CE11', // executable added
    'CP01', // new entry point
    'CF02', // field added
    'CPI01', // iOS platform added
    'CPA01', // Android platform added
    'CPA03', // Android platform min SDK added
    'CPA06', // Android platform target SDK added
    'CPA09', // Android platform compile SDK added
    'CD01', // dependency added
  };

  /// The declaration-kind prefixes `dart-apitool` renders on a node label.
  /// Exactly the four it emits — an unlisted label is reported whole rather
  /// than half-stripped by a guessed prefix.
  static const List<String> _declarationPrefixes = [
    'Class ',
    'Constructor ',
    'Field ',
    'Method ',
  ];

  /// The `CE01` detail line — the one change whose consequence is stated
  /// exactly (`calls that supply <name> no longer compile`) rather than
  /// generically.
  static final RegExp _removedParameter = RegExp(
    r'Parameter "([^"]+)" removed',
  );

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

  /// Copies [packageDir], exact-pins its direct workspace siblings at their
  /// DECLARED inclusive minimums, then runs `dart pub get` and `dart analyze`
  /// in that throwaway copy.
  ///
  /// The inverse of [validateConsumers]: same `pubspec_overrides.yaml`
  /// mechanism, but it pins the DEPENDENCIES' floors instead of the candidate.
  /// A pub workspace resolves siblings by path, so a member added in one
  /// package and used in another compiles green even when every published
  /// floor in the chain predates it; this leg is what catches that before the
  /// tag is cut. It resolves against pub.dev, so it belongs to the release
  /// verb, never an offline unit suite.
  ///
  /// A structured/path sibling dependency, an `any`, or an exclusive lower
  /// bound has no exact floor to pin and is a LOUD [StateError] naming that
  /// sibling and its authored constraint (guards LOUD or GONE). Only the
  /// top-level `dependencies` map is read — `dev_dependencies` are not part of
  /// the published runtime contract.
  Future<DeclaredFloorsValidationResult> validateDeclaredFloors({
    required String packageDir,
  }) async {
    final candidateDir = Directory(p.normalize(p.absolute(packageDir)));
    final candidatePubspecFile = File(
      p.join(candidateDir.path, 'pubspec.yaml'),
    );
    final candidatePubspec = _readPubspec(candidatePubspecFile);
    final candidate = _pubspecName(candidatePubspec, candidatePubspecFile.path);
    final pins = _declaredFloorPins(
      candidatePubspec,
      workspacePackageNames: _workspacePackageNames(candidateDir),
      pubspecPath: candidatePubspecFile.path,
    );
    final temp = await Directory.systemTemp.createTemp(
      'release-declared-floors-',
    );
    try {
      final copy = Directory(p.join(temp.path, candidate));
      _copyPackage(candidateDir, copy);
      _removeWorkspaceResolution(File(p.join(copy.path, 'pubspec.yaml')));
      final overrides = pubspecOverridesForExactVersions({
        for (final pin in pins) pin.package: pin.floor,
      });
      if (overrides != null) {
        File(
          p.join(copy.path, 'pubspec_overrides.yaml'),
        ).writeAsStringSync(overrides);
      }

      final pubGet = await _run('dart', const [
        'pub',
        'get',
      ], workingDirectory: copy.path);
      ProcessResult? analyze;
      if (pubGet.exitCode == 0) {
        analyze = await _run('dart', const [
          'analyze',
        ], workingDirectory: copy.path);
      }
      return DeclaredFloorsValidationResult(
        candidate: candidate,
        pins: List<DeclaredFloorPin>.unmodifiable(pins),
        pubGetExitCode: pubGet.exitCode,
        analyzeExitCode: analyze?.exitCode,
        stdout: '${pubGet.stdout}\n${analyze?.stdout ?? ''}',
        stderr: '${pubGet.stderr}\n${analyze?.stderr ?? ''}',
      );
    } finally {
      if (temp.existsSync()) {
        await temp.delete(recursive: true);
      }
    }
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
      final isPublicDartSource = p.extension(file) == '.dart';
      final isDartdoc = line.trimLeft().startsWith('///');
      final internalMatch = isPublicDartSource
          ? null
          : _internalRef.firstMatch(line);
      final workingDocMatch = isPublicDartSource || isDartdoc
          ? null
          : _workingDocRef.firstMatch(line);
      final match = internalMatch ?? workingDocMatch;
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

  /// Runs the COMPLETE online release scrub gate for [packageDir]: the
  /// content scan of [scrubDir] plus the [validateDeclaredFloors] leg. Both
  /// verdicts ride ONE [ScrubResult] — the release skill parses one object.
  Future<ScrubResult> scrubPackage(String packageDir) async {
    final content = scrubDir(packageDir);
    final floors = await validateDeclaredFloors(packageDir: packageDir);
    return ScrubResult(
      root: content.root,
      hits: content.hits,
      filesScanned: content.filesScanned,
      declaredFloors: floors,
    );
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

  /// Answers "what does this workspace need to release" by asking MELOS, in
  /// the pub workspace rooted at [workspaceRoot]: `melos list --no-published`
  /// for the members whose authored version is not on pub.dev, and
  /// `melos list --diff=<[diff]>` for the members that changed since that ref.
  ///
  /// Both queries ride the existing [ProcessRunner] seam as
  /// `dart run melos list ...`, so the op needs no melos dependency here — the
  /// workspace already declares one — and the whole surface tests offline. A
  /// non-zero exit, non-JSON output, a non-array payload, a nameless entry or
  /// a duplicated name is a LOUD [StateError] carrying the command, the exit
  /// code and the process diagnostic; there is no partial candidate set.
  ///
  /// This is a read-only PREFLIGHT. It does not gate a publish and does not
  /// weaken [publishWorkspace], which keeps resolving each member's published
  /// predecessor against pub.dev immediately before it tags.
  Future<ReleaseDiscovery> discoverWorkspace({
    required String workspaceRoot,
    required String diff,
  }) async {
    final root = p.normalize(p.absolute(workspaceRoot));
    final candidates = await _melosPackageNames(root, const [
      '--no-published',
      '--json',
      '--no-private',
    ]);
    final changed = await _melosPackageNames(root, [
      '--diff=$diff',
      '--json',
      '--no-private',
    ]);
    return ReleaseDiscovery(
      workspaceRoot: root,
      diff: diff,
      candidates: candidates,
      changed: changed,
    );
  }

  /// Resolves the dependency-order publish sequence for the pub workspace at
  /// [workspaceRoot] from MELOS's own adjacency graph
  /// (`melos list --json --graph --no-private`), so the graph that decides
  /// publish order is never transcribed into a hand-written manifest.
  ///
  /// Melos emits ALL in-workspace edges — `dependencies`, `dev_dependencies`
  /// AND `dependency_overrides` — and publish order is a statement about the
  /// PUBLISHED runtime contract only. So every emitted edge is filtered
  /// against the source package's top-level `dependencies` map (the same list
  /// [publishWorkspace] orders by) before it reaches [publishOrder]. That is
  /// load-bearing, not cosmetic: lenny's `leonard_agent`, `leonard_flutter`
  /// and `leonard_flutter_test` form a DEV-dependency cycle, which is not a
  /// publish cycle, and ordering the raw graph would refuse a releasable
  /// workspace.
  ///
  /// A graph node that is not a publishable member of the workspace is a LOUD
  /// [StateError] — melos and the pubspec must be describing the same
  /// workspace. A RUNTIME cycle still reaches [publishOrder]'s existing loud
  /// refusal, unchanged.
  Future<PublishOrder> publishOrderFromMelosWorkspace({
    required String workspaceRoot,
  }) async {
    final root = p.normalize(p.absolute(workspaceRoot));
    final decoded = await _runMelosList(root, const [
      '--json',
      '--graph',
      '--no-private',
    ]);
    if (decoded is! Map) {
      throw StateError(
        'melos graph in $root is not a {package: [dependencies]} object.',
      );
    }
    final members = {
      for (final member in _workspaceMembers(root)) member.name: member,
    };
    final deps = <String, List<String>>{};
    for (final entry in decoded.entries) {
      final node = entry.key;
      if (node is! String || node.isEmpty) {
        throw StateError('melos graph in $root has a nameless package key.');
      }
      final member = members[node];
      if (member == null) {
        throw StateError(
          'melos graph in $root names "$node", which is not a publishable '
          'member of that pub workspace (members: '
          '${(members.keys.toList()..sort()).join(', ')}).',
        );
      }
      final edges = entry.value;
      if (edges is! List) {
        throw StateError(
          'melos graph in $root maps "$node" to something other than a list '
          'of dependencies.',
        );
      }
      final runtime = member.dependencies.toSet();
      deps[node] = [
        for (final edge in edges)
          if (edge is String && edge != node && runtime.contains(edge)) edge,
      ]..sort();
    }
    return publishOrder(deps);
  }

  /// Runs one `dart run melos list <arguments>` in [root] through the
  /// [ProcessRunner] seam and yields its decoded JSON. A non-zero exit or
  /// undecodable output is a LOUD [StateError] naming the command, the exit
  /// code and the process diagnostic.
  Future<Object?> _runMelosList(String root, List<String> arguments) async {
    final argv = ['run', 'melos', 'list', ...arguments];
    final result = await _run('dart', argv, workingDirectory: root);
    if (result.exitCode != 0) {
      throw StateError(
        '`dart ${argv.join(' ')}` failed in $root with exit '
        '${result.exitCode}${_melosDiagnostic(result)}',
      );
    }
    try {
      return jsonDecode('${result.stdout}'.trim());
    } on FormatException catch (error) {
      throw StateError(
        '`dart ${argv.join(' ')}` in $root did not emit JSON: '
        '${error.message}${_melosDiagnostic(result)}',
      );
    }
  }

  /// The unique, sorted `name` values of a `melos list --json` array. A
  /// non-array payload, an entry that is not an object, a missing or empty
  /// name, and a duplicated name are each a LOUD [StateError].
  Future<List<String>> _melosPackageNames(
    String root,
    List<String> arguments,
  ) async {
    final decoded = await _runMelosList(root, arguments);
    if (decoded is! List) {
      throw StateError(
        '`dart run melos list ${arguments.join(' ')}` in $root did not emit a '
        'JSON array of packages.',
      );
    }
    final names = <String>[];
    for (final entry in decoded) {
      if (entry is! Map) {
        throw StateError(
          'melos list in $root emitted a package entry that is not an object.',
        );
      }
      final name = entry['name'];
      if (name is! String || name.isEmpty) {
        throw StateError('melos list in $root emitted a package with no name.');
      }
      if (names.contains(name)) {
        throw StateError('melos list in $root named "$name" more than once.');
      }
      names.add(name);
    }
    names.sort();
    return List<String>.unmodifiable(names);
  }

  /// The stderr/stdout tail every melos refusal carries, so the operator reads
  /// what the process actually said instead of only that it failed.
  String _melosDiagnostic(ProcessResult result) {
    final stderrText = '${result.stderr}'.trim();
    final stdoutText = '${result.stdout}'.trim();
    final detail = stderrText.isNotEmpty ? stderrText : stdoutText;
    return detail.isEmpty ? '.' : ':\n$detail';
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
    final overlayWarnings = _hiddenOverlaySourceWarnings(packageDir);
    return DryRunResult(
      package: package,
      exitCode: result.exitCode,
      warningCount: warningCount + overlayWarnings.length,
      warnings: [...warnings, ...overlayWarnings],
    );
  }

  /// Polls `https://pub.dev/api/packages/<package>` ONCE via the [HttpGetter]
  /// seam and reports whether [version] occurs in the complete `versions` list.
  /// The top-level `latest` stable version remains informational. ONE probe —
  /// the skill loops it between dependency-order publishes. Thin: no live
  /// network in tests.
  Future<PollResult> poll({
    required String package,
    required String version,
  }) async {
    final fetch = await _http(
      Uri.parse('https://pub.dev/api/packages/$package'),
    );
    String? latest;
    final versions = <String>[];
    if (fetch.statusCode == 200) {
      try {
        final decoded = jsonDecode(fetch.body);
        if (decoded is Map) {
          final latestField = decoded['latest'];
          if (latestField is Map && latestField['version'] is String) {
            latest = latestField['version'] as String;
          }
          final versionsField = decoded['versions'];
          if (versionsField is List) {
            for (final entry in versionsField) {
              if (entry is Map && entry['version'] is String) {
                versions.add(entry['version'] as String);
              }
            }
          }
        }
      } on FormatException {
        latest = null; // a non-JSON body is "not resolvable yet", not a crash
        versions.clear();
      }
    }
    return PollResult(
      package: package,
      wanted: version,
      statusCode: fetch.statusCode,
      versions: List<String>.unmodifiable(versions),
      latest: latest,
      isPublished: versions.contains(version),
    );
  }

  /// CLASSIFIES a release: diffs the package's PUBLIC API at HEAD against the
  /// API of its LAST PUBLISHED version and pairs that delta with the version
  /// bump the pubspec declares.
  ///
  /// The baseline is the greatest version pub.dev lists — what a consumer
  /// resolves today — and never a golden file in the repo: a checked-in golden
  /// moves with the diff and can only tell you a symbol changed, which the
  /// diff already told you.
  ///
  /// The API extraction is NOT owned here. The semver rules are subtle
  /// (generics, optional parameters, sealed types, re-exports) and owning them
  /// wrong makes the gate lie in the safe-looking direction, so the delta comes
  /// from the external `dart-apitool` CLI, shelled out through the same
  /// [ProcessRunner] seam `dart pub publish` rides. `dart_apitool` is therefore
  /// NOT a dependency of this package, and replacing it is a one-seam change.
  ///
  /// The tool MUST be activated to run. When it cannot be launched this throws
  /// a LOUD [StateError] carrying the activation command — a gate that silently
  /// passes when its analyzer is missing is worse than no gate, so there is no
  /// path from a missing analyzer to a verdict. A missing baseline, a failing
  /// tool, a missing report and a malformed report are all the same kind of
  /// refusal.
  ///
  /// The seam ruling — shell out rather than depend on `package:dart_apitool`,
  /// and rather than owning the extraction in-house — is recorded as
  /// `release-classification-shells-out-to-dart-apitool`.
  Future<ReleaseClassification> classifyRelease({
    required String packageDir,
    required String package,
  }) async {
    final dir = p.normalize(p.absolute(packageDir));
    final pubspecFile = File(p.join(dir, 'pubspec.yaml'));
    final pubspec = _readPubspec(pubspecFile);
    final declared = _pubspecName(pubspec, pubspecFile.path);
    if (declared != package) {
      throw FormatException(
        '${pubspecFile.path} declares package "$declared", not "$package" — '
        'classify the package the directory actually holds.',
      );
    }
    final rawVersion = pubspec['version'];
    if (rawVersion is! String || rawVersion.isEmpty) {
      throw FormatException(
        '${pubspecFile.path} has no version — classification pairs the API '
        'delta with the version this release DECLARES.',
      );
    }
    final Version head;
    try {
      head = Version.parse(rawVersion);
    } on FormatException catch (error) {
      throw FormatException(
        '${pubspecFile.path} version "$rawVersion" is not a semantic version: '
        '${error.message}',
      );
    }

    final baseline = await _publishedBaseline(package: package, head: head);
    final leaves = await _apiDelta(
      package: package,
      baseline: baseline,
      packageDir: dir,
    );

    final removed = <String>[];
    final changed = <String>[];
    final added = <String>[];
    for (final leaf in leaves) {
      if (_apiRemovalCodes.contains(leaf.code)) {
        removed.add(leaf.entry);
      } else if (_apiAdditionCodes.contains(leaf.code)) {
        added.add(leaf.entry);
      } else {
        changed.add(leaf.entry);
      }
    }
    removed.sort();
    changed.sort();
    added.sort();

    final breaking = [
      for (final leaf in leaves)
        if (leaf.isBreaking) leaf,
    ]..sort((a, b) => a.entry.compareTo(b.entry));
    final requiredChange = breaking.isNotEmpty
        ? ReleaseRequiredChange.breaking
        : leaves.isEmpty
        ? ReleaseRequiredChange.none
        : ReleaseRequiredChange.additive;
    final declaredChange = _declaredChange(baseline: baseline, head: head);

    final String message;
    final ReleaseClassificationVerdict verdict;
    switch (requiredChange) {
      case ReleaseRequiredChange.none:
        verdict = ReleaseClassificationVerdict.ok;
        message =
            '$package: no public API change between $baseline and $head; '
            'declared $head is a ${declaredChange.label}.';
      case ReleaseRequiredChange.additive:
        verdict = ReleaseClassificationVerdict.ok;
        message =
            '$package: ${leaves.length} public API change(s) since $baseline, '
            'none breaking; declared $head is a ${declaredChange.label}, which '
            'covers an additive change.';
      case ReleaseRequiredChange.breaking:
        final rcFirst = _rcFirstFor(package: package, baseline: baseline);
        final understated = _core(head) < _core(rcFirst);
        verdict = understated
            ? ReleaseClassificationVerdict.understated
            : ReleaseClassificationVerdict.ok;
        message = understated
            ? _understatedMessage(
                package: package,
                leaf: breaking.first,
                head: head,
                declaredChange: declaredChange,
                rcFirst: rcFirst,
              )
            : '$package: ${leaves.length} public API change(s) since '
                  '$baseline, ${breaking.length} breaking; declared $head is a '
                  '${declaredChange.label} that reaches the required $rcFirst.';
    }

    return ReleaseClassification(
      package: package,
      baseline: baseline,
      head: head,
      removed: List<String>.unmodifiable(removed),
      changed: List<String>.unmodifiable(changed),
      added: List<String>.unmodifiable(added),
      requiredChange: requiredChange,
      declaredChange: declaredChange,
      verdict: verdict,
      message: message,
    );
  }

  /// Resolves the classification BASELINE: the greatest version pub.dev lists
  /// for [package], through the existing [poll] (so registry access stays on
  /// the one [HttpGetter] seam). A pre-release counts — it is what a consumer
  /// pinning `^X.Y.Z-rc.N` resolves. A package with nothing published, and a
  /// baseline that is not below [head], are both LOUD refusals: there is no
  /// safe fallback baseline to classify against.
  Future<Version> _publishedBaseline({
    required String package,
    required Version head,
  }) async {
    final probe = await poll(package: package, version: head.toString());
    if (probe.statusCode != 200) {
      throw StateError(
        'pub.dev answered ${probe.statusCode} for $package; the classification '
        'baseline is the LAST PUBLISHED release and this gate refuses to '
        'guess one.',
      );
    }
    final published = <Version>[];
    for (final raw in probe.versions) {
      try {
        published.add(Version.parse(raw));
      } on FormatException catch (error) {
        throw StateError(
          'pub.dev listed "$raw" for $package, which is not a semantic '
          'version: ${error.message}',
        );
      }
    }
    if (published.isEmpty) {
      throw StateError(
        '$package has no published version, so there is no baseline to '
        'classify the local API against.',
      );
    }
    published.sort();
    final baseline = published.last;
    if (baseline >= head) {
      throw StateError(
        'the greatest published version of $package is $baseline, which is not '
        'below the authored $head — author the version this release publishes '
        'before classifying it.',
      );
    }
    return baseline;
  }

  /// Runs `dart-apitool diff` over the [ProcessRunner] seam and parses its JSON
  /// report into flat leaves. The report goes to a temporary file (the tool
  /// prints progress on stdout, so stdout is not a parseable channel) that is
  /// deleted either way.
  Future<List<_ApiDeltaLeaf>> _apiDelta({
    required String package,
    required Version baseline,
    required String packageDir,
  }) async {
    final temp = Directory.systemTemp.createTempSync('release-classify-');
    try {
      final reportPath = p.join(temp.path, 'api-diff.json');
      final ProcessResult result;
      try {
        result = await _run(_apiTool, [
          'diff',
          '--old',
          'pub://$package/$baseline',
          '--new',
          packageDir,
          // The version check is dart-apitool's own opinion about the bump;
          // this gate forms its own verdict from the delta, so the tool is
          // asked for the DELTA only.
          '--version-check-mode=none',
          '--report-format=json',
          '--report-file-path',
          reportPath,
        ], workingDirectory: packageDir);
      } on ProcessException catch (error) {
        throw StateError(_apiToolUnavailable(error.message));
      }
      if (result.exitCode == _commandNotFound) {
        throw StateError(
          _apiToolUnavailable('exit $_commandNotFound (command not found)'),
        );
      }
      if (result.exitCode != 0) {
        throw StateError(
          '$_apiTool diff failed for $package against $baseline (exit '
                  '${result.exitCode}); this release is NOT classified.\n'
                  '${result.stderr}'
              .trimRight(),
        );
      }
      final reportFile = File(reportPath);
      if (!reportFile.existsSync()) {
        throw StateError(
          '$_apiTool exited 0 but wrote no report at $reportPath; this release '
          'is NOT classified.',
        );
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(reportFile.readAsStringSync());
      } on FormatException catch (error) {
        throw StateError(
          '$_apiTool wrote a report that is not JSON: ${error.message}',
        );
      }
      return _apiDeltaLeaves(decoded);
    } finally {
      temp.deleteSync(recursive: true);
    }
  }

  /// The LOUD "the gate has no analyzer" refusal. A gate that silently passes
  /// when its analyzer is missing is worse than no gate, so this is the only
  /// thing a missing [_apiTool] can produce — never a verdict.
  String _apiToolUnavailable(String detail) =>
      'the release classification gate could not run $_apiTool ($detail). It '
      'refuses to pass a release it did not analyze: activate the tool with '
      '`$_apiToolActivation` and re-run.';

  /// Flattens `report.breakingChanges` / `report.nonBreakingChanges` — each a
  /// tree of declaration nodes over change leaves — into one leaf list, each
  /// leaf carrying its enclosing declarations as a dotted symbol. The tool
  /// nests (`Class PollResult` > `Constructor new`), so the nearest label
  /// ALONE would render the useless `exported new lost parameter statusCode`;
  /// the qualified `PollResult.new` is the name a consumer actually writes. A
  /// leaf missing `changeCode`, `isBreaking` or `changeDescription` is a
  /// refusal, not a skipped entry.
  List<_ApiDeltaLeaf> _apiDeltaLeaves(Object? decoded) {
    if (decoded is! Map) {
      throw StateError('$_apiTool report must be a JSON object.');
    }
    final report = decoded.cast<Object?, Object?>()['report'];
    if (report is! Map) {
      throw StateError('$_apiTool report has no `report` object.');
    }
    final sections = report.cast<Object?, Object?>();
    final leaves = <_ApiDeltaLeaf>[];
    for (final key in const ['breakingChanges', 'nonBreakingChanges']) {
      final root = sections[key];
      if (root == null) continue;
      if (root is! Map) {
        throw StateError('$_apiTool report `$key` must be an object.');
      }
      final children = root.cast<Object?, Object?>()['children'];
      if (children is! List) {
        throw StateError('$_apiTool report `$key` must carry a children list.');
      }
      // The root's own label is the section banner ("BREAKING CHANGES"), never
      // a declaration — descend past it with no carried symbol.
      for (final child in children) {
        _collectApiDeltaLeaves(child, '', leaves);
      }
    }
    return leaves;
  }

  void _collectApiDeltaLeaves(
    Object? node,
    String symbol,
    List<_ApiDeltaLeaf> into,
  ) {
    if (node is! Map) {
      throw StateError('$_apiTool report nodes must be objects.');
    }
    final entry = node.cast<Object?, Object?>();
    final children = entry['children'];
    if (children != null) {
      if (children is! List) {
        throw StateError('$_apiTool report node children must be a list.');
      }
      final label = entry['label'];
      final declaration = label is String && label.isNotEmpty
          ? _declarationSymbol(label)
          : '';
      final nested = switch ((symbol.isEmpty, declaration.isEmpty)) {
        (_, true) => symbol,
        (true, false) => declaration,
        (false, false) => '$symbol.$declaration',
      };
      for (final child in children) {
        _collectApiDeltaLeaves(child, nested, into);
      }
      return;
    }
    final code = entry['changeCode'];
    final isBreaking = entry['isBreaking'];
    final description = entry['changeDescription'];
    if (code is! String || isBreaking is! bool || description is! String) {
      throw StateError(
        '$_apiTool report leaf is missing changeCode/isBreaking/'
        'changeDescription: ${jsonEncode(entry)}',
      );
    }
    into.add(
      _ApiDeltaLeaf(
        symbol: symbol,
        code: code,
        description: description,
        isBreaking: isBreaking,
      ),
    );
  }

  /// Strips the declaration-kind prefix `dart-apitool` puts on a node label
  /// (`Method captureScreenshot` -> `captureScreenshot`) so the message names
  /// the symbol a consumer writes. An unrecognized label passes through whole.
  String _declarationSymbol(String label) {
    for (final prefix in _declarationPrefixes) {
      if (label.startsWith(prefix)) return label.substring(prefix.length);
    }
    return label;
  }

  /// The bump [head] declares off [baseline] — read off the versions, so a
  /// commit that carries neither `!` nor a `BREAKING CHANGE:` footer still
  /// declares exactly what it authored.
  ReleaseDeclaredChange _declaredChange({
    required Version baseline,
    required Version head,
  }) {
    if (head.preRelease.isNotEmpty) return ReleaseDeclaredChange.prerelease;
    if (baseline.preRelease.isNotEmpty && _core(baseline) == _core(head)) {
      return ReleaseDeclaredChange.promotion;
    }
    if (head.major != baseline.major) return ReleaseDeclaredChange.major;
    if (head.minor != baseline.minor) return ReleaseDeclaredChange.minor;
    return ReleaseDeclaredChange.patch;
  }

  /// The rc-first version a breaking change off [baseline] requires — computed
  /// by the existing [planVersion], so classification never invents version
  /// math and stays on ADR-0003 D3's rc-first lane.
  Version _rcFirstFor({required String package, required Version baseline}) {
    try {
      return planVersion(
        current: baseline.toString(),
        change: ReleaseChange.rc,
      ).next;
    } on ArgumentError catch (error) {
      throw StateError(
        'the published baseline $baseline of $package cannot plan an rc-first '
        'breaking version (${error.message}), so the required version is not '
        'derivable and the delta is NOT classified.',
      );
    }
  }

  /// The core `major.minor.patch` of [version], pre-release suffix dropped —
  /// the comparison a bump-size question actually asks.
  Version _core(Version version) =>
      Version(version.major, version.minor, version.patch);

  /// The understated verdict's message. It names the SYMBOL and the
  /// CONSEQUENCE: a message that only says a thing changed is not worth a gate.
  String _understatedMessage({
    required String package,
    required _ApiDeltaLeaf leaf,
    required Version head,
    required ReleaseDeclaredChange declaredChange,
    required Version rcFirst,
  }) {
    final tail =
        'declared $head is a ${declaredChange.label}, a breaking change '
        'requires $rcFirst';
    final parameter = _removedParameter.firstMatch(leaf.description);
    if (leaf.code == 'CE01' && parameter != null && leaf.symbol.isNotEmpty) {
      final name = parameter.group(1)!;
      return '$package: exported ${leaf.symbol} lost parameter $name, so existing '
          'calls that supply $name no longer compile; $tail';
    }
    final subject = leaf.symbol.isEmpty
        ? 'the package API'
        : 'exported ${leaf.symbol}';
    return '$package: $subject changed — ${leaf.description} — so existing '
        'consumers may no longer compile; $tail';
  }

  /// Publishes a whole pub WORKSPACE in one wave: computes the changed-package
  /// set against pub.dev, runs every existing release gate, validates the
  /// consumers a direct stable wave owes, then cuts and pushes one tag per
  /// package in dependency order, waiting for each to propagate before the
  /// next dependent moves. THE TAG PUSH IS THE PUBLISH — tag-triggered
  /// trusted publishing does the upload — so this composes the existing ops
  /// and never runs `dart pub publish` for real.
  ///
  /// [change] is the operator's declared change class and it is load-bearing:
  ///
  /// - [ReleaseChange.breaking] is REFUSED before any filesystem, process or
  ///   network work. A breaking base goes rc-first and is promoted through the
  ///   separate `validate-consumers` then `promote` operations; the refusal
  ///   says so.
  /// - [ReleaseChange.rc] cuts pre-release tags and does NOT validate
  ///   consumers here: the candidate is cut FIRST, and the separate ops carry
  ///   its gate.
  /// - docs/additive/fix MAY tag directly (no rc soak) but are STILL
  ///   consumer-validated: [consumers] is required, every one is resolved
  ///   against the release commit (an origin-reachable SHA, which pub accepts
  ///   as a git `ref:` exactly as it accepts a tag) BEFORE the first tag, and
  ///   one failing consumer refuses the whole wave — a "non-breaking" change
  ///   that fails a consumer is breaking, and the refusal names the rc path it
  ///   drops to.
  ///
  /// Gates run to completion before ANY mutation, so a preflight stop leaves
  /// zero tags. Once the wave mutates, a stop leaves only what its own stage
  /// already did (a pushed tag whose propagation never landed, say) and every
  /// LATER package untagged and unpushed. Every stop is a [ReleaseWaveFailure]
  /// naming the stage and package.
  ///
  /// [dryRunOnly] runs the gates and the consumer validation and returns the
  /// ordered plan without cutting a tag, pushing, or polling; consumer
  /// override files are restored byte-for-byte either way.
  Future<ReleaseWavePlan> publishWorkspace({
    required String workspaceRoot,
    required ReleaseChange change,
    List<ReleaseConsumer> consumers = const [],
    bool dryRunOnly = false,
    Duration pollInterval = const Duration(seconds: 5),
    int maxPollAttempts = 120,
  }) async {
    if (change == ReleaseChange.breaking) {
      throw const ReleaseWaveFailure(
        stage: ReleaseWaveStage.plan,
        message:
            'a breaking wave is refused: a breaking change must go rc-first '
            'and pass every consumer before promotion. Cut candidates with '
            '`--change rc`, then run the separate `release validate-consumers` '
            'and `release promote` operations to promote the stable base.',
      );
    }
    if (maxPollAttempts < 1) {
      throw ArgumentError.value(
        maxPollAttempts,
        'maxPollAttempts',
        'must be at least one poll attempt',
      );
    }
    if (pollInterval.isNegative) {
      throw ArgumentError.value(
        pollInterval,
        'pollInterval',
        'must not be negative',
      );
    }

    final root = p.normalize(p.absolute(workspaceRoot));
    final members = _workspaceMembers(root);
    final changed = <_ChangedMember>[];
    for (final member in members) {
      final resolved = await _resolveChangedMember(member, change);
      if (resolved != null) changed.add(resolved);
    }
    if (changed.isEmpty) {
      return ReleaseWavePlan(
        workspaceRoot: root,
        change: change,
        dryRun: dryRunOnly,
        packages: const [],
      );
    }

    for (final member in changed) {
      await _runScrubGate(member);
    }

    final names = {for (final member in changed) member.name};
    final PublishOrder order;
    try {
      order = publishOrder({
        for (final member in changed)
          member.name: [
            for (final dependency in member.dependencies)
              if (names.contains(dependency) && dependency != member.name)
                dependency,
          ]..sort(),
      });
    } on StateError catch (error) {
      throw ReleaseWaveFailure(
        stage: ReleaseWaveStage.order,
        message: error.message,
      );
    }
    final byName = {for (final member in changed) member.name: member};
    final ordered = [
      for (final name in order.order)
        ReleaseWavePackage(
          package: name,
          directory: p.normalize(
            p.relative(byName[name]!.directory, from: root),
          ),
          publishedPredecessor: byName[name]!.predecessor,
          localVersion: byName[name]!.version,
          dependencies: List<String>.unmodifiable(
            [
              for (final dependency in byName[name]!.dependencies)
                if (names.contains(dependency) && dependency != name)
                  dependency,
            ]..sort(),
          ),
          tag: tagFor(package: name, version: byName[name]!.version.toString()),
        ),
    ];

    for (final package in ordered) {
      final result = await dryRun(
        packageDir: byName[package.package]!.directory,
        package: package.package,
      );
      if (!result.clean) {
        throw ReleaseWaveFailure(
          stage: ReleaseWaveStage.dryRun,
          package: package.package,
          message:
              'the publish dry-run gate failed for ${package.package} (exit '
              '${result.exitCode}, ${result.warningCount} warning(s))'
              '${result.warnings.isEmpty ? '' : '\n${result.warnings.join('\n')}'}',
        );
      }
    }

    if (!change.isBreaking) {
      await _validateStableWave(root: root, consumers: consumers);
    }

    final plan = ReleaseWavePlan(
      workspaceRoot: root,
      change: change,
      dryRun: dryRunOnly,
      packages: List<ReleaseWavePackage>.unmodifiable(ordered),
    );
    if (dryRunOnly) return plan;

    for (final package in ordered) {
      await _publishWavePackage(
        root: root,
        package: package,
        pollInterval: pollInterval,
        maxPollAttempts: maxPollAttempts,
      );
    }
    return plan;
  }

  /// Reads the workspace root's `pubspec.yaml` and yields every PUBLISHABLE
  /// member (`publish_to: none` is skipped — it never reaches pub.dev). An
  /// escaping or duplicated member path, a duplicated package name, a missing
  /// or malformed member pubspec, and a member without a semantic version are
  /// all LOUD workspace-stage refusals.
  List<_WorkspaceMember> _workspaceMembers(String root) {
    final rootPubspecFile = File(p.join(root, 'pubspec.yaml'));
    final Map<Object?, Object?> rootPubspec;
    try {
      rootPubspec = _readPubspec(rootPubspecFile);
    } on FileSystemException catch (error) {
      throw ReleaseWaveFailure(
        stage: ReleaseWaveStage.workspace,
        message: '${error.message}: ${error.path}',
      );
    } on FormatException catch (error) {
      throw ReleaseWaveFailure(
        stage: ReleaseWaveStage.workspace,
        message: error.message,
      );
    }
    final declared = rootPubspec['workspace'];
    if (declared is! List || declared.isEmpty) {
      throw ReleaseWaveFailure(
        stage: ReleaseWaveStage.workspace,
        message:
            '${rootPubspecFile.path} declares no pub workspace members — '
            '`--workspace` must point at a pub workspace root.',
      );
    }
    final members = <_WorkspaceMember>[];
    final seenPaths = <String>{};
    final seenNames = <String>{};
    for (final entry in declared) {
      if (entry is! String || entry.isEmpty) {
        throw ReleaseWaveFailure(
          stage: ReleaseWaveStage.workspace,
          message:
              '${rootPubspecFile.path} workspace entries must be non-empty '
              'strings; found "$entry".',
        );
      }
      final directory = p.normalize(p.join(root, entry));
      if (!p.isWithin(root, directory)) {
        throw ReleaseWaveFailure(
          stage: ReleaseWaveStage.workspace,
          message:
              'workspace member "$entry" resolves outside the workspace root '
              '($directory).',
        );
      }
      if (!seenPaths.add(directory)) {
        throw ReleaseWaveFailure(
          stage: ReleaseWaveStage.workspace,
          message: 'workspace member "$entry" is declared more than once.',
        );
      }
      final pubspecFile = File(p.join(directory, 'pubspec.yaml'));
      final Map<Object?, Object?> pubspec;
      final String name;
      try {
        pubspec = _readPubspec(pubspecFile);
        name = _pubspecName(pubspec, pubspecFile.path);
      } on FileSystemException catch (error) {
        throw ReleaseWaveFailure(
          stage: ReleaseWaveStage.workspace,
          message: '${error.message}: ${error.path}',
        );
      } on FormatException catch (error) {
        throw ReleaseWaveFailure(
          stage: ReleaseWaveStage.workspace,
          message: '${pubspecFile.path}: ${error.message}',
        );
      }
      if (!seenNames.add(name)) {
        throw ReleaseWaveFailure(
          stage: ReleaseWaveStage.workspace,
          message:
              'workspace package "$name" is declared by more than one member.',
        );
      }
      if (pubspec['publish_to'] == 'none') continue;
      final rawVersion = pubspec['version'];
      if (rawVersion is! String || rawVersion.isEmpty) {
        throw ReleaseWaveFailure(
          stage: ReleaseWaveStage.workspace,
          package: name,
          message:
              '${pubspecFile.path} has no version — a publishable member must '
              'author the version the wave publishes.',
        );
      }
      final Version version;
      try {
        version = Version.parse(rawVersion);
      } on FormatException catch (error) {
        throw ReleaseWaveFailure(
          stage: ReleaseWaveStage.workspace,
          package: name,
          message:
              '${pubspecFile.path} version "$rawVersion" is not a semantic '
              'version: ${error.message}',
        );
      }
      final List<String> dependencies;
      try {
        dependencies = _directDependencyNames(pubspec, pubspecFile.path);
      } on FormatException catch (error) {
        throw ReleaseWaveFailure(
          stage: ReleaseWaveStage.workspace,
          package: name,
          message: error.message,
        );
      }
      members.add(
        _WorkspaceMember(
          name: name,
          directory: directory,
          version: version,
          dependencies: dependencies,
        ),
      );
    }
    return members;
  }

  /// Decides whether [member] is IN the wave: unchanged (its authored version
  /// is already on pub.dev) yields null; otherwise the published predecessor
  /// its version bumps off — null for a first release — is resolved through
  /// the existing [planVersion], so the wave can never invent version math.
  Future<_ChangedMember?> _resolveChangedMember(
    _WorkspaceMember member,
    ReleaseChange change,
  ) async {
    final probe = await poll(
      package: member.name,
      version: member.version.toString(),
    );
    if (probe.statusCode == 404) {
      final isRcShaped =
          member.version.preRelease.length == 2 &&
          member.version.preRelease[0] == 'rc' &&
          member.version.preRelease[1] is int;
      if (change.isPreRelease && !isRcShaped) {
        throw ReleaseWaveFailure(
          stage: ReleaseWaveStage.discovery,
          package: member.name,
          message:
              'an rc wave publishes rc.N pre-releases, but the first release '
              'of ${member.name} is authored as ${member.version}.',
        );
      }
      if (!change.isPreRelease && member.version.preRelease.isNotEmpty) {
        throw ReleaseWaveFailure(
          stage: ReleaseWaveStage.discovery,
          package: member.name,
          message:
              'a ${change.name} wave publishes stable versions, but the first '
              'release of ${member.name} is authored as the pre-release '
              '${member.version}.',
        );
      }
      return _ChangedMember(member: member, predecessor: null);
    }
    if (probe.statusCode != 200) {
      throw ReleaseWaveFailure(
        stage: ReleaseWaveStage.discovery,
        package: member.name,
        message:
            'pub.dev answered ${probe.statusCode} for ${member.name}; refusing '
            'to read that as "not published yet".',
      );
    }
    if (probe.isPublished) return null;
    final published = <Version>[];
    for (final raw in probe.versions) {
      try {
        published.add(Version.parse(raw));
      } on FormatException catch (error) {
        throw ReleaseWaveFailure(
          stage: ReleaseWaveStage.discovery,
          package: member.name,
          message:
              'pub.dev listed "$raw" for ${member.name}, which is not a '
              'semantic version: ${error.message}',
        );
      }
    }
    published.sort((a, b) => b.compareTo(a));
    for (final candidate in published) {
      final ReleaseVersionPlan plan;
      try {
        plan = planVersion(current: candidate.toString(), change: change);
      } on ArgumentError {
        continue; // this published version cannot carry the change class
      }
      if (plan.next == member.version) {
        return _ChangedMember(member: member, predecessor: candidate);
      }
    }
    throw ReleaseWaveFailure(
      stage: ReleaseWaveStage.discovery,
      package: member.name,
      message:
          'no published version of ${member.name} reaches the authored '
          '${member.version} under `--change ${change.name}` — re-author the '
          'version or declare the change class the bump actually carries.',
    );
  }

  /// Runs the existing complete scrub gate (content scan + declared floors)
  /// for one wave member and refuses the wave unless it comes back clean.
  Future<void> _runScrubGate(_ChangedMember member) async {
    final ScrubResult result;
    try {
      result = await scrubPackage(member.directory);
    } on ReleaseWaveFailure {
      rethrow;
    } on Object catch (error) {
      throw ReleaseWaveFailure(
        stage: ReleaseWaveStage.scrub,
        package: member.name,
        message: '$error',
      );
    }
    if (result.clean) return;
    final floors = result.declaredFloors;
    throw ReleaseWaveFailure(
      stage: ReleaseWaveStage.scrub,
      package: member.name,
      message: [
        'the scrub gate failed for ${member.name}',
        if (result.hits.isNotEmpty)
          '${result.hits.length} internal ref(s): '
              '${result.hits.map((hit) => '${hit.file}:${hit.line}').join(', ')}',
        if (floors != null && !floors.passed) floors.message,
      ].join('\n'),
    );
  }

  /// The direct stable wave's consumer gate: resolve the origin-reachable
  /// release commit, validate every consumer against it, restore the consumer
  /// overrides, and refuse the wave — before any tag exists — when one fails.
  Future<void> _validateStableWave({
    required String root,
    required List<ReleaseConsumer> consumers,
  }) async {
    if (consumers.isEmpty) {
      throw const ReleaseWaveFailure(
        stage: ReleaseWaveStage.validateConsumers,
        message:
            'a docs/additive/fix wave may tag directly but is still '
            'consumer-validated: pass `--consumers <manifest.json>` naming '
            'every consumer this wave must not break.',
      );
    }
    final sha = await _releaseCommitSha(root);
    final snapshots = <({File file, List<int>? bytes})>[];
    for (final consumer in consumers) {
      final file = File(p.join(consumer.directory, 'pubspec_overrides.yaml'));
      snapshots.add((
        file: file,
        bytes: file.existsSync() ? file.readAsBytesSync() : null,
      ));
    }
    final ConsumerValidationReport report;
    try {
      report = await validateConsumers(rcTag: sha, consumers: consumers);
    } on StateError catch (error) {
      throw ReleaseWaveFailure(
        stage: ReleaseWaveStage.validateConsumers,
        message: error.message,
      );
    } finally {
      for (final snapshot in snapshots) {
        final bytes = snapshot.bytes;
        if (bytes == null) {
          if (snapshot.file.existsSync()) snapshot.file.deleteSync();
        } else {
          snapshot.file.writeAsBytesSync(bytes);
        }
      }
    }
    if (report.allPassed) return;
    final failed = report.results
        .where((result) => !result.passed)
        .map((result) => result.name)
        .join(', ');
    throw ReleaseWaveFailure(
      stage: ReleaseWaveStage.validateConsumers,
      message:
          'consumer validation failed at $sha for: $failed. A "non-breaking" '
          'change that fails a consumer is breaking — cut it as a candidate '
          'with `--change rc` instead.',
    );
  }

  /// The commit consumers resolve against: `HEAD`, refused unless it is
  /// reachable from an `origin/` ref (an unpushed commit is a git ref no
  /// consumer could ever fetch).
  Future<String> _releaseCommitSha(String root) async {
    final head = await _run('git', const [
      'rev-parse',
      'HEAD',
    ], workingDirectory: root);
    final sha = head.stdout.toString().trim();
    if (head.exitCode != 0 || sha.isEmpty) {
      throw ReleaseWaveFailure(
        stage: ReleaseWaveStage.releaseCommit,
        message:
            'git rev-parse HEAD failed in $root (exit ${head.exitCode}): '
            '${head.stderr}',
      );
    }
    final remotes = await _run('git', [
      'branch',
      '--remotes',
      '--contains',
      sha,
    ], workingDirectory: root);
    if (remotes.exitCode != 0) {
      throw ReleaseWaveFailure(
        stage: ReleaseWaveStage.releaseCommit,
        message:
            'git branch --remotes --contains $sha failed in $root (exit '
            '${remotes.exitCode}): ${remotes.stderr}',
      );
    }
    final reachable = [
      for (final line in const LineSplitter().convert(
        remotes.stdout.toString(),
      ))
        line.replaceFirst(RegExp(r'^[*\s]+'), '').trim(),
    ].where((ref) => ref.startsWith('origin/'));
    if (reachable.isEmpty) {
      throw ReleaseWaveFailure(
        stage: ReleaseWaveStage.releaseCommit,
        message:
            'the release commit $sha is not reachable from any origin/ ref — '
            'push it before releasing, so consumers can resolve the wave '
            'against it.',
      );
    }
    return sha;
  }

  /// Cuts, pushes and waits out ONE package. The push is the publish, so the
  /// propagation poll is the barrier the next dependent waits behind.
  Future<void> _publishWavePackage({
    required String root,
    required ReleaseWavePackage package,
    required Duration pollInterval,
    required int maxPollAttempts,
  }) async {
    final tagged = await createGitTag(repoDir: root, tag: package.tag);
    if (!tagged.created) {
      throw ReleaseWaveFailure(
        stage: ReleaseWaveStage.tag,
        package: package.package,
        message:
            'git tag ${package.tag} failed (exit ${tagged.exitCode}): '
            '${tagged.stderr}',
      );
    }
    final pushed = await _run('git', [
      'push',
      'origin',
      package.tag,
    ], workingDirectory: root);
    if (pushed.exitCode != 0) {
      throw ReleaseWaveFailure(
        stage: ReleaseWaveStage.push,
        package: package.package,
        message:
            'git push origin ${package.tag} failed (exit ${pushed.exitCode}): '
            '${pushed.stderr}',
      );
    }
    for (var attempt = 1; attempt <= maxPollAttempts; attempt++) {
      final probe = await poll(
        package: package.package,
        version: package.localVersion.toString(),
      );
      if (probe.isPublished) return;
      if (attempt < maxPollAttempts) await _wait(pollInterval);
    }
    throw ReleaseWaveFailure(
      stage: ReleaseWaveStage.poll,
      package: package.package,
      message:
          '${package.package} ${package.localVersion} did not appear on '
          'pub.dev after $maxPollAttempts poll(s); every later package in the '
          'wave is left untagged and unpushed.',
    );
  }
}

/// One publishable pub-workspace member, as authored on disk.
/// One flattened change from a `dart-apitool` JSON report: the nearest
/// enclosing declaration, the change code, its description and whether the
/// tool judged it breaking.
class _ApiDeltaLeaf {
  const _ApiDeltaLeaf({
    required this.symbol,
    required this.code,
    required this.description,
    required this.isBreaking,
  });

  final String symbol;
  final String code;
  final String description;
  final bool isBreaking;

  /// The rendered delta entry. A change with no enclosing declaration (a
  /// package-level entry point or dependency move) reads as its description.
  String get entry => symbol.isEmpty ? description : '$symbol: $description';
}

class _WorkspaceMember {
  const _WorkspaceMember({
    required this.name,
    required this.directory,
    required this.version,
    required this.dependencies,
  });

  final String name;
  final String directory;
  final Version version;
  final List<String> dependencies;
}

/// A member the wave publishes, plus the published version it moves off.
class _ChangedMember {
  const _ChangedMember({required this.member, required this.predecessor});

  final _WorkspaceMember member;
  final Version? predecessor;

  String get name => member.name;
  String get directory => member.directory;
  Version get version => member.version;
  List<String> get dependencies => member.dependencies;
}

/// Entries a throwaway candidate copy must NOT carry: workspace-resolved
/// caches, the repo's own lock, the machine-local generated overrides, and
/// build output. Everything else is copied so analysis sees the real sources.
///
/// `analysis_options.yaml` is excluded too, because the house one `include:`s a
/// repo-root file by relative path — outside the checkout that resolves to
/// nothing and analysis reports `include_file_not_found`, failing every
/// candidate for a reason that has nothing to do with its floors. The leg's
/// invariant is narrow on purpose: does the candidate COMPILE against the
/// minimums it declares. Repo lint conformance is the workspace-green gate's
/// job, and it runs against the real tree where the include resolves.
const Set<String> _throwawayExclusions = {
  '.dart_tool',
  '.git',
  'analysis_options.yaml',
  'build',
  'pubspec.lock',
  'pubspec_overrides.yaml',
};

Map<Object?, Object?> _readPubspec(File file) {
  if (!file.existsSync()) {
    throw FileSystemException('Missing pubspec.yaml', file.path);
  }
  final Object? decoded = loadYaml(file.readAsStringSync());
  if (decoded is! Map) {
    throw FormatException('${file.path} must contain a YAML map');
  }
  return decoded.cast<Object?, Object?>();
}

String _pubspecName(Map<Object?, Object?> pubspec, String path) {
  final name = pubspec['name'];
  if (name is! String || name.isEmpty) {
    throw FormatException('$path requires a non-empty package name');
  }
  PubLink.fromJson(<String, Object?>{'package': name});
  return name;
}

/// Walks up from [candidateDir] for the pub workspace root that LISTS it, and
/// yields every member's package name. No workspace -> an empty set (a
/// standalone package has no siblings to pin).
Set<String> _workspacePackageNames(Directory candidateDir) {
  var cursor = candidateDir;
  final candidatePath = p.normalize(candidateDir.absolute.path);
  while (true) {
    final rootPubspecFile = File(p.join(cursor.path, 'pubspec.yaml'));
    if (rootPubspecFile.existsSync()) {
      final rootPubspec = _readPubspec(rootPubspecFile);
      final workspace = rootPubspec['workspace'];
      if (workspace is List) {
        final members = <Directory>[];
        for (final value in workspace) {
          if (value is! String) {
            throw FormatException(
              '${rootPubspecFile.path} workspace entries must be strings',
            );
          }
          members.add(Directory(p.normalize(p.join(cursor.path, value))));
        }
        if (members.any(
          (member) => p.normalize(member.absolute.path) == candidatePath,
        )) {
          return {
            for (final member in members)
              _pubspecName(
                _readPubspec(File(p.join(member.path, 'pubspec.yaml'))),
                p.join(member.path, 'pubspec.yaml'),
              ),
          };
        }
      }
    }
    final parent = cursor.parent;
    if (parent.path == cursor.path) return const <String>{};
    cursor = parent;
  }
}

/// The names in a pubspec's top-level `dependencies` map — the only edges a
/// release wave orders by (`dev_dependencies` are not part of the published
/// runtime contract, exactly as in [_declaredFloorPins]).
List<String> _directDependencyNames(
  Map<Object?, Object?> pubspec,
  String pubspecPath,
) {
  final declared = pubspec['dependencies'];
  if (declared == null) return const <String>[];
  if (declared is! Map) {
    throw FormatException('$pubspecPath dependencies must be a map');
  }
  final names = <String>[];
  for (final key in declared.keys) {
    if (key is! String) {
      throw FormatException('$pubspecPath dependency names must be strings');
    }
    names.add(key);
  }
  names.sort();
  return List<String>.unmodifiable(names);
}

List<DeclaredFloorPin> _declaredFloorPins(
  Map<Object?, Object?> pubspec, {
  required Set<String> workspacePackageNames,
  required String pubspecPath,
}) {
  final rawDependencies = pubspec['dependencies'];
  if (rawDependencies == null) return const <DeclaredFloorPin>[];
  if (rawDependencies is! Map) {
    throw FormatException('$pubspecPath dependencies must be a map');
  }
  final pins = <DeclaredFloorPin>[];
  for (final entry in rawDependencies.entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException('$pubspecPath dependency names must be strings');
    }
    if (!workspacePackageNames.contains(key)) continue;
    final rawConstraint = entry.value;
    if (rawConstraint is! String) {
      throw StateError(
        'workspace sibling "$key" declares a non-hosted dependency in '
        '$pubspecPath; an exact declared floor cannot be derived',
      );
    }
    final VersionConstraint constraint;
    try {
      constraint = VersionConstraint.parse(rawConstraint);
    } on FormatException catch (error) {
      throw StateError(
        'workspace sibling "$key" has malformed declared constraint '
        '"$rawConstraint": $error',
      );
    }
    final floor = switch (constraint) {
      VersionRange(min: final min, includeMin: true) => min,
      _ => null,
    };
    if (floor == null) {
      throw StateError(
        'workspace sibling "$key" constraint "$rawConstraint" has no '
        'inclusive declared floor to exact-pin',
      );
    }
    pins.add(
      DeclaredFloorPin(
        package: key,
        declaredConstraint: rawConstraint,
        floor: floor.toString(),
      ),
    );
  }
  pins.sort((a, b) => a.package.compareTo(b.package));
  return pins;
}

void _copyPackage(Directory source, Directory target) {
  target.createSync(recursive: true);
  for (final entity in source.listSync(followLinks: false)) {
    final name = p.basename(entity.path);
    if (_throwawayExclusions.contains(name)) continue;
    final destination = p.join(target.path, name);
    if (entity is File) {
      entity.copySync(destination);
    } else if (entity is Directory) {
      _copyPackage(entity, Directory(destination));
    } else if (entity is Link) {
      Link(destination).createSync(entity.targetSync());
    } else {
      throw StateError('unsupported package entry: ${entity.path}');
    }
  }
}

/// Strips `resolution: workspace` so the copy resolves STANDALONE — the whole
/// point of the leg is to stop siblings resolving by path.
void _removeWorkspaceResolution(File pubspec) {
  final standalone = const LineSplitter()
      .convert(pubspec.readAsStringSync())
      .where(
        (line) =>
            !RegExp(r'^resolution:\s*workspace\s*(?:#.*)?$').hasMatch(line),
      )
      .join('\n');
  pubspec.writeAsStringSync('$standalone\n');
}

List<String> _hiddenOverlaySourceWarnings(String packageDir) {
  final root = Directory(p.join(packageDir, 'extension', 'station_overlay'));
  if (!root.existsSync()) return const [];
  final paths = [
    for (final entity in root.listSync(recursive: true).whereType<Directory>())
      if (p.basename(entity.path).startsWith('.'))
        p.relative(entity.path, from: root.path),
  ]..sort();
  return [
    for (final path in paths)
      '* WARNING: hidden overlay source directory "$path" will be omitted by '
          'dart pub publish',
  ];
}
