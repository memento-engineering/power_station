/// The RELEASE circuit — the gated pipeline that makes publishing to pub.dev
/// NON-OPTIONAL.
///
/// Every other major path in this station is a circuit: discovery, spec,
/// spec-review, code, code-review, design-review, docs-review, landing. Release
/// was the one exception, and it is the one path that cannot be undone. It was
/// driven by an operator SKILL — prose an agent reads and may skip — so a
/// hand-cut release could record analyze, format, test and a dry-run in its gate
/// section and simply omit the declared-floors leg. That release published, and
/// it was retracted. The gate existed and worked; nothing REQUIRED it, because
/// the thing that makes a step non-optional in this machine is a circuit.
///
/// It COMPOSES, it does not reimplement. `discover`, `ladder`, `plan`, `scrub`,
/// `classify`, `order`, `dry-run`, `publish` and `poll` are already vended as
/// subcommands of the DART domain's release command group in
/// `dart_grid_assets`, and each already carries its own verdict. This file
/// ORDERS them and makes the order mandatory: one linear graph, one capability
/// per deterministic leg, and one canonical JSON receipt per node that the next
/// leg reads off the ambient [SiblingView]. Nothing here recomputes version
/// math, scans content, diffs an API or talks to pub.dev — a leg that could not
/// reach its vended verdict REFUSES rather than deciding for itself.
///
/// **No committee**
/// (`power_station#release-is-a-gated-pipeline-without-committee`). Every
/// release verdict is already machine-decidable — the content scrub, the
/// declared-floors analysis, the semver classification, the dry-run, the
/// propagation poll — so a committee round would re-judge what a deterministic
/// gate already decided, at the cost of latency and model spend and with no
/// added signal. There is no critic, no rubric, no inference leg in this graph.
///
/// **The human boundary is preserved.** Publishing a prerelease is agent work;
/// promoting `beta` to `rc`, and `rc` to a stable version, stays human.
/// [ReleasePromotionRouteCapability] compares the live ladder to each declared
/// target rung and ESCALATES a rung change into `rc` or `stable` that carries no
/// declared human intent — the circuit HALTS at a rung change rather than
/// driving through it. Publishing again at a rung a package already occupies is
/// ordinary agent work, and the already-established intent rides through to the
/// vended operations that require the flag.
///
/// **The irreversible step is spent once.** The `publish` leg declares one
/// initial attempt and parks at a gate on exhaustion for every failure kind, so
/// an interrupted tag-and-push wave is never auto-retried; and the final `poll`
/// leg refuses a zero exit that reports `isPublished: false`, because a
/// cancelled publish run may still have uploaded and only pub.dev's own versions
/// list answers whether a dependent may follow.
library;

import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:dart_grid_assets/dart_grid_assets.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:path/path.dart' as p;

import '../agent/captured_output.dart';
import 'route_failure.dart';

// ── ids ─────────────────────────────────────────────────────────────────────

/// The capability id every DETERMINISTIC release leg resolves through — one
/// capability, ten legs, selected by the step's `operation` param.
const String kReleaseGateCapabilityId = 'release-gate';

/// The capability id of the human-promotion route — the only decision point in
/// the release graph, and the only step that can HALT it short of a refusal.
const String kReleasePromotionRouteCapabilityId = 'release-promotion';

/// The result-payload key every release node writes its canonical JSON receipt
/// under (`grid.result.<nodePath>.release`). One key, one object, so a
/// downstream leg parses exactly one thing.
const String kReleaseReceiptKey = 'release';

/// The step param naming which vended release operation a gate node runs.
const String _kOperationParam = 'operation';

const String _kDiscoverStep = 'discover';
const String _kLadderStep = 'ladder';
const String _kPromotionStep = 'promotion';
const String _kPlanStep = 'plan';
const String _kScrubStep = 'scrub';
const String _kClassifyStep = 'classify';
const String _kOrderStep = 'order';
const String _kDryRunStep = 'dry-run';
const String _kPreflightStep = 'preflight';
const String _kPublishStep = 'publish';
const String _kPollStep = 'poll';

/// The tail budget a captured command diagnostic takes in a refusal reason —
/// tail-first, because a vended command prints its cause LAST
/// (`power_station#captured-process-output-escalates-tail-first`).
const int _kReleaseDiagnosticTailChars = 1200;

// ── the graph ───────────────────────────────────────────────────────────────

/// The RELEASE circuit (id `release`) — a strictly linear gated pipeline whose
/// always-1-wide frontier is the whole point: each leg's verdict gates the next,
/// and the irreversible one is last but two.
///
/// `discover → ladder → promotion → plan → scrub → classify → order → dry-run →
/// preflight → publish → poll`
///
/// Every node but `promotion` is a [ReleaseGateCapability] leg selected by its
/// `operation` param; `promotion` is the [ReleasePromotionRouteCapability]
/// route. `preflight` and `publish` are the SAME vended wave operation run twice
/// — once with `--dry-run` and once for real — and the gate refuses a wave whose
/// two answers disagree about any package, version, rung, dependency or tag.
const Circuit kReleaseCircuit = Circuit(
  id: 'release',
  terminalStepId: _kPollStep,
  steps: [
    CapabilityStep(
      stepId: _kDiscoverStep,
      capabilityId: kReleaseGateCapabilityId,
      params: {_kOperationParam: _kDiscoverStep},
    ),
    CapabilityStep(
      stepId: _kLadderStep,
      capabilityId: kReleaseGateCapabilityId,
      params: {_kOperationParam: _kLadderStep},
      dependsOn: {_kDiscoverStep},
    ),
    CapabilityStep(
      stepId: _kPromotionStep,
      capabilityId: kReleasePromotionRouteCapabilityId,
      dependsOn: {_kLadderStep},
    ),
    CapabilityStep(
      stepId: _kPlanStep,
      capabilityId: kReleaseGateCapabilityId,
      params: {_kOperationParam: _kPlanStep},
      dependsOn: {_kPromotionStep},
    ),
    CapabilityStep(
      stepId: _kScrubStep,
      capabilityId: kReleaseGateCapabilityId,
      params: {_kOperationParam: _kScrubStep},
      dependsOn: {_kPlanStep},
    ),
    CapabilityStep(
      stepId: _kClassifyStep,
      capabilityId: kReleaseGateCapabilityId,
      params: {_kOperationParam: _kClassifyStep},
      dependsOn: {_kScrubStep},
    ),
    CapabilityStep(
      stepId: _kOrderStep,
      capabilityId: kReleaseGateCapabilityId,
      params: {_kOperationParam: _kOrderStep},
      dependsOn: {_kClassifyStep},
    ),
    CapabilityStep(
      stepId: _kDryRunStep,
      capabilityId: kReleaseGateCapabilityId,
      params: {_kOperationParam: _kDryRunStep},
      dependsOn: {_kOrderStep},
    ),
    CapabilityStep(
      stepId: _kPreflightStep,
      capabilityId: kReleaseGateCapabilityId,
      params: {_kOperationParam: _kPreflightStep},
      dependsOn: {_kDryRunStep},
    ),
    CapabilityStep(
      stepId: _kPublishStep,
      capabilityId: kReleaseGateCapabilityId,
      params: {_kOperationParam: _kPublishStep},
      dependsOn: {_kPreflightStep},
    ),
    CapabilityStep(
      stepId: _kPollStep,
      capabilityId: kReleaseGateCapabilityId,
      params: {_kOperationParam: _kPollStep},
      dependsOn: {_kPublishStep},
    ),
  ],
);

