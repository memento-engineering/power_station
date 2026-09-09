/// The DART domain's exported RELEASE Command — the deterministic half of the
/// coupled `release` skill+command (ADR-0001). `dart release <op>` is a
/// SUBcommand group of [DartCommand]; each op is a thin adapter over
/// [ReleaseService] that emits a structured JSON result under `--json` (the
/// surface the operator `release` skill parses — it never scrapes prose).
///
/// THIN by rule (the CLI-SDK redline): all logic lives in [ReleaseService];
/// these Commands only parse argv and render.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import 'release_service.dart';

/// `dart release` — the release-op group (subcommands carry the verbs).
class ReleaseCommand extends Command<int> {
  /// Creates the group over [service] (injectable for tests). [out]/[err]
  /// default to the real stdout/stderr; tests capture them.
  ReleaseCommand({
    ReleaseService service = const ReleaseService(),
    StringSink? out,
    StringSink? err,
  }) {
    final o = out ?? stdout;
    final e = err ?? stderr;
    addSubcommand(ReleaseDiscoverCommand(service: service, out: o, err: e));
    addSubcommand(ReleasePlanCommand(service: service, out: o, err: e));
    addSubcommand(ReleaseTagCommand(service: service, out: o));
    addSubcommand(
      ReleaseValidateConsumersCommand(service: service, out: o, err: e),
    );
    addSubcommand(ReleasePromoteCommand(service: service, out: o, err: e));
    addSubcommand(ReleaseScrubCommand(service: service, out: o, err: e));
    addSubcommand(ReleaseClassifyCommand(service: service, out: o, err: e));
    addSubcommand(ReleaseOrderCommand(service: service, out: o, err: e));
    addSubcommand(ReleaseDryRunCommand(service: service, out: o, err: e));
    addSubcommand(ReleasePollCommand(service: service, out: o));
    addSubcommand(ReleasePublishCommand(service: service, out: o, err: e));
  }

  @override
  final String name = 'release';

  @override
  final String description =
      'Deterministic Dart-package release ops (the machine substrate under the '
      'operator `release` skill): workspace discovery, version plan, scrub '
      'gate, semver classification, publish order, dry-run, pub.dev poll, and '
      'the one-command workspace wave — each a structured JSON result.';
}

/// Decodes the shared `{consumers: [{name, directory, links}]}` manifest both
/// consumer-validating ops take. A malformed file throws — the caller renders
/// it as a usage error.
List<ReleaseConsumer> _consumersFromManifest(File file) {
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return [
    for (final entry in decoded['consumers'] as List)
      ReleaseConsumer.fromJson((entry as Map).cast<String, Object?>()),
  ];
}

/// `dart release discover` — ask melos what the workspace needs to release.
class ReleaseDiscoverCommand extends Command<int> {
  /// Creates the op over [service], rendering to [out]/[err].
  ReleaseDiscoverCommand({
    required ReleaseService service,
    required StringSink out,
    required StringSink err,
  }) : _service = service,
       _out = out,
       _err = err {
    argParser
      ..addOption(
        'workspace',
        mandatory: true,
        help: 'The pub workspace root to survey.',
      )
      ..addOption(
        'diff',
        mandatory: true,
        help:
            'The git ref HEAD is compared against for the changed-package '
            'query (a ref, or a `<start>..<end>` range).',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the structured result as one JSON object.',
      );
  }

  final ReleaseService _service;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'discover';
  @override
  final String description =
      'Survey a pub workspace with melos: which members are unpublished, and '
      'which changed since a ref.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final ReleaseDiscovery discovery;
    try {
      discovery = await _service.discoverWorkspace(
        workspaceRoot: args.option('workspace')!,
        diff: args.option('diff')!,
      );
    } on ReleaseWaveFailure catch (failure) {
      _err.writeln('release discover: $failure');
      return 1;
    } on StateError catch (error) {
      // melos refused or answered something that is not a package list. A
      // survey that reports an empty candidate set it never read is worse
      // than no survey, so nothing reaches stdout.
      _err.writeln('release discover: ${error.message}');
      return 1;
    }
    if (args.flag('json')) {
      _out.writeln(jsonEncode(discovery.toJson()));
    } else {
      for (final candidate in discovery.candidates) {
        _out.writeln(candidate);
      }
    }
    return 0;
  }
}

