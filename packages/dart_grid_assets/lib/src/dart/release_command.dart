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
    addSubcommand(ReleasePlanCommand(service: service, out: o, err: e));
    addSubcommand(ReleaseTagCommand(service: service, out: o));
    addSubcommand(
      ReleaseValidateConsumersCommand(service: service, out: o, err: e),
    );
    addSubcommand(ReleasePromoteCommand(service: service, out: o, err: e));
    addSubcommand(ReleaseScrubCommand(service: service, out: o, err: e));
    addSubcommand(ReleaseOrderCommand(service: service, out: o, err: e));
    addSubcommand(ReleaseDryRunCommand(service: service, out: o, err: e));
    addSubcommand(ReleasePollCommand(service: service, out: o));
  }

  @override
  final String name = 'release';

  @override
  final String description =
      'Deterministic Dart-package release ops (the machine substrate under the '
      'operator `release` skill): version plan, scrub gate, publish order, '
      'dry-run, and pub.dev poll — each a structured JSON result.';
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
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      consumers = [
        for (final entry in decoded['consumers'] as List)
          ReleaseConsumer.fromJson((entry as Map).cast<String, Object?>()),
      ];
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
      'Scan README/CHANGELOG/lib/example for internal refs (the scrub gate).';

  @override
  Future<int> run() async {
    final args = argResults!;
    final dir = args.option('dir')!;
    if (!Directory(dir).existsSync()) {
      _err.writeln('release scrub: no such dir: $dir');
      return 64;
    }
    final result = _service.scrubDir(dir);
    if (args.flag('json')) {
      _out.writeln(jsonEncode(result.toJson()));
    } else {
      _out.writeln(
        result.clean
            ? 'scrub clean (${result.filesScanned} files)'
            : 'scrub found ${result.hits.length} internal ref(s)',
      );
    }
    return 0;
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
        mandatory: true,
        help: 'A JSON file mapping package -> [in-set deps].',
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
      'Resolve the dependency-order publish sequence from a deps manifest.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final file = File(args.option('manifest')!);
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
    final PublishOrder order;
    try {
      order = _service.publishOrder(deps);
    } on StateError catch (e) {
      _err.writeln('release order: ${e.message}');
      return 1;
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

/// `dart release poll` — poll pub.dev for whether a version is now `latest`.
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
      'Poll pub.dev once — is <version> the latest for <package> yet?';

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
            ? '${result.package} ${result.wanted} is latest'
            : '${result.package}: latest is $latest, not ${result.wanted}',
      );
    }
    return 0;
  }
}