// ── the request (config = VALUES in the tree) ───────────────────────────────

/// One package a release wave publishes: WHAT it is, WHERE it lives relative to
/// the workspace root, and the prerelease rung the wave means it to occupy.
///
/// A VALUE, mounted in the tree as part of [ReleaseCircuitRequest] and read at
/// each capability's effect edge — never a service and never mutable state.
class ReleasePackageTarget {
  /// Declares [package] at the workspace-relative [directory], targeting
  /// [targetRung].
  const ReleasePackageTarget({
    required this.package,
    required this.directory,
    required this.targetRung,
  });

  /// The pub package name — what pub.dev lists and what a tag is composed from.
  final String package;

  /// The member directory, RELATIVE to [ReleaseCircuitRequest.workspaceRoot].
  final String directory;

  /// The prerelease rung this wave means the package to occupy. A rung CHANGE
  /// into [ReleaseRung.rc] or [ReleaseRung.stable] is the human boundary
  /// [ReleasePromotionRouteCapability] halts at.
  final ReleaseRung targetRung;
}

/// Everything a release wave is: the workspace, the ref the changed-package
/// query compares against, the semver move, the packages it publishes, the
/// optional consumers manifest a stable wave owes, and whether a human declared
/// intent to promote.
///
/// A mounted CONFIGURATION VALUE (ADR-0008 D-H): the station mounts one, every
/// leg reads it at its own effect edge, and nothing here caches or re-projects
/// it. The collections are frozen at construction and the shape is validated
/// LOUDLY — a duplicated package, a duplicated directory, or a directory that
/// escapes the workspace is an authoring error, never a wave that publishes
/// something it did not mean to.
class ReleaseCircuitRequest {
  /// Creates the request, freezing [packages] and refusing a malformed set.
  ReleaseCircuitRequest({
    required this.workspaceRoot,
    required this.diff,
    required this.change,
    required List<ReleasePackageTarget> packages,
    this.consumersManifest,
    this.humanPromotionIntent = false,
  }) : packages = List<ReleasePackageTarget>.unmodifiable(packages) {
    if (this.packages.isEmpty) {
      throw ArgumentError.value(
        packages,
        'packages',
        'a release wave publishes at least one package',
      );
    }
    final names = <String>{};
    final directories = <String>{};
    for (final target in this.packages) {
      if (!names.add(target.package)) {
        throw ArgumentError.value(
          target.package,
          'packages',
          'is declared more than once; a wave publishes each package once',
        );
      }
      final normalized = p.normalize(target.directory);
      if (!directories.add(normalized)) {
        throw ArgumentError.value(
          target.directory,
          'packages',
          'is declared by more than one package target',
        );
      }
      if (normalized.isEmpty ||
          p.isAbsolute(normalized) ||
          normalized == '..' ||
          normalized.startsWith('../') ||
          normalized.startsWith('..${p.separator}')) {
        throw ArgumentError.value(
          target.directory,
          'packages',
          'resolves outside the workspace root; a member directory is '
              'workspace-relative',
        );
      }
    }
  }

  /// The pub workspace root every workspace-scoped operation runs against.
  final String workspaceRoot;

  /// The git ref HEAD is compared against for the changed-package query.
  final String diff;

  /// The semver move the whole wave carries.
  final ReleaseChange change;

  /// The packages this wave publishes — frozen, deduplicated, workspace-local.
  final List<ReleasePackageTarget> packages;

  /// The consumers manifest a wave carrying a stable package owes; null for an
  /// all-prerelease wave.
  final String? consumersManifest;

  /// Whether a HUMAN declared intent to promote. It is the only thing that
  /// admits a rung CHANGE into `rc` or `stable`.
  final bool humanPromotionIntent;

  /// The configured package names, sorted — the set discovery must agree with.
  List<String> get packageNames =>
      [for (final target in packages) target.package]..sort();

  /// The absolute package directory the vended `--dir` flags name for [target].
  String directoryFor(ReleasePackageTarget target) =>
      p.normalize(p.join(workspaceRoot, target.directory));

  /// Whether any target sits on a rung whose vended operations require a
  /// declared promotion intent. [ReleasePromotionRouteCapability] is what makes
  /// supplying it legitimate; this only reports that it is needed.
  bool get requiresPromotionIntentFlag =>
      packages.any((target) => target.targetRung.requiresPromotionIntent);
}

// ── the command seam ────────────────────────────────────────────────────────