/// `dart release plan` — compute the next version + git tag for a change class.
class ReleasePlanCommand extends Command<int> {
  /// Creates the op over [service], rendering to [out]/[err].
  ReleasePlanCommand({
    required ReleaseService service,
    required StringSink out,
    required StringSink err,
  }) : _service = service,
       _out = out,
       _err = err {
    argParser
      ..addOption(
        'package',
        mandatory: true,
        help: 'The pub package name (composes the tag).',
      )
      ..addOption(
        'current',
        mandatory: true,
        help: 'The current published version (semver).',
      )
      ..addOption(
        'change',
        mandatory: true,
        allowed: ['docs', 'additive', 'fix', 'breaking', 'rc'],
        help:
            'docs/additive/fix -> PATCH; breaking -> MINOR pre-1.0 / MAJOR '
            'from 1.0; rc -> next breaking base as rc.N.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the structured result as one JSON object.',
      );
  }

  final ReleaseService _service;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'plan';
  @override
  final String description =
      'Compute the next version + git tag for a change class.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final change = ReleaseChange.parse(args.option('change'));
    if (change == null) {
      _err.writeln('release plan: unknown --change');
      return 64;
    }
    final ReleaseVersionPlan plan;
    try {
      plan = _service.planVersion(
        current: args.option('current')!,
        change: change,
      );
    } on ArgumentError catch (e) {
      _err.writeln('release plan: ${e.message}');
      return 64;
    }
    final package = args.option('package')!;
    final tag = _service.tagFor(
      package: package,
      version: plan.next.toString(),
    );
    final json = {...plan.toJson(), 'package': package, 'tag': tag};
    if (args.flag('json')) {
      _out.writeln(jsonEncode(json));
    } else {
      _out.writeln('${plan.current} -> ${plan.next}  tag: $tag');
    }
    return 0;
  }
}

/// `dart release tag` — cut a private git release tag.
class ReleaseTagCommand extends Command<int> {
  /// Creates the op over [service], rendering to [out].
  ReleaseTagCommand({required ReleaseService service, required StringSink out})
    : _service = service,
      _out = out {
    argParser
      ..addOption('repo-dir', mandatory: true, help: 'The git repository dir.')
      ..addOption('tag', mandatory: true, help: 'The release tag to create.')
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the structured result as one JSON object.',
      );
  }

  final ReleaseService _service;
  final StringSink _out;

  @override
  final String name = 'tag';
  @override
  final String description = 'Cut a private git release tag.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final result = await _service.createGitTag(
      repoDir: args.option('repo-dir')!,
      tag: args.option('tag')!,
    );
    if (args.flag('json')) {
      _out.writeln(jsonEncode(result.toJson()));
    } else {
      _out.writeln(
        result.created
            ? 'tag created: ${result.tag}'
            : 'tag failed: ${result.tag}',
      );
    }
    return result.exitCode;
  }
}

/// `dart release validate-consumers` — validate consumers against an rc tag.
class ReleaseValidateConsumersCommand extends Command<int> {
  /// Creates the op over [service], rendering to [out]/[err].
  ReleaseValidateConsumersCommand({
    required ReleaseService service,
    required StringSink out,
    required StringSink err,
  }) : _service = service,
       _out = out,
       _err = err {
    argParser
      ..addOption('rc-tag', mandatory: true, help: 'The candidate rc tag.')
      ..addOption(
        'manifest',
        mandatory: true,
        help: 'JSON manifest containing a consumers list.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the structured result as one JSON object.',
      );
  }

  final ReleaseService _service;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'validate-consumers';
  @override
  final String description =
      'Resolve every consumer against an rc tag and run analyze/test.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final file = File(args.option('manifest')!);
    if (!file.existsSync()) {
      _err.writeln(
        'release validate-consumers: no such manifest: ${file.path}',
      );
      return 64;
    }
    final List<ReleaseConsumer> consumers;
    try {
      consumers = _consumersFromManifest(file);
    } on Object catch (e) {
      _err.writeln('release validate-consumers: invalid manifest: $e');
      return 64;
    }
    try {
      final report = await _service.validateConsumers(
        rcTag: args.option('rc-tag')!,
        consumers: consumers,
      );
      if (args.flag('json')) {
        _out.writeln(jsonEncode(report.toJson()));
      } else {
        _out.writeln(
          report.allPassed
              ? 'all consumers passed'
              : 'consumer validation failed',
        );
      }
      return report.allPassed ? 0 : 1;
    } on StateError catch (e) {
      _err.writeln('release validate-consumers: ${e.message}');
      return 1;
    }
  }
}

/// `dart release promote` — cut the stable tag after green consumer validation.
class ReleasePromoteCommand extends Command<int> {
  /// Creates the op over [service], rendering to [out]/[err].
  ReleasePromoteCommand({
    required ReleaseService service,
    required StringSink out,
    required StringSink err,
  }) : _service = service,
       _out = out,
       _err = err {
    argParser
      ..addOption('repo-dir', mandatory: true, help: 'The git repository dir.')
      ..addOption(
        'stable-tag',
        mandatory: true,
        help: 'The stable release tag to create.',
      )
      ..addOption(
        'validation',
        mandatory: true,
        help: 'A JSON validation report emitted by validate-consumers.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the structured result as one JSON object.',
      );
  }

  final ReleaseService _service;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'promote';
  @override
  final String description =
      'Cut the stable git tag only after all consumers passed.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final file = File(args.option('validation')!);
    if (!file.existsSync()) {
      _err.writeln('release promote: no such validation file: ${file.path}');
      return 64;
    }
    try {
      final validation = ConsumerValidationReport.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
      );
      final result = await _service.promoteTag(
        repoDir: args.option('repo-dir')!,
        stableTag: args.option('stable-tag')!,
        validation: validation,
      );
      if (args.flag('json')) {
        _out.writeln(jsonEncode(result.toJson()));
      } else {
        _out.writeln(
          result.created
              ? 'stable tag created: ${result.tag}'
              : 'stable tag failed: ${result.tag}',
        );
      }
      return result.exitCode;
    } on StateError catch (e) {
      _err.writeln('release promote: ${e.message}');
      return 1;
    } on Object catch (e) {
      _err.writeln('release promote: invalid validation report: $e');
      return 64;
    }
  }
}

/// `dart release scrub` — scan a package dir's publish-visible text for
/// internal references (genesis `publishing.md` scrub gate).
class ReleaseScrubCommand extends Command<int> {
  /// Creates the op over [service], rendering to [out]/[err].
  ReleaseScrubCommand({
    required ReleaseService service,
    required StringSink out,
    required StringSink err,
  }) : _service = service,
       _out = out,
       _err = err {
    argParser
      ..addOption('dir', mandatory: true, help: 'The package dir to scrub.')
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the structured result as one JSON object.',
      );
  }

  final ReleaseService _service;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'scrub';
  @override
  final String description =
      'Scan README/CHANGELOG/lib/example for internal refs and analyze the '
      'candidate at its declared sibling floors (the scrub gate).';

  @override
  Future<int> run() async {
    final args = argResults!;
    final dir = args.option('dir')!;
    if (!Directory(dir).existsSync()) {
      _err.writeln('release scrub: no such dir: $dir');
      return 64;
    }
    final ScrubResult result;
    try {
      result = await _service.scrubPackage(dir);
    } on FileSystemException catch (error) {
      _err.writeln('release scrub: ${error.message}: ${error.path}');
      return 64;
    } on FormatException catch (error) {
      _err.writeln('release scrub: ${error.message}');
      return 64;
    } on StateError catch (error) {
      _err.writeln('release scrub: ${error.message}');
      return 1;
    }
    if (args.flag('json')) {
      _out.writeln(jsonEncode(result.toJson()));
    } else if (result.clean) {
      _out.writeln(
        'scrub clean (${result.filesScanned} files; declared floors pass)',
      );
    } else {
      if (result.hits.isNotEmpty) {
        _out.writeln('scrub found ${result.hits.length} internal ref(s)');
      }
      final floors = result.declaredFloors;
      if (floors != null && !floors.passed) {
        _out.writeln(floors.message);
      }
    }
    return result.clean ? 0 : 1;
  }
}