/// One vended release-command invocation's result — the exit code and both
/// captured streams, and nothing else. The circuit reads verdicts out of the
/// JSON object on [stdout]; [stderr] and a non-zero [exitCode] are what a
/// refusal quotes.
class ReleaseCommandInvocation {
  /// Creates the invocation result.
  const ReleaseCommandInvocation({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// The command's exit code.
  final int exitCode;

  /// Everything the command wrote to its out sink.
  final String stdout;

  /// Everything the command wrote to its err sink.
  final String stderr;
}

/// The injectable seam every release leg runs its vended operation through.
///
/// It takes ARGV, exactly as an operator would type it, and returns what the
/// command answered. That is what keeps the circuit a composition: the legs know
/// the argv and the JSON contract of the vended commands and nothing about how
/// a release is computed. Tests inject a recording Fake (Fakes, not mocks).
abstract interface class ReleaseCommandInvoker {
  /// Runs the vended release command named by [arguments] and yields its
  /// result. Never throws for a command that merely FAILED — a refusal is a
  /// non-zero [ReleaseCommandInvocation.exitCode].
  Future<ReleaseCommandInvocation> run(List<String> arguments);
}

/// The live [ReleaseCommandInvoker]: composes a fresh vended release command
/// group per call, with captured output, and runs the requested subcommand
/// IN-PROCESS.
///
/// It calls no release-service method of its own. The service reaches the
/// command only through the command group's own constructor seam — the same
/// injection point the DART domain's CLI uses — so this invoker adds no second
/// path to the release logic, and a Fake service reaches the real commands.
///
/// It admits only the JSON surface of that one command group: the invariant is
/// that a release leg consumes a STRUCTURED verdict, never scraped prose, and it
/// is loud rather than silently running something else.
class InProcessReleaseCommandInvoker implements ReleaseCommandInvoker {
  /// Creates the invoker over [service] — the seam a test injects process,
  /// pub.dev and wait Fakes through.
  const InProcessReleaseCommandInvoker({
    ReleaseService service = const ReleaseService(),
  }) : _service = service;

  final ReleaseService _service;

  @override
  Future<ReleaseCommandInvocation> run(List<String> arguments) async {
    if (arguments.isEmpty ||
        arguments.first != 'release' ||
        !arguments.contains('--json')) {
      throw ArgumentError.value(
        arguments,
        'arguments',
        'the release circuit invokes only the vended `release <op> … --json` '
            'surface',
      );
    }
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = CommandRunner<int>('grid_assets', _kInvokerDescription)
      ..addCommand(ReleaseCommand(service: _service, out: out, err: err));
    try {
      final exitCode = await runner.run(arguments) ?? 0;
      return ReleaseCommandInvocation(
        exitCode: exitCode,
        stdout: out.toString(),
        stderr: err.toString(),
      );
    } on UsageException catch (error) {
      return ReleaseCommandInvocation(
        exitCode: 64,
        stdout: out.toString(),
        stderr: '$err${error.message}',
      );
    }
  }
}

const String _kInvokerDescription =
    'The release circuit\'s in-process host for the vended release commands.';

// ── the deterministic legs ──────────────────────────────────────────────────

/// Which vended operation one gate node runs. Private and exhaustively
/// switched: a new leg is a compile error at the dispatch, never a silent
/// no-op.
enum _ReleaseOperation {
  discover(_kDiscoverStep),
  ladder(_kLadderStep),
  plan(_kPlanStep),
  scrub(_kScrubStep),
  classify(_kClassifyStep),
  order(_kOrderStep),
  dryRun(_kDryRunStep),
  preflight(_kPreflightStep),
  publish(_kPublishStep),
  poll(_kPollStep);

  const _ReleaseOperation(this.wireName);

  /// The step id AND the `operation` param value — one vocabulary, so a node
  /// path and its leg can never name different things.
  final String wireName;

  static _ReleaseOperation? parse(String? value) => switch (value) {
    _kDiscoverStep => _ReleaseOperation.discover,
    _kLadderStep => _ReleaseOperation.ladder,
    _kPlanStep => _ReleaseOperation.plan,
    _kScrubStep => _ReleaseOperation.scrub,
    _kClassifyStep => _ReleaseOperation.classify,
    _kOrderStep => _ReleaseOperation.order,
    _kDryRunStep => _ReleaseOperation.dryRun,
    _kPreflightStep => _ReleaseOperation.preflight,
    _kPublishStep => _ReleaseOperation.publish,
    _kPollStep => _ReleaseOperation.poll,
    _ => null,
  };
}

/// The sibling receipts each leg REQUIRES before it runs — its immediate
/// predecessor (so the pipeline order is enforced inside the leg as well as by
/// the graph) plus every earlier receipt it actually reads.
const Map<_ReleaseOperation, List<String>> _kRequiredReceipts = {
  _ReleaseOperation.discover: <String>[],
  _ReleaseOperation.ladder: [_kDiscoverStep],
  _ReleaseOperation.plan: [_kPromotionStep, _kLadderStep],
  _ReleaseOperation.scrub: [_kPlanStep],
  _ReleaseOperation.classify: [_kScrubStep, _kLadderStep],
  _ReleaseOperation.order: [_kClassifyStep],
  _ReleaseOperation.dryRun: [_kOrderStep],
  _ReleaseOperation.preflight: [_kDryRunStep, _kOrderStep],
  _ReleaseOperation.publish: [_kPreflightStep, _kOrderStep],
  _ReleaseOperation.poll: [_kPublishStep],
};

/// The irreversible leg's supervision declaration: ONE attempt, then park at a
/// gate — for a substantive failure, for a turn that produced no result, and
/// for one whose result violated its contract alike.
///
/// A tag push IS the publish. An interrupted wave may already have uploaded, so
/// re-running it is not a retry of the same work — it is a second release
/// attempt against a registry that may have moved. A human reads the gate.
const SupervisionPolicy _kIrreversiblePublishPolicy = SupervisionPolicy(
  byKind: {
    CapabilityFailureKind.work: RetryPolicy(
      maxRestarts: 0,
      onExhaustion: ExhaustionBehavior.parkAtGate,
    ),
    CapabilityFailureKind.noResult: RetryPolicy(
      maxRestarts: 0,
      onExhaustion: ExhaustionBehavior.parkAtGate,
    ),
    CapabilityFailureKind.invalidResult: RetryPolicy(
      maxRestarts: 0,
      onExhaustion: ExhaustionBehavior.parkAtGate,
    ),
  },
);

/// One release leg's REFUSAL, carried as a throw so each leg body reads as the
/// straight line it is. The gate turns it back into the [StepOutcome] it wraps.
class _GateRefusal implements Exception {
  const _GateRefusal(this.outcome);

  final StepOutcome outcome;
}

/// What one vended invocation answered, before any leg judges it.
typedef _Invocation = ({
  int exitCode,
  Map<String, Object?>? json,
  String rendered,
  String diagnostic,
});

/// The deterministic release legs — ONE capability, ten operations, selected by
/// the step's `operation` param.
///
/// Each leg reads the ambient [ReleaseCircuitRequest] and its required sibling
/// receipts ONCE at entry with the effect verb, invokes the vended operations it
/// composes, checks the verdicts those operations already computed, and writes
/// ONE canonical JSON receipt under [kReleaseReceiptKey]. It decides nothing a
/// vended command already decides; what it OWNS is the refusal — a missing
/// package, a missing receipt, a non-zero command, a malformed answer, an
/// unclean gate, an understated bump, a wave that disagrees with the publish
/// order or with its own preflight, and a version pub.dev does not yet list.
class ReleaseGateCapability extends ServiceCapability {
  /// Creates the gate over [invoker] — the vended-command seam.
  const ReleaseGateCapability(this._invoker);

  final ReleaseCommandInvoker _invoker;

  @override
  SupervisionPolicy supervisionPolicy(StepArgs args) =>
      _ReleaseOperation.parse(args.params[_kOperationParam]) ==
          _ReleaseOperation.publish
      ? _kIrreversiblePublishPolicy
      : const SupervisionPolicy.inherit();

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    final operation = _ReleaseOperation.parse(args.params[_kOperationParam]);
    if (operation == null) {
      return Failed.invalidResult(
        'release gate: ${args.nodePath} declares no known release operation '
        '(params[$_kOperationParam] = '
        '${args.params[_kOperationParam] ?? '<absent>'}).',
      );
    }
    // Read every ambient value at ENTRY, while mounted; after this only the
    // captured values and the cancel token are touched.
    final request = context
        .getInheritedSeedOfExactType<ReleaseCircuitRequest>();
    if (request == null) {
      return Failed.noResult(
        'release ${operation.wireName}: no ReleaseCircuitRequest is mounted — '
        'a release wave is a configured VALUE in the tree, never inferred.',
      );
    }
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    try {
      final receipts = _requiredReceiptsFor(operation, siblings, args);
      final receipt = await switch (operation) {
        _ReleaseOperation.discover => _discover(request, args),
        _ReleaseOperation.ladder => _ladder(request, args),
        _ReleaseOperation.plan => _plan(request, receipts, args),
        _ReleaseOperation.scrub => _scrub(request, args),
        _ReleaseOperation.classify => _classify(request, receipts, args),
        _ReleaseOperation.order => _order(request, args),
        _ReleaseOperation.dryRun => _dryRun(request, args),
        _ReleaseOperation.preflight => _wave(
          operation,
          request,
          receipts,
          args,
        ),
        _ReleaseOperation.publish => _wave(operation, request, receipts, args),
        _ReleaseOperation.poll => _poll(receipts, args),
      };
      return Ok({kReleaseReceiptKey: jsonEncode(receipt)});
    } on _GateRefusal catch (refusal) {
      return refusal.outcome;
    } on FormatException catch (error) {
      return Failed.invalidResult(
        'release ${operation.wireName}: ${error.message}',
      );
    }
  }

  /// Every receipt [operation] requires, read off [siblings] at this node's own
  /// circuit path. A missing one is LOUD: it means the ordered pipeline did not
  /// run, and a release leg that proceeds on a predecessor it cannot read is the
  /// optional gate this circuit exists to end.
  Map<String, Map<String, Object?>> _requiredReceiptsFor(
    _ReleaseOperation operation,
    SiblingView siblings,
    StepArgs args,
  ) {
    final circuitPath = _circuitPathOf(args.nodePath);
    final receipts = <String, Map<String, Object?>>{};
    for (final stepId in _kRequiredReceipts[operation]!) {
      final receipt = _receiptAt(siblings, '$circuitPath/$stepId');
      if (receipt == null) {
        throw _GateRefusal(
          Failed.noResult(
            'release ${operation.wireName}: the `$stepId` receipt is missing at '
            '$circuitPath/$stepId — the release pipeline runs in order, and a '
            'leg never runs on a predecessor it cannot read.',
          ),
        );
      }
      receipts[stepId] = receipt;
    }
    return receipts;
  }

  /// Runs one vended operation and reports what it answered — the exit code,
  /// the single JSON object it wrote (null when it wrote none or wrote more
  /// than one), and the diagnostic a refusal quotes. A cancelled turn unwinds
  /// here; every other judgement belongs to the caller, because a vended verdict
  /// operation reports a DECIDED negative by exiting non-zero WITH its verdict.
  Future<_Invocation> _invoke(
    _ReleaseOperation operation,
    List<String> arguments,
    StepArgs args,
  ) async {
    final invocation = await _invoker.run(arguments);
    if (args.cancel.isCancelled) {
      throw _GateRefusal(
        Failed.noResult('release ${operation.wireName}: cancelled'),
      );
    }
    return (
      exitCode: invocation.exitCode,
      json: _decodeSingleObject(invocation.stdout),
      rendered: arguments.join(' '),
      diagnostic: _diagnostic(invocation),
    );
  }

  /// Runs one vended operation whose only success is exit zero, and yields the
  /// single JSON object it wrote. A non-zero exit and an answer that is not
  /// exactly one JSON object are each a refusal — never a leg that proceeds on a
  /// verdict it did not read.
  Future<Map<String, Object?>> _invokeJson(
    _ReleaseOperation operation,
    List<String> arguments,
    StepArgs args,
  ) async {
    final invocation = await _invoke(operation, arguments, args);
    _refuseNonZero(operation, invocation);
    return _requireJson(operation, invocation);
  }

  /// The single JSON object [invocation] carries, or a refusal.
  Map<String, Object?> _requireJson(
    _ReleaseOperation operation,
    _Invocation invocation,
  ) {
    final json = invocation.json;
    if (json == null) {
      throw _GateRefusal(
        Failed.invalidResult(
          'release ${operation.wireName}: `${invocation.rendered}` did not '
          'write exactly one JSON object: ${invocation.diagnostic}',
        ),
      );
    }
    return json;
  }

  /// Refuses a non-zero [invocation], quoting the wave failure's own message
  /// when the command wrote one.
  void _refuseNonZero(_ReleaseOperation operation, _Invocation invocation) {
    if (invocation.exitCode == 0) return;
    final failure = invocation.json?['message'];
    throw _GateRefusal(
      Failed(
        'release ${operation.wireName}: `${invocation.rendered}` exited '
        '${invocation.exitCode}: '
        '${failure is String && failure.isNotEmpty ? failure : invocation.diagnostic}',
      ),
    );
  }

  // ── discover ──────────────────────────────────────────────────────────────

  Future<Map<String, Object?>> _discover(
    ReleaseCircuitRequest request,
    StepArgs args,
  ) async {
    const operation = _ReleaseOperation.discover;
    final json = await _invokeJson(operation, [
      'release',
      _kDiscoverStep,
      '--workspace',
      request.workspaceRoot,
      '--diff',
      request.diff,
      '--json',
    ], args);
    final what = 'the release discover result';
    final candidates = _stringListAt(json, 'candidates', what);
    final configured = request.packageNames;
    if (!_sameSet(candidates, configured)) {
      throw _GateRefusal(
        Failed(
          'release discover: ${request.workspaceRoot} offers '
          '[${candidates.join(', ')}] but the wave configures '
          '[${configured.join(', ')}] — a release wave publishes exactly its '
          'configured set, so neither an unlisted package nor an unclaimed one '
          'may ride along.',
        ),
      );
    }
    return <String, Object?>{
      _kOperationParam: operation.wireName,
      'workspaceRoot': request.workspaceRoot,
      'diff': request.diff,
      'candidates': candidates,
      'changed': _stringListAt(json, 'changed', what),
      'packages': configured,
    };
  }

  // ── ladder ────────────────────────────────────────────────────────────────

  /// Reads EVERY bounded page of the ladder report. The vended report caps its
  /// window and names the next offset; a caller that read only the first page
  /// would decide a promotion off a report it never finished.
  Future<Map<String, Object?>> _ladder(
    ReleaseCircuitRequest request,
    StepArgs args,
  ) async {
    const operation = _ReleaseOperation.ladder;
    final what = 'the release ladder result';
    final records = <String, Map<String, Object?>>{};
    var skip = 0;
    var pages = 0;
    var total = -1;
    while (true) {
      final json = await _invokeJson(operation, [
        'release',
        _kLadderStep,
        '--workspace',
        request.workspaceRoot,
        '--skip',
        '$skip',
        '--json',
      ], args);
      pages++;
      final pageTotal = _intAt(json, 'totalPackages', what);
      if (total >= 0 && pageTotal != total) {
        throw _GateRefusal(
          Failed.invalidResult(
            'release ladder: the report declared $total packages and then '
            '$pageTotal — the workspace moved under the paged read.',
          ),
        );
      }
      total = pageTotal;
      final page = _objectListAt(json, 'packages', what);
      final before = records.length;
      for (final record in page) {
        records[_stringAt(record, 'package', what)] = record;
      }
      if (records.length >= total) break;
      // The read must MAKE PROGRESS. An empty page, and a page that repeats
      // records already read, are the same defect: the rest of the report is
      // unreachable, and looping on it would hang the leg instead of refusing.
      if (records.length == before) {
        throw _GateRefusal(
          Failed.invalidResult(
            'release ladder: the page at --skip $skip added no record while '
            '${total - records.length} of $total remain — the paged read '
            'cannot reach the rest of the report.',
          ),
        );
      }
      skip = _intAt(json, 'offset', what) + page.length;
    }
    final facts = <String, Object?>{};
    for (final target in request.packages) {
      final record = records[target.package];
      if (record == null) {
        throw _GateRefusal(
          Failed(
            'release ladder: the report names no record for '
            '${target.package} — the wave configures a package the workspace '
            'does not publish.',
          ),
        );
      }
      facts[target.package] = <String, Object?>{
        'hasPublishedVersion': _boolAt(record, 'hasPublishedVersion', what),
        'currentPublishedVersion': _optionalStringAt(
          record,
          'currentPublishedVersion',
          what,
        ),
        'rung': _optionalStringAt(record, 'rung', what),
        'targetRung': target.targetRung.name,
      };
    }
    return <String, Object?>{
      _kOperationParam: operation.wireName,
      'pages': pages,
      'totalPackages': total,
      'packages': facts,
    };
  }

  // ── plan ──────────────────────────────────────────────────────────────────

  Future<Map<String, Object?>> _plan(
    ReleaseCircuitRequest request,
    Map<String, Map<String, Object?>> receipts,
    StepArgs args,
  ) async {
    const operation = _ReleaseOperation.plan;
    final what = 'the release plan result';
    final ladder = _ladderFacts(receipts);
    final planned = <String, Object?>{};
    for (final target in request.packages) {
      final facts = _ladderFactsFor(ladder, target.package);
      if (!_boolAt(facts, 'hasPublishedVersion', 'the ladder receipt')) {
        planned[target.package] = _kFirstReleaseReceipt;
        continue;
      }
      final current = _currentPublishedVersion(facts, target.package);
      final json = await _invokeJson(operation, [
        'release',
        _kPlanStep,
        '--package',
        target.package,
        '--current',
        current,
        '--change',
        request.change.name,
        '--rung',
        target.targetRung.name,
        if (target.targetRung.requiresPromotionIntent) '--promotion-intent',
        '--json',
      ], args);
      planned[target.package] = <String, Object?>{
        'current': _stringAt(json, 'current', what),
        'next': _stringAt(json, 'next', what),
        'change': _stringAt(json, 'change', what),
        'rung': _stringAt(json, 'rung', what),
        'tag': _stringAt(json, 'tag', what),
      };
    }
    return <String, Object?>{
      _kOperationParam: operation.wireName,
      'packages': planned,
    };
  }

  // ── scrub ─────────────────────────────────────────────────────────────────

  Future<Map<String, Object?>> _scrub(
    ReleaseCircuitRequest request,
    StepArgs args,
  ) async {
    const operation = _ReleaseOperation.scrub;
    final what = 'the release scrub result';
    final scrubbed = <String, Object?>{};
    for (final target in request.packages) {
      // The vended scrub reports a DECIDED unclean verdict by exiting one WITH
      // its result, so the verdict is read first and the exit code is only the
      // backstop for an answer that contradicts it.
      final invocation = await _invoke(operation, [
        'release',
        _kScrubStep,
        '--dir',
        request.directoryFor(target),
        '--json',
      ], args);
      final json = _requireJson(operation, invocation);
      final floors = json['declaredFloors'];
      final floorsPassed = floors is Map<String, Object?>
          ? _boolAt(floors, 'passed', what)
          : null;
      if (!_boolAt(json, 'clean', what) || floorsPassed == false) {
        throw _GateRefusal(
          Failed(
            'release scrub: ${target.package} did not pass the scrub gate — '
            '${_scrubReason(json, floors)}',
          ),
        );
      }
      _refuseNonZero(operation, invocation);
      scrubbed[target.package] = <String, Object?>{
        'clean': true,
        'filesScanned': _intAt(json, 'filesScanned', what),
        'declaredFloorsPassed': floorsPassed,
      };
    }
    return <String, Object?>{
      _kOperationParam: operation.wireName,
      'packages': scrubbed,
    };
  }

  // ── classify ──────────────────────────────────────────────────────────────

  Future<Map<String, Object?>> _classify(
    ReleaseCircuitRequest request,
    Map<String, Map<String, Object?>> receipts,
    StepArgs args,
  ) async {
    const operation = _ReleaseOperation.classify;
    final what = 'the release classify result';
    final ladder = _ladderFacts(receipts);
    final classified = <String, Object?>{};
    for (final target in request.packages) {
      final facts = _ladderFactsFor(ladder, target.package);
      if (!_boolAt(facts, 'hasPublishedVersion', 'the ladder receipt')) {
        classified[target.package] = _kFirstReleaseReceipt;
        continue;
      }
      // Like the scrub, an UNDERSTATED classification is a decided verdict the
      // command reports by exiting one; a missing analyzer is the loud refusal
      // it already owns (`power_station#release-classification-shells-out-to-
      // dart-apitool`), and that arrives with no verdict at all.
      final invocation = await _invoke(operation, [
        'release',
        _kClassifyStep,
        '--dir',
        request.directoryFor(target),
        '--package',
        target.package,
        '--json',
      ], args);
      final json = _requireJson(operation, invocation);
      final verdict = _stringAt(json, 'verdict', what);
      if (verdict != 'ok') {
        throw _GateRefusal(
          Failed(
            'release classify: ${target.package} is $verdict — '
            '${_stringAt(json, 'message', what)}',
          ),
        );
      }
      _refuseNonZero(operation, invocation);
      classified[target.package] = <String, Object?>{
        'verdict': verdict,
        'requiredChange': _stringAt(json, 'requiredChange', what),
        'declaredChange': _stringAt(json, 'declaredChange', what),
      };
    }
    return <String, Object?>{
      _kOperationParam: operation.wireName,
      'packages': classified,
    };
  }

  // ── order ─────────────────────────────────────────────────────────────────

  Future<Map<String, Object?>> _order(
    ReleaseCircuitRequest request,
    StepArgs args,
  ) async {
    const operation = _ReleaseOperation.order;
    final json = await _invokeJson(operation, [
      'release',
      _kOrderStep,
      '--workspace',
      request.workspaceRoot,
      '--json',
    ], args);
    final order = _stringListAt(json, 'order', 'the release order result');
    final configured = request.packageNames.toSet();
    final projected = [
      for (final name in order)
        if (configured.contains(name)) name,
    ];
    if (projected.length != configured.length) {
      throw _GateRefusal(
        Failed(
          'release order: the workspace publish order [${order.join(' -> ')}] '
          'omits '
          '[${configured.difference(projected.toSet()).join(', ')}] — the wave '
          'cannot be sequenced against a graph that does not carry it.',
        ),
      );
    }
    return <String, Object?>{
      _kOperationParam: operation.wireName,
      'order': order,
      'projected': projected,
    };
  }

  // ── dry-run ───────────────────────────────────────────────────────────────

  Future<Map<String, Object?>> _dryRun(
    ReleaseCircuitRequest request,
    StepArgs args,
  ) async {
    const operation = _ReleaseOperation.dryRun;
    final what = 'the release dry-run result';
    final results = <String, Object?>{};
    for (final target in request.packages) {
      final json = await _invokeJson(operation, [
        'release',
        _kDryRunStep,
        '--dir',
        request.directoryFor(target),
        '--package',
        target.package,
        '--json',
      ], args);
      // The vended dry-run always exits zero — it REPORTS the gate rather than
      // enforcing it — so the verdict, not the exit code, is the gate here.
      if (!_boolAt(json, 'clean', what)) {
        throw _GateRefusal(
          Failed(
            'release dry-run: ${target.package} is not publishable — exit '
            '${_intAt(json, 'exitCode', what)}, '
            '${_intAt(json, 'warningCount', what)} warning(s): '
            '${_stringListAt(json, 'warnings', what).join('; ')}',
          ),
        );
      }
      results[target.package] = <String, Object?>{
        'clean': true,
        'warningCount': _intAt(json, 'warningCount', what),
      };
    }
    return <String, Object?>{
      _kOperationParam: operation.wireName,
      'packages': results,
    };
  }

  // ── preflight + publish (the SAME wave operation, twice) ──────────────────

  Future<Map<String, Object?>> _wave(
    _ReleaseOperation operation,
    ReleaseCircuitRequest request,
    Map<String, Map<String, Object?>> receipts,
    StepArgs args,
  ) async {
    final preflight = operation == _ReleaseOperation.preflight;
    final what = 'the release ${operation.wireName} result';
    final json = await _invokeJson(operation, [
      'release',
      _kPublishStep,
      '--workspace',
      request.workspaceRoot,
      '--change',
      request.change.name,
      if (request.consumersManifest != null) ...[
        '--consumers',
        request.consumersManifest!,
      ],
      if (request.requiresPromotionIntentFlag) '--promotion-intent',
      if (preflight) '--dry-run',
      '--json',
    ], args);
    final dryRun = _boolAt(json, 'dryRun', what);
    if (dryRun != preflight) {
      throw _GateRefusal(
        Failed.invalidResult(
          'release ${operation.wireName}: the wave answered dryRun=$dryRun '
          'where the ${preflight ? 'preflight' : 'irreversible'} leg requires '
          'dryRun=$preflight.',
        ),
      );
    }
    final facts = _waveFacts(json, what);
    final ordered = [for (final fact in facts) fact['package'] as String];
    // BOTH wave answers are checked against the workspace's own dependency
    // order, not just the one that cleared: the whole point of the barrier is
    // that a dependent is never tagged before what it resolves.
    final projected = _stringListAt(
      receipts[_kOrderStep]!,
      'projected',
      'the order receipt',
    );
    if (!_sameOrder(ordered, projected)) {
      throw _GateRefusal(
        Failed(
          'release ${operation.wireName}: the wave would publish '
          '[${ordered.join(' -> ')}] where the workspace dependency order is '
          '[${projected.join(' -> ')}] — a dependent must never be tagged '
          'before what it resolves.',
        ),
      );
    }
    if (!preflight) {
      final preflightReceipt = receipts[_kPreflightStep]!;
      final preflightFacts = _objectListAt(
        preflightReceipt,
        'packages',
        'the preflight receipt',
      );
      if (jsonEncode(preflightFacts) != jsonEncode(facts)) {
        throw _GateRefusal(
          Failed(
            'release publish: the wave that ran differs from the wave the '
            'preflight cleared at ${_firstWaveDifference(preflightFacts, facts)}'
            ' — nothing publishes on a plan no gate saw.',
          ),
        );
      }
    }
    return <String, Object?>{
      _kOperationParam: operation.wireName,
      'dryRun': dryRun,
      'packages': facts,
    };
  }

  // ── poll ──────────────────────────────────────────────────────────────────

  /// The propagation barrier, re-asserted after the wave: a zero exit is not
  /// publication. A cancelled or partially-completed publish run may still have
  /// uploaded, and only pub.dev's own versions list answers whether a version is
  /// there — so the pipeline ends by ASKING, per published package.
  Future<Map<String, Object?>> _poll(
    Map<String, Map<String, Object?>> receipts,
    StepArgs args,
  ) async {
    const operation = _ReleaseOperation.poll;
    final what = 'the release poll result';
    final published = _objectListAt(
      receipts[_kPublishStep]!,
      'packages',
      'the publish receipt',
    );
    final polled = <String, Object?>{};
    for (final fact in published) {
      final package = _stringAt(fact, 'package', 'the publish receipt');
      final version = _stringAt(fact, 'localVersion', 'the publish receipt');
      final json = await _invokeJson(operation, [
        'release',
        _kPollStep,
        '--package',
        package,
        '--version',
        version,
        '--json',
      ], args);
      if (!_boolAt(json, 'isPublished', what)) {
        throw _GateRefusal(
          Failed(
            'release poll: pub.dev does not list $package $version (status '
            '${_intAt(json, 'statusCode', what)}, listed '
            '[${_stringListAt(json, 'versions', what).join(', ')}]) — an exit '
            'code is not publication.',
          ),
        );
      }
      polled[package] = <String, Object?>{
        'version': version,
        'isPublished': true,
      };
    }
    return <String, Object?>{
      _kOperationParam: operation.wireName,
      'packages': polled,
    };
  }
}

/// The receipt a baseline-dependent leg writes for a FIRST publication — the
/// explicit "this leg does not apply", never a silently skipped package.
const Map<String, Object?> _kFirstReleaseReceipt = {'firstRelease': true};

// ── the human boundary ──────────────────────────────────────────────────────

/// The PROMOTION route — the only decision point in the release graph, and the
/// place the pipeline HALTS rather than driving through a rung change only a
/// human may make.
///
/// It compares the live ladder facts to each declared target rung. Entering
/// [ReleaseRung.rc] or [ReleaseRung.stable] from a different rung (a first
/// publication included — an unpublished package occupies no rung) is the human
/// boundary: without a declared [ReleaseCircuitRequest.humanPromotionIntent] it
/// [Escalate]s, naming every transition it held. Publishing again at a rung a
/// package ALREADY occupies is ordinary agent work: the intent that put it there
/// is already established, and the gate legs supply the flag the vended
/// operations require.
///
/// It reads, it never writes; the ladder is a vended read and the target rungs
/// are configuration, so the whole verdict is deterministic.
class ReleasePromotionRouteCapability extends RouteCapability {
  /// Creates the route.
  const ReleasePromotionRouteCapability();

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    final request = context
        .getInheritedSeedOfExactType<ReleaseCircuitRequest>();
    if (request == null) {
      throw const RouteFailure(
        'release promotion: no ReleaseCircuitRequest is mounted — a release '
        'wave is a configured VALUE in the tree, never inferred.',
      );
    }
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final ladderPath = '${_circuitPathOf(args.nodePath)}/$_kLadderStep';
    final ladder = _receiptAt(siblings, ladderPath);
    if (ladder == null) {
      throw RouteFailure(
        'release promotion: the `$_kLadderStep` receipt is missing at '
        '$ladderPath — a promotion is decided against the live ladder, never '
        'against the wave\'s own wish.',
      );
    }
    try {
      final facts = _objectAt(ladder, 'packages', 'the ladder receipt');
      final transitions = <Map<String, Object?>>[];
      final held = <String>[];
      for (final target in request.packages) {
        final record = _ladderFactsFor(facts, target.package);
        final from = _optionalStringAt(record, 'rung', 'the ladder receipt');
        final to = target.targetRung;
        final isRungChange = from != to.name;
        final needsHuman =
            isRungChange && (to == ReleaseRung.rc || to == ReleaseRung.stable);
        if (needsHuman && !request.humanPromotionIntent) {
          held.add('${target.package} ${from ?? 'unpublished'} -> ${to.name}');
        }
        transitions.add(<String, Object?>{
          'package': target.package,
          'from': from,
          'to': to.name,
          'isRungChange': isRungChange,
          'requiresHumanIntent': needsHuman,
        });
      }
      if (held.isNotEmpty) {
        return Escalate(
          'release promotion halts: [${held.join('; ')}] '
          '${held.length == 1 ? 'is a rung change' : 'are rung changes'} into a '
          'rung only a human may set, and no promotion intent is declared. '
          'Publishing a prerelease is agent work; promoting beta to rc, and rc '
          'to stable, is not.',
        );
      }
      return Advance({
        kReleaseReceiptKey: jsonEncode(<String, Object?>{
          _kOperationParam: _kPromotionStep,
          'humanPromotionIntent': request.humanPromotionIntent,
          'promotionIntentFlag': request.requiresPromotionIntentFlag,
          'transitions': transitions,
        }),
      });
    } on FormatException catch (error) {
      throw RouteFailure('release promotion: ${error.message}');
    }
  }
}