/// `dart release classify` — the SEMVER verdict: compare the package's public
/// API at HEAD against the API of its LAST PUBLISHED version and pair that
/// delta with the version bump this release declares.
///
/// The other ops each check one thing in isolation: `plan` takes the change
/// class as an INPUT, `scrub` checks declared floors, `dry-run` checks
/// packaging. None of them CLASSIFIES, so a breaking change mis-declared as a
/// patch passes every gate. This op is the pairing they lack.
class ReleaseClassifyCommand extends Command<int> {
  /// Creates the op over [service], rendering to [out]/[err].
  ReleaseClassifyCommand({
    required ReleaseService service,
    required StringSink out,
    required StringSink err,
  }) : _service = service,
       _out = out,
       _err = err {
    argParser
      ..addOption(
        'dir',
        mandatory: true,
        help:
            'The package dir to classify — its pubspec authors the HEAD '
            'version the verdict is measured against.',
      )
      ..addOption(
        'package',
        mandatory: true,
        help:
            'The pub package name; it must match the directory\'s pubspec and '
            'names the pub.dev listing the baseline comes from.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the structured result as one JSON object.',
      );
  }

  final ReleaseService _service;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'classify';
  @override
  final String description =
      'Diff the public API against the last published release and pair it '
      'with the declared version bump (the semver verdict).';

  @override
  Future<int> run() async {
    final args = argResults!;
    final dir = args.option('dir')!;
    if (!Directory(dir).existsSync()) {
      _err.writeln('release classify: no such dir: $dir');
      return 64;
    }
    final ReleaseClassification result;
    try {
      result = await _service.classifyRelease(
        packageDir: dir,
        package: args.option('package')!,
      );
    } on StateError catch (error) {
      // The baseline, the analyzer or its report was unavailable. There is NO
      // verdict on stdout: a gate that passes without its analyzer is worse
      // than no gate.
      _err.writeln('release classify: ${error.message}');
      return 1;
    } on FileSystemException catch (error) {
      _err.writeln('release classify: ${error.message}: ${error.path}');
      return 64;
    } on FormatException catch (error) {
      _err.writeln('release classify: ${error.message}');
      return 64;
    }
    if (args.flag('json')) {
      _out.writeln(jsonEncode(result.toJson()));
    } else {
      _out.writeln(result.message);
    }
    return switch (result.verdict) {
      ReleaseClassificationVerdict.ok => 0,
      ReleaseClassificationVerdict.understated => 1,
    };
  }
}

/// `dart release order` — resolve the dependency-order publish sequence.
class ReleaseOrderCommand extends Command<int> {
  /// Creates the op over [service], rendering to [out]/[err].
  ReleaseOrderCommand({
    required ReleaseService service,
    required StringSink out,
    required StringSink err,
  }) : _service = service,
       _out = out,
       _err = err {
    argParser
      ..addOption(
        'manifest',
        help:
            'A JSON file mapping package -> [in-set deps] — the hand-written '
            'input, kept for compatibility.',
      )
      ..addOption(
        'workspace',
        help:
            'A pub workspace root to read the graph from, via melos. Exactly '
            'one of --workspace and --manifest is required.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the structured result as one JSON object.',
      );
  }

  final ReleaseService _service;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'order';
  @override
  final String description =
      'Resolve the dependency-order publish sequence — from a melos workspace '
      'graph (--workspace) or a deps manifest (--manifest).';

  @override
  Future<int> run() async {
    final args = argResults!;
    final manifestPath = args.option('manifest');
    final workspacePath = args.option('workspace');
    if ((manifestPath == null) == (workspacePath == null)) {
      // Two graphs are two answers; no graph is none. Either way there is
      // nothing to order, and guessing which input won is exactly the
      // transcription risk the workspace mode exists to remove.
      _err.writeln(
        'release order: pass exactly one of --workspace <dir> or --manifest '
        '<deps.json>.',
      );
      return 64;
    }
    final PublishOrder order;
    if (workspacePath != null) {
      try {
        order = await _service.publishOrderFromMelosWorkspace(
          workspaceRoot: workspacePath,
        );
      } on ReleaseWaveFailure catch (failure) {
        _err.writeln('release order: $failure');
        return 1;
      } on StateError catch (e) {
        _err.writeln('release order: ${e.message}');
        return 1;
      }
    } else {
      final file = File(manifestPath!);
      if (!file.existsSync()) {
        _err.writeln('release order: no such manifest: ${file.path}');
        return 64;
      }
      final Map<String, List<String>> deps;
      try {
        final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        deps = {
          for (final entry in raw.entries)
            entry.key: [for (final d in entry.value as List) d as String],
        };
      } on Object catch (e) {
        _err.writeln(
          'release order: manifest is not a {package: [deps]} object: $e',
        );
        return 64;
      }
      try {
        order = _service.publishOrder(deps);
      } on StateError catch (e) {
        _err.writeln('release order: ${e.message}');
        return 1;
      }
    }
    if (args.flag('json')) {
      _out.writeln(jsonEncode(order.toJson()));
    } else {
      _out.writeln(order.order.join(' -> '));
    }
    return 0;
  }
}

/// `dart release dry-run` — run `dart pub publish --dry-run` and parse the gate.
class ReleaseDryRunCommand extends Command<int> {
  /// Creates the op over [service], rendering to [out]/[err].
  ReleaseDryRunCommand({
    required ReleaseService service,
    required StringSink out,
    required StringSink err,
  }) : _service = service,
       _out = out,
       _err = err {
    argParser
      ..addOption('dir', mandatory: true, help: 'The package dir to dry-run.')
      ..addOption(
        'package',
        help: 'The package name (informational, echoed in the result).',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the structured result as one JSON object.',
      );
  }

  final ReleaseService _service;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'dry-run';
  @override
  final String description =
      'Run `dart pub publish --dry-run` and parse the 0-warnings gate.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final dir = args.option('dir')!;
    if (!Directory(dir).existsSync()) {
      _err.writeln('release dry-run: no such dir: $dir');
      return 64;
    }
    final result = await _service.dryRun(
      packageDir: dir,
      package: args.option('package') ?? '',
    );
    if (args.flag('json')) {
      _out.writeln(jsonEncode(result.toJson()));
    } else {
      _out.writeln(
        result.clean
            ? 'dry-run clean'
            : 'dry-run: ${result.warningCount} warning(s), exit '
                  '${result.exitCode}',
      );
    }
    return 0;
  }
}

/// `dart release poll` — poll pub.dev for whether a version is published.
class ReleasePollCommand extends Command<int> {
  /// Creates the op over [service], rendering to [out] (poll has no error
  /// path — the mandatory options are enforced by the arg parser).
  ReleasePollCommand({required ReleaseService service, required StringSink out})
    : _service = service,
      _out = out {
    argParser
      ..addOption('package', mandatory: true, help: 'The pub package name.')
      ..addOption('version', mandatory: true, help: 'The version to wait for.')
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the structured result as one JSON object.',
      );
  }

  final ReleaseService _service;
  final StringSink _out;

  @override
  final String name = 'poll';
  @override
  final String description =
      'Poll pub.dev once — is <version> published for <package> yet?';

  @override
  Future<int> run() async {
    final args = argResults!;
    final result = await _service.poll(
      package: args.option('package')!,
      version: args.option('version')!,
    );
    if (args.flag('json')) {
      _out.writeln(jsonEncode(result.toJson()));
    } else {
      final latest = result.latest ?? 'unresolved';
      _out.writeln(
        result.isPublished
            ? '${result.package} ${result.wanted} is published'
            : '${result.package} ${result.wanted} is not published yet '
                  '(latest stable: $latest)',
      );
    }
    return 0;
  }
}