// ── shared readers ──────────────────────────────────────────────────────────

/// The node path of the release circuit this step belongs to — the prefix every
/// sibling receipt is read at.
String _circuitPathOf(String nodePath) {
  final cut = nodePath.lastIndexOf('/');
  if (cut <= 0) {
    throw FormatException(
      '$nodePath is not a release step inside a circuit; a release leg reads '
      'its siblings at its own circuit path',
    );
  }
  return nodePath.substring(0, cut);
}

/// The canonical receipt recorded at [nodePath], or null when the node recorded
/// none (or recorded something that is not one JSON object).
Map<String, Object?>? _receiptAt(SiblingView siblings, String nodePath) {
  final raw = siblings.resultOf(nodePath)[kReleaseReceiptKey];
  if (raw == null) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// The per-package ladder facts, off the ladder receipt.
Map<String, Object?> _ladderFacts(Map<String, Map<String, Object?>> receipts) =>
    _objectAt(receipts[_kLadderStep]!, 'packages', 'the ladder receipt');

/// One package's ladder facts. A package the ladder never reported is LOUD.
Map<String, Object?> _ladderFactsFor(Map<String, Object?> facts, String name) {
  final record = facts[name];
  if (record is! Map<String, Object?>) {
    throw FormatException('the ladder receipt carries no facts for $name');
  }
  return record;
}

/// The published version a baseline-dependent leg measures against.
String _currentPublishedVersion(Map<String, Object?> facts, String name) {
  final current = _optionalStringAt(
    facts,
    'currentPublishedVersion',
    'the ladder receipt',
  );
  if (current == null) {
    throw FormatException(
      'the ladder receipt reports $name as published and names no version',
    );
  }
  return current;
}

/// The five wave facts a preflight and its irreversible run must agree on,
/// in the wave's own dependency-first order.
List<Map<String, Object?>> _waveFacts(Map<String, Object?> json, String what) =>
    [
      for (final package in _objectListAt(json, 'packages', what))
        <String, Object?>{
          'package': _stringAt(package, 'package', what),
          'localVersion': _stringAt(package, 'localVersion', what),
          'rung': _stringAt(package, 'rung', what),
          'dependencies': _stringListAt(package, 'dependencies', what),
          'tag': _stringAt(package, 'tag', what),
        },
    ];

/// Where two wave answers first disagree — the ONE record an operator needs,
/// rather than two whole wave dumps a bounded failure reason would clip.
String _firstWaveDifference(
  List<Map<String, Object?>> expected,
  List<Map<String, Object?>> actual,
) {
  for (var i = 0; i < expected.length && i < actual.length; i++) {
    if (jsonEncode(expected[i]) == jsonEncode(actual[i])) continue;
    return 'position $i: preflight ${jsonEncode(expected[i])}, published '
        '${jsonEncode(actual[i])}';
  }
  return 'its length: the preflight carried ${expected.length} package(s), the '
      'run carried ${actual.length}';
}

/// Why a scrub refused, in the vended result's own words.
String _scrubReason(Map<String, Object?> json, Object? floors) {
  final hits = json['hits'];
  final parts = <String>[
    if (hits is List && hits.isNotEmpty) '${hits.length} internal ref(s)',
    if (floors is Map<String, Object?> && floors['message'] is String)
      floors['message']! as String,
  ];
  return parts.isEmpty ? 'the gate reported clean: false' : parts.join('; ');
}

/// The diagnostic a refusal quotes: stderr when there is any, else stdout,
/// tail-cut so the cause survives the reason cap.
String _diagnostic(ReleaseCommandInvocation invocation) {
  final err = invocation.stderr.trim();
  final out = invocation.stdout.trim();
  final detail = err.isNotEmpty ? err : out;
  return detail.isEmpty
      ? '<no output captured>'
      : landReasonTail(detail, _kReleaseDiagnosticTailChars);
}

/// The one JSON object [stdout] carries, or null when it carries none, more
/// than one, or something that is not an object.
Map<String, Object?>? _decodeSingleObject(String stdout) {
  final lines = [
    for (final line in const LineSplitter().convert(stdout))
      if (line.trim().isNotEmpty) line,
  ];
  if (lines.length != 1) return null;
  try {
    final decoded = jsonDecode(lines.single);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}

bool _sameSet(List<String> left, List<String> right) =>
    left.toSet().length == left.length &&
    right.toSet().length == right.length &&
    left.toSet().containsAll(right) &&
    right.toSet().containsAll(left);

bool _sameOrder(List<String> left, List<String> right) =>
    left.length == right.length &&
    [
      for (var i = 0; i < left.length; i++) left[i] == right[i],
    ].every((equal) => equal);

Never _malformed(String message) => throw FormatException(message);

Map<String, Object?> _objectAt(
  Map<String, Object?> source,
  String key,
  String what,
) {
  final value = source[key];
  if (value is! Map<String, Object?>) {
    _malformed('$what carries no `$key` object');
  }
  return value;
}

List<Map<String, Object?>> _objectListAt(
  Map<String, Object?> source,
  String key,
  String what,
) {
  final value = source[key];
  if (value is! List) _malformed('$what carries no `$key` list');
  final out = <Map<String, Object?>>[];
  for (final entry in value) {
    if (entry is! Map<String, Object?>) {
      _malformed('$what `$key` holds an entry that is not an object');
    }
    out.add(entry);
  }
  return out;
}

List<String> _stringListAt(
  Map<String, Object?> source,
  String key,
  String what,
) {
  final value = source[key];
  if (value is! List) _malformed('$what carries no `$key` list');
  final out = <String>[];
  for (final entry in value) {
    if (entry is! String) {
      _malformed('$what `$key` holds an entry that is not a string');
    }
    out.add(entry);
  }
  return out;
}

String _stringAt(Map<String, Object?> source, String key, String what) {
  final value = source[key];
  if (value is! String) _malformed('$what carries no `$key` string');
  return value;
}

String? _optionalStringAt(
  Map<String, Object?> source,
  String key,
  String what,
) {
  if (!source.containsKey(key)) {
    _malformed('$what carries no `$key` entry');
  }
  final value = source[key];
  if (value == null) return null;
  if (value is! String) _malformed('$what `$key` is not a string');
  return value;
}

bool _boolAt(Map<String, Object?> source, String key, String what) {
  final value = source[key];
  if (value is! bool) _malformed('$what carries no `$key` boolean');
  return value;
}

int _intAt(Map<String, Object?> source, String key, String what) {
  final value = source[key];
  if (value is! int) _malformed('$what carries no `$key` integer');
  return value;
}