/// `dart release publish` — the ONE-COMMAND workspace wave: compute the
/// changed-package set against pub.dev, run every gate, validate the consumers
/// a direct stable wave owes, then cut and push one tag per package in
/// dependency order, waiting for each to propagate (the tag push IS the
/// publish — tag-triggered trusted publishing does the upload).
class ReleasePublishCommand extends Command<int> {
  /// Creates the op over [service], rendering to [out]/[err].
  ReleasePublishCommand({
    required ReleaseService service,
    required StringSink out,
    required StringSink err,
  }) : _service = service,
       _out = out,
       _err = err {
    argParser
      ..addOption(
        'workspace',
        mandatory: true,
        help: 'The pub workspace root to release from.',
      )
      ..addOption(
        'change',
        mandatory: true,
        allowed: ['docs', 'additive', 'fix', 'breaking', 'rc'],
        help:
            'The wave\'s change class. docs/additive/fix tag directly but are '
            'still consumer-validated; rc cuts candidates only; breaking is '
            'refused (it goes rc-first, then promote).',
      )
      ..addOption(
        'consumers',
        help:
            'JSON manifest containing a consumers list — REQUIRED for a '
            'docs/additive/fix wave, unused by rc.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Run every gate and stop: no tag, no push, no poll.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the structured result as one JSON object.',
      );
  }

  final ReleaseService _service;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'publish';
  @override
  final String description =
      'Release a whole pub workspace in one wave: changed set, gates, consumer '
      'validation, then dependency-ordered tag pushes with propagation polls.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final change = ReleaseChange.parse(args.option('change'));
    if (change == null) {
      _err.writeln('release publish: unknown --change');
      return 64;
    }
    final manifestPath = args.option('consumers');
    var consumers = const <ReleaseConsumer>[];
    if (manifestPath == null) {
      if (!change.isBreaking) {
        _err.writeln(
          'release publish: --consumers <manifest.json> is required for a '
          '${change.name} wave (it tags directly, so it is validated first).',
        );
        return 64;
      }
    } else {
      final file = File(manifestPath);
      if (!file.existsSync()) {
        _err.writeln('release publish: no such manifest: ${file.path}');
        return 64;
      }
      try {
        consumers = _consumersFromManifest(file);
      } on Object catch (e) {
        _err.writeln('release publish: invalid manifest: $e');
        return 64;
      }
    }
    final json = args.flag('json');
    try {
      final plan = await _service.publishWorkspace(
        workspaceRoot: args.option('workspace')!,
        change: change,
        consumers: consumers,
        dryRunOnly: args.flag('dry-run'),
      );
      if (json) {
        _out.writeln(jsonEncode(plan.toJson()));
      } else if (plan.packages.isEmpty) {
        _out.writeln('nothing to release: every authored version is published');
      } else {
        _out.writeln(
          plan.dryRun
              ? 'dry-run: ${plan.packages.length} package(s) would publish'
              : 'released ${plan.packages.length} package(s)',
        );
        for (final package in plan.packages) {
          _out.writeln(
            '  ${package.tag}  '
            '(${package.publishedPredecessor ?? 'first release'} -> '
            '${package.localVersion})',
          );
        }
      }
      return 0;
    } on ReleaseWaveFailure catch (failure) {
      if (json) {
        _out.writeln(jsonEncode(failure.toJson()));
      } else {
        _err.writeln('release publish: $failure');
      }
      return 1;
    } on FileSystemException catch (error) {
      _err.writeln('release publish: ${error.message}: ${error.path}');
      return 64;
    } on FormatException catch (error) {
      _err.writeln('release publish: ${error.message}');
      return 64;
    } on ArgumentError catch (error) {
      _err.writeln('release publish: ${error.message}');
      return 64;
    }
  }
}
